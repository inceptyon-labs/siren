import AVFoundation
import Observation

/// What's in a downloaded audio file: its pauses (for trim silence) and its loudness (for the voice
/// print), read with `AVAssetReader` a chunk at a time, starting where you're listening.
/// Kept in Caches, by file name and size.
@MainActor @Observable
final class SirenAudioScan {
  static let shared = SirenAudioScan()

  struct FileScan: Codable {
    /// Chunks read so far (chunk N covers N × `chunk` seconds onward).
    var chunks: Set<Int> = []
    /// Pauses long enough to trim, sorted, in the file's seconds.
    var pauses: [Range<Double>] = []
    /// Loudness every `bin` seconds, in dBFS; nil where not read yet.
    var loudness: [Float?] = []
    /// How many chunks the file has, once its length is known.
    var chunkCount: Int?

    var isComplete: Bool { chunkCount.map { chunks.count >= $0 } ?? false }
  }

  nonisolated static let chunk = 120.0
  nonisolated static let bin = 2.0

  /// Goes up as chunks are read, so the voice print redraws.
  private(set) var revision = 0
  @ObservationIgnored private var scans: [String: FileScan] = [:]
  @ObservationIgnored private var running: Set<String> = []
  /// Cache files are written in order, so a later chunk's snapshot is never replaced by an earlier one.
  @ObservationIgnored private let writer = DispatchQueue(label: "siren.audio-scan.writer", qos: .utility)
  @ObservationIgnored private let folder = URL.cachesDirectory.appending(
    path: "siren-scan",
    directoryHint: .isDirectory
  )

  /// The pause around `time` in the file, if that part has been read.
  func pause(in file: URL, at time: Double) -> Range<Double>? {
    guard let key = Self.key(file), let scan = scan(key) else { return nil }
    let pauses = scan.pauses
    var low = 0
    var high = pauses.count
    while low < high {
      let mid = (low + high) / 2
      if pauses[mid].upperBound <= time { low = mid + 1 } else { high = mid }
    }
    return low < pauses.count && pauses[low].contains(time) ? pauses[low] : nil
  }

  /// The file's loudness every `bin` seconds so far (nil where not read yet).
  func loudness(in file: URL) -> [Float?]? {
    Self.key(file).flatMap { scan($0)?.loudness }
  }

  /// Reads the file from the chunk at `time` to the end, then the start, unless it's read or
  /// being read.
  func scan(_ file: URL, from time: Double) {
    guard let key = Self.key(file), !running.contains(key), scan(key)?.isComplete != true else { return }
    Task { await run(file, key: key, from: time) }
  }

  /// Reads each file in turn, all of it, each from `from` seconds into it (then its start),
  /// skipping ones read or being read.
  func scanAll(_ files: [(url: URL, from: Double)]) async {
    for file in files {
      guard !Task.isCancelled else { return }
      guard let key = Self.key(file.url), !running.contains(key), scan(key)?.isComplete != true else { continue }
      await run(file.url, key: key, from: file.from)
    }
  }

  private func run(_ file: URL, key: String, from time: Double) async {
    guard !running.contains(key) else { return }
    running.insert(key)
    defer { running.remove(key) }
    let asset = AVURLAsset(url: file)
    guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else { return }
    let count = Int((duration / Self.chunk).rounded(.up))
    let done = scan(key)?.chunks ?? []
    let first = min(max(Int(time / Self.chunk), 0), count - 1)
    for index in Array(first..<count) + Array(0..<first) where !done.contains(index) {
      guard !Task.isCancelled else { return }
      let start = Double(index) * Self.chunk
      let range = start..<min(start + Self.chunk, duration)
      guard let read = await Task.detached(priority: .utility, operation: { await Self.read(asset, range) }).value
      else { return }
      merge(read, chunk: index, of: count, into: key, duration: duration)
    }
  }

  // MARK: Reading

  private struct Read: Sendable {
    var pauses: [Range<Double>]
    var loudness: [(bin: Int, level: Float)]
  }

  /// Decodes `range` of the file to 16 kHz mono and measures it in 20 ms blocks.
  nonisolated private static func read(_ asset: AVURLAsset, _ range: Range<Double>) async -> Read? {
    guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
      let reader = try? AVAssetReader(asset: asset)
    else { return nil }
    let rate = 16_000.0
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false,
        AVLinearPCMIsBigEndianKey: false,
        AVNumberOfChannelsKey: 1,
        AVSampleRateKey: rate,
      ]
    )
    reader.add(output)
    reader.timeRange = CMTimeRange(
      start: CMTime(seconds: range.lowerBound, preferredTimescale: 1000),
      end: CMTime(seconds: range.upperBound, preferredTimescale: 1000)
    )
    guard reader.startReading() else { return nil }

    var detector = SirenPauseDetector(start: range.lowerBound)
    let block = Int(rate * SirenPauseDetector.block)
    var pending: [Float] = []
    var time = range.lowerBound
    var bins: [Int: (sum: Double, count: Int)] = [:]
    while let sample = output.copyNextSampleBuffer() {
      if Task.isCancelled { return nil }
      guard let data = CMSampleBufferGetDataBuffer(sample) else { continue }
      let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
      if pending.isEmpty, start.isFinite { time = start }
      let length = CMBlockBufferGetDataLength(data)
      var floats = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
      floats.withUnsafeMutableBytes {
        _ = CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
      }
      pending += floats
      var used = 0
      while pending.count - used >= block {
        var sum: Float = 0
        for i in used..<(used + block) { sum += pending[i] * pending[i] }
        let meanSquare = sum / Float(block)
        detector.add(time: time, meanSquare: meanSquare, seconds: SirenPauseDetector.block)
        let bin = Int(time / bin)
        bins[bin, default: (0, 0)].sum += Double(meanSquare)
        bins[bin, default: (0, 0)].count += 1
        time += SirenPauseDetector.block
        used += block
      }
      pending.removeFirst(used)
    }
    guard reader.status == .completed else { return nil }
    detector.finish(at: time, atEdge: true)
    let loudness = bins.map {
      (bin: $0.key, level: 10 * log10(max(Float($0.value.sum / Double($0.value.count)), 1e-12)))
    }
    return Read(pauses: detector.pauses, loudness: loudness)
  }

  // MARK: Storage

  private func merge(_ read: Read, chunk: Int, of count: Int, into key: String, duration: Double) {
    var scan = scan(key) ?? FileScan()
    scan.chunks.insert(chunk)
    scan.chunkCount = count
    // A pause cut by a chunk edge joins its other half.
    var pauses = scan.pauses + read.pauses
    pauses.sort { $0.lowerBound < $1.lowerBound }
    var joined: [Range<Double>] = []
    for pause in pauses {
      if let last = joined.last, pause.lowerBound <= last.upperBound + SirenPauseDetector.block * 1.5 {
        joined[joined.count - 1] = last.lowerBound..<max(last.upperBound, pause.upperBound)
      } else {
        joined.append(pause)
      }
    }
    // Short pieces are kept only at chunk edges, where the rest may be in a chunk not read yet.
    func atEdge(_ time: Double) -> Bool {
      abs(time - (time / Self.chunk).rounded() * Self.chunk) < SirenPauseDetector.block * 1.5
    }
    scan.pauses = joined.filter {
      $0.upperBound - $0.lowerBound >= SirenPauseDetector.shortestPause || atEdge($0.lowerBound)
        || atEdge($0.upperBound)
    }
    let bins = Int((duration / Self.bin).rounded(.up))
    if scan.loudness.count != bins { scan.loudness = Array(repeating: nil, count: bins) }
    for (bin, level) in read.loudness where scan.loudness.indices.contains(bin) {
      scan.loudness[bin] = level
    }
    scans[key] = scan
    revision += 1
    let file = folder.appending(path: key + ".json")
    let folder = folder
    if let data = try? JSONEncoder().encode(scan) {
      writer.async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
      }
    }
  }

  private func scan(_ key: String) -> FileScan? {
    if let scan = scans[key] { return scan }
    guard let data = try? Data(contentsOf: folder.appending(path: key + ".json")),
      let scan = try? JSONDecoder().decode(FileScan.self, from: data)
    else { return nil }
    scans[key] = scan
    return scan
  }

  /// The file's path in the shared downloads container (server, book and file) and its size. The
  /// path from there on stays put, while the container's own path can change.
  private static func key(_ file: URL) -> String? {
    guard file.isFileURL,
      let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
    else { return nil }
    var path = file.standardizedFileURL.path
    if let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.com.inceptyon.siren"
    )?.standardizedFileURL.path, path.hasPrefix(container) {
      path.removeFirst(container.count)
    }
    let name = path.map { $0.isLetter || $0.isNumber || $0 == "." ? String($0) : "_" }.joined()
    return "\(name)-\(size)"
  }
}

/// Finds pauses in a run of 20 ms levels. The threshold follows the narrator: 30 dB under recent
/// speech, between −60 and −38 dBFS.
nonisolated struct SirenPauseDetector {
  static let block = 0.02
  /// Shorter than this is a breath between words.
  static let shortestPause = 0.6

  private(set) var pauses: [Range<Double>] = []
  private var pauseStart: Double?
  private var speech: Float = -20
  /// Where the read starts: a pause from there may continue before it.
  private let start: Double

  init(start: Double) {
    self.start = start
  }

  mutating func add(time: Double, meanSquare: Float, seconds: Double) {
    let level = 10 * log10(max(meanSquare, 1e-12))
    speech = level > speech ? level : max(speech - Float(seconds) * 0.5, -50)
    let threshold = min(max(speech - 30, -60), -38)
    if level < threshold {
      if pauseStart == nil { pauseStart = time }
    } else {
      finish(at: time)
    }
  }

  /// Ends a pause at `time`. A short one is kept where it touches the edge of the read, since the
  /// rest of it may be in the next chunk.
  mutating func finish(at time: Double, atEdge: Bool = false) {
    if let pauseStart, time > pauseStart,
      time - pauseStart >= Self.shortestPause || atEdge || pauseStart <= start + Self.block / 2
    {
      pauses.append(pauseStart..<time)
    }
    pauseStart = nil
  }
}
