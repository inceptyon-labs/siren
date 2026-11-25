import AVFoundation

/// What's in a downloaded audio file: its pauses (for trim silence) and its loudness (for the voice
/// print), read with `AVAssetReader` a chunk at a time, starting where you're listening.
/// Kept in Caches, by file name and size.
@MainActor
final class SirenAudioScan {
  static let shared = SirenAudioScan()

  struct FileScan: Codable {
    /// Chunks read so far (chunk N covers N × `chunk` seconds onward).
    var chunks: Set<Int> = []
    /// Pauses long enough to trim, sorted, in the file's seconds.
    var pauses: [Range<Double>] = []
    /// Loudness every `bin` seconds, in dBFS; nil where not read yet.
    var loudness: [Float?] = []
  }

  nonisolated static let chunk = 120.0
  nonisolated static let bin = 2.0

  private var scans: [String: FileScan] = [:]
  private var running: Set<String> = []
  private let folder = URL.cachesDirectory.appending(path: "siren-scan", directoryHint: .isDirectory)

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

  /// Reads the file from the chunk at `time` to the end, then the start, unless it's read or
  /// being read.
  func scan(_ file: URL, from time: Double) {
    guard let key = Self.key(file), !running.contains(key) else { return }
    let done = scan(key)?.chunks ?? []
    let asset = AVURLAsset(url: file)
    running.insert(key)
    Task {
      defer { running.remove(key) }
      guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else { return }
      let count = Int((duration / Self.chunk).rounded(.up))
      let first = min(max(Int(time / Self.chunk), 0), count - 1)
      let order = Array(first..<count) + Array(0..<first)
      for index in order where !done.contains(index) {
        let start = Double(index) * Self.chunk
        let range = start..<min(start + Self.chunk, duration)
        guard let read = await Task.detached(priority: .utility, operation: { await Self.read(asset, range) }).value
        else {
          return
        }
        merge(read, chunk: index, into: key, duration: duration)
      }
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

    var detector = SirenPauseDetector()
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
    detector.finish(at: time)
    let loudness = bins.map {
      (bin: $0.key, level: 10 * log10(max(Float($0.value.sum / Double($0.value.count)), 1e-12)))
    }
    return Read(pauses: detector.pauses, loudness: loudness)
  }

  // MARK: Storage

  private func merge(_ read: Read, chunk: Int, into key: String, duration: Double) {
    var scan = scan(key) ?? FileScan()
    scan.chunks.insert(chunk)
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
    scan.pauses = joined
    let bins = Int((duration / Self.bin).rounded(.up))
    if scan.loudness.count != bins { scan.loudness = Array(repeating: nil, count: bins) }
    for (bin, level) in read.loudness where scan.loudness.indices.contains(bin) {
      scan.loudness[bin] = level
    }
    scans[key] = scan
    let file = folder.appending(path: key + ".json")
    let folder = folder
    if let data = try? JSONEncoder().encode(scan) {
      Task.detached(priority: .utility) {
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

  /// File name and size: the same download keeps both, while the app's container path can change.
  private static func key(_ file: URL) -> String? {
    guard file.isFileURL,
      let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
    else { return nil }
    let name = file.lastPathComponent.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
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

  mutating func finish(at time: Double) {
    if let pauseStart, time - pauseStart >= Self.shortestPause { pauses.append(pauseStart..<time) }
    pauseStart = nil
  }
}
