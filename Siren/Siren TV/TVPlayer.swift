import API
import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// Plays a book on the Apple TV: opens an Audiobookshelf playback session, streams its tracks in
/// order, syncs progress every fifteen seconds and closes the session when you stop. Streaming
/// only; nothing is downloaded.
@MainActor @Observable
final class TVPlayer {
  static let shared = TVPlayer()

  struct Chapter: Identifiable, Equatable {
    let id: Int
    let start: Double
    let end: Double
    let title: String
  }

  struct Book: Equatable {
    let itemID: String
    let serverID: String
    let title: String
    let author: String
    let coverURL: URL?
    let duration: Double
    let chapters: [Chapter]
  }

  private(set) var book: Book?
  private(set) var isPlaying = false
  private(set) var isLoading = false
  /// Where you are in the book, in seconds.
  private(set) var time: Double = 0
  private(set) var rate: Float = 1
  var error: String?
  /// The full-screen player is showing.
  var isShowing = false

  static let rates: [Float] = [1, 1.25, 1.5, 1.75, 2, 0.75]
  static let skip: Double = 30

  var chapter: Chapter? {
    book?.chapters.last { $0.start <= time + 0.5 }
  }

  @ObservationIgnored private let player = AVQueuePlayer()
  @ObservationIgnored private var sessionID: String?
  @ObservationIgnored private var tracks: [(start: Double, duration: Double, url: URL)] = []
  @ObservationIgnored private var headers: [String: String] = [:]
  @ObservationIgnored private var currentTrack = 0
  /// Which track each queued item plays.
  @ObservationIgnored private var trackOf: [ObjectIdentifier: Int] = [:]
  @ObservationIgnored private var timeObserver: Any?
  @ObservationIgnored private var listened = 0.0
  @ObservationIgnored private var lastTick: Date?
  @ObservationIgnored private var lastSync = Date.distantPast
  @ObservationIgnored private var artwork: MPMediaItemArtwork?
  /// Goes up with each start and stop, so a start that returns late is dropped.
  @ObservationIgnored private var generation = 0

  private init() {
    player.automaticallyWaitsToMinimizeStalling = true
    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 2), queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    NotificationCenter.default.addObserver(
      forName: AVPlayerItem.failedToPlayToEndTimeNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let item = notification.object as? AVPlayerItem
      MainActor.assumeIsolated { self?.itemFailed(item) }
    }
    NotificationCenter.default.addObserver(
      forName: AVPlayerItem.didPlayToEndTimeNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let item = notification.object as? AVPlayerItem
      MainActor.assumeIsolated { self?.itemEnded(item) }
    }
    setUpRemoteCommands()
  }

  // MARK: Playing

  /// Starts the book where you left off, or brings up the one already playing.
  func play(itemID: String) async {
    isShowing = true
    if book?.itemID == itemID, sessionID != nil {
      if !isPlaying { resume() }
      return
    }
    await stop()
    guard let server = Audiobookshelf.shared.authentication.server else { return }
    generation += 1
    let current = generation
    isLoading = true
    defer { if current == generation { isLoading = false } }
    do {
      let session = try await Audiobookshelf.shared.sessions.start(itemID: itemID, sessionType: .tv, timeout: 30)
      // Stopped, or switched to someone else, while it started. Its session is closed only on its
      // own server's sign-in; after a switch, Audiobookshelf times it out.
      let sameServer = Audiobookshelf.shared.authentication.server?.id == server.id
      guard current == generation, sameServer else {
        if sameServer { try? await Audiobookshelf.shared.sessions.close(session.id) }
        return
      }
      guard case .book(let item) = session.libraryItem, let audio = session.audioTracks, !audio.isEmpty else {
        throw TVPlayerError.nothingToPlay
      }
      sessionID = session.id
      headers = server.customHeaders
      let base = server.activeURL
      tracks = audio.sorted { $0.startOffset < $1.startOffset }.map {
        ($0.startOffset, $0.duration, base.appendingPathComponent("public/session/\(session.id)/track/\($0.index)"))
      }
      book = Book(
        itemID: itemID,
        serverID: server.id,
        title: item.title,
        author: item.authorName ?? "",
        coverURL: item.coverURL(),
        duration: session.duration,
        chapters: (session.chapters ?? []).map { Chapter(id: $0.id, start: $0.start, end: $0.end, title: $0.title) }
      )
      error = nil
      try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
      try? AVAudioSession.sharedInstance().setActive(true)
      load(at: session.currentTime, play: true)
      loadArtwork()
    } catch {
      guard current == generation else { return }
      self.error = String(localized: "Couldn't play this book. \(error.localizedDescription)")
    }
  }

  func toggle() {
    isPlaying ? pause() : resume()
  }

  func pause() {
    player.pause()
    isPlaying = false
    Task { await sync() }
    updateNowPlaying()
  }

  func resume() {
    guard let book else { return }
    // After the last track, or a track that failed, the queue is rebuilt (from the start once
    // the book is finished).
    if !tracks.isEmpty, player.items().isEmpty || player.currentItem?.status == .failed {
      error = nil
      load(at: time >= book.duration - 1 ? 0 : time, play: true)
      return
    }
    player.playImmediately(atRate: rate)
    isPlaying = true
    updateNowPlaying()
  }

  func skip(by seconds: Double) {
    seek(to: time + seconds)
  }

  func seek(to target: Double) {
    guard let book else { return }
    let clamped = min(max(target, 0), max(book.duration - 1, 0))
    if let index = tracks.lastIndex(where: { $0.start <= clamped }), index == currentTrack,
      let item = player.currentItem
    {
      item.seek(to: CMTime(seconds: clamped - tracks[index].start, preferredTimescale: 1000), completionHandler: nil)
      time = clamped
    } else {
      load(at: clamped, play: isPlaying)
    }
    updateNowPlaying()
  }

  func setRate(_ rate: Float) {
    self.rate = rate
    if isPlaying { player.rate = rate }
    updateNowPlaying()
  }

  /// Saves where you are and closes the session.
  func stop() async {
    generation += 1
    isLoading = false
    guard book != nil else { return }
    player.pause()
    isPlaying = false
    await sync()
    if let sessionID { try? await Audiobookshelf.shared.sessions.close(sessionID) }
    player.removeAllItems()
    trackOf = [:]
    sessionID = nil
    tracks = []
    book = nil
    time = 0
    artwork = nil
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  #if DEBUG
  /// The demo's player: a book and a position, no session or sound.
  func showDemo(_ book: Book, at time: Double) {
    self.book = book
    self.time = time
  }
  #endif

  // MARK: Tracks

  /// Queues the tracks from the one holding `bookTime`, positioned there.
  private func load(at bookTime: Double, play: Bool) {
    guard !tracks.isEmpty else { return }
    player.removeAllItems()
    trackOf = [:]
    let index = tracks.lastIndex { $0.start <= bookTime } ?? 0
    currentTrack = index
    for (offset, track) in tracks[index...].enumerated() {
      let asset = AVURLAsset(
        url: track.url,
        options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers]
      )
      let item = AVPlayerItem(asset: asset)
      trackOf[ObjectIdentifier(item)] = index + offset
      player.insert(item, after: nil)
    }
    let offset = max(bookTime - tracks[index].start, 0)
    player.currentItem?.seek(to: CMTime(seconds: offset, preferredTimescale: 1000), completionHandler: nil)
    time = bookTime
    if play {
      player.playImmediately(atRate: rate)
      isPlaying = true
    }
    updateNowPlaying()
  }

  /// A track that couldn't be fetched or decoded: say so, and Play tries again from here.
  private func itemFailed(_ item: AVPlayerItem?) {
    guard let item, trackOf[ObjectIdentifier(item)] != nil else { return }
    player.pause()
    isPlaying = false
    let reason = item.error?.localizedDescription ?? ""
    error = String(localized: "Playback stopped. \(reason)")
    updateNowPlaying()
  }

  /// The queue moves on by itself; after the last track the book is done.
  private func itemEnded(_ item: AVPlayerItem?) {
    guard let item, trackOf[ObjectIdentifier(item)] == tracks.count - 1 else { return }
    isPlaying = false
    time = book?.duration ?? time
    Task { await sync() }
    updateNowPlaying()
  }

  private func tick() {
    let now = Date()
    if isPlaying, let lastTick { listened += min(now.timeIntervalSince(lastTick), 2) }
    lastTick = isPlaying ? now : nil
    guard book != nil, let item = player.currentItem else { return }
    if let index = trackOf[ObjectIdentifier(item)] { currentTrack = index }
    guard tracks.indices.contains(currentTrack) else { return }
    let seconds = item.currentTime().seconds
    if seconds.isFinite { time = tracks[currentTrack].start + seconds }
    if item.status == .failed, error == nil { itemFailed(item) }
    if isPlaying, player.timeControlStatus == .paused, player.rate == 0 { isPlaying = false }
    if now.timeIntervalSince(lastSync) >= 15 { Task { await sync() } }
  }

  private func sync() async {
    guard let sessionID else { return }
    lastSync = Date()
    let listened = listened
    self.listened = 0
    do {
      try await Audiobookshelf.shared.sessions.sync(sessionID, timeListened: listened, currentTime: time)
    } catch {
      self.listened += listened
    }
  }

  // MARK: Remote and Now Playing

  private func setUpRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.resume() }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.pause() }
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.toggle() }
      return .success
    }
    center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skip)]
    center.skipForwardCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.skip(by: Self.skip) }
      return .success
    }
    center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skip)]
    center.skipBackwardCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.skip(by: -Self.skip) }
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      let position = event.positionTime
      MainActor.assumeIsolated { self?.seek(to: position) }
      return .success
    }
  }

  private func updateNowPlaying() {
    guard let book else { return }
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: book.title,
      MPMediaItemPropertyArtist: book.author,
      MPMediaItemPropertyPlaybackDuration: book.duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
    ]
    if let chapter { info[MPMediaItemPropertyAlbumTitle] = chapter.title }
    if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
  }

  private func loadArtwork() {
    guard let url = book?.coverURL else { return }
    Task {
      guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else {
        return
      }
      artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      updateNowPlaying()
    }
  }
}

enum TVPlayerError: LocalizedError {
  case nothingToPlay

  var errorDescription: String? {
    String(localized: "It has no audio to play.")
  }
}
