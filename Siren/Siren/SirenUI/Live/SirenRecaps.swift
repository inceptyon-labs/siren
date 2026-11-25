import API
import AVFoundation
import Foundation
import FoundationModels
import Models
import Speech

/// "Previously on": when you come back to a book after three days or more, a few sentences on what
/// you last heard. While you listen to a downloaded book, each ten minutes heard is transcribed and
/// summarized on the device (Apple Intelligence), so the recap is ready when you return and covers
/// only what you've heard. Coming back to a book with nothing saved yet, the last ten minutes are
/// summarized then, and the recap appears a little after the book starts.
@MainActor @Observable
final class SirenRecaps {
  static let shared = SirenRecaps()

  struct Recap: Identifiable, Equatable {
    /// The sign-in (household profile) it belongs to.
    let scope: String
    let bookID: String
    let title: String
    /// Oldest first.
    let summaries: [String]
    /// The book's language, for reading it aloud.
    let language: String?

    var id: String { bookID }
  }

  /// The recap to show in the player, set when you come back to a book.
  var pending: Recap?

  static var isOn: Bool { UserDefaults.standard.object(forKey: SirenSettings.recaps) as? Bool ?? true }

  /// iOS 26 with Apple Intelligence on, and speech transcription on this device.
  static var isSupported: Bool {
    guard #available(iOS 26.0, *) else { return false }
    return SystemLanguageModel.default.isAvailable && SpeechTranscriber.isAvailable
  }

  private struct Log: Codable {
    var lastPlayed: Date?
    var segments: [Segment] = []
    /// Where listening not yet summarized began, kept across pauses.
    var unsummarizedFrom: Double?
  }

  /// One person's copy of a book: profiles on the same server share book IDs.
  private struct Key: Hashable {
    let scope: String
    let bookID: String
  }

  private struct Segment: Codable {
    let start: Double
    let end: Double
    let summary: String
  }

  private static let away: TimeInterval = 3 * 24 * 3600
  private static let segment: TimeInterval = 600

  @ObservationIgnored private var timer: Timer?
  /// The book playing at the last step.
  @ObservationIgnored private var playing: Key?
  /// A book you came back to with nothing saved: its recap is made now, retried until it works.
  @ObservationIgnored private var owed: Key?
  @ObservationIgnored private var logs: [Key: Log] = [:]
  @ObservationIgnored private var isSummarizing = false
  @ObservationIgnored private var failedAt: [Key: Date] = [:]
  @ObservationIgnored private var savedAt = Date.distantPast
  @ObservationIgnored private let folder = URL.applicationSupportDirectory.appending(
    path: "siren-recaps",
    directoryHint: .isDirectory
  )

  private init() {}

  /// The signed-in connection, so each profile keeps its own recaps.
  private static var scope: String? {
    Audiobookshelf.shared.authentication.server.map { "\($0.id)" }
  }

  func start() {
    guard timer == nil else { return }
    let timer = Timer(timeInterval: 5, repeats: true) { _ in
      MainActor.assumeIsolated { SirenRecaps.shared.step() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func dismiss() {
    pending = nil
    owed = nil
  }

  private func step() {
    guard Self.isOn else { return dismiss() }
    guard Self.isSupported, let scope = Self.scope, let player = PlayerManager.shared.current,
      player.podcastID == nil
    else {
      playing = nil
      return
    }
    if pending.map({ $0.scope != scope }) == true { pending = nil }
    guard player.isPlaying else {
      playing = nil
      return
    }
    let key = Key(scope: scope, bookID: player.id)
    let now = Date()
    let position = player.playbackProgress.totalProgress * player.playbackProgress.total
    var log = log(key)

    if playing != key {
      // Just started, or came back to, this book.
      playing = key
      if pending?.bookID != key.bookID { pending = nil }
      owed = nil
      if let last = log.lastPlayed, now.timeIntervalSince(last) >= Self.away {
        let heard = log.segments.filter { $0.end <= position + 60 }.sorted { $0.end < $1.end }.suffix(3)
        if heard.last.map({ position - $0.end < Self.segment * 2 }) == true {
          let language = (try? LocalBook.fetch(bookID: key.bookID))?.language
          pending = Recap(
            scope: scope,
            bookID: key.bookID,
            title: player.title,
            summaries: heard.map(\.summary),
            language: language
          )
        } else if position >= 120 {
          owed = key
        }
      }
    }
    if owed == key {
      summarize(key, from: max(position - Self.segment, 0), to: position, show: player.title)
    }

    // Each ten minutes heard, summarized (at most the last fifteen, after a jump ahead).
    let summarized = log.segments.map(\.end).filter { $0 <= position + 1 }.max()
    if summarized == nil { log.unsummarizedFrom = min(log.unsummarizedFrom ?? position, position) }
    log.lastPlayed = now
    logs[key] = log
    if now.timeIntervalSince(savedAt) > 60 {
      save(key)
      savedAt = now
    }
    let covered = summarized ?? log.unsummarizedFrom ?? position
    if position - covered >= Self.segment {
      summarize(key, from: max(covered, position - Self.segment * 1.5), to: position, show: nil)
    }
  }

  /// Transcribes and summarizes `start` to `end` of a downloaded book, then shows the recap if
  /// `title` is set and the book is still playing for the same person.
  private func summarize(_ key: Key, from start: Double, to end: Double, show title: String?) {
    guard #available(iOS 26.0, *), !isSummarizing,
      failedAt[key].map({ Date().timeIntervalSince($0) > Self.segment }) ?? true,
      let book = try? LocalBook.fetch(bookID: key.bookID),
      let source = NarrationSource(downloaded: book.tracks)
    else { return }
    isSummarizing = true
    let language = book.language
    let bookTitle = book.title
    Task {
      defer { isSummarizing = false }
      guard let text = await Self.transcript(source, language: language, from: start, to: end),
        text.split(separator: " ").count >= 40,
        let summary = await Self.summary(of: text, title: bookTitle)
      else {
        failedAt[key] = Date()
        return
      }
      var log = log(key)
      log.segments.removeAll { $0.start < end && start < $0.end }
      log.segments.append(Segment(start: start, end: end, summary: summary))
      log.segments.sort { $0.end < $1.end }
      log.segments = Array(log.segments.suffix(24))
      log.unsummarizedFrom = nil
      logs[key] = log
      save(key)
      guard let title, owed == key else { return }
      owed = nil
      if Self.isOn, Self.scope == key.scope, PlayerManager.shared.current?.id == key.bookID {
        pending = Recap(scope: key.scope, bookID: key.bookID, title: title, summaries: [summary], language: language)
      }
    }
  }

  @available(iOS 26.0, *)
  private static func transcript(
    _ source: NarrationSource,
    language: String?,
    from start: Double,
    to end: Double
  )
    async -> String?
  {
    let preferred = BookLanguage.code(for: language).map { Locale(identifier: $0) } ?? Locale.current
    guard let locale = try? await ReadAlongAvailability.prepare(preferred: preferred) else { return nil }
    var words: [String] = []
    do {
      for try await word in NarrationTranscriber(locale: locale, source: source).words(from: start, playhead: { end }) {
        if word.start >= end { break }
        words.append(word.text)
      }
    } catch {
      return nil
    }
    return words.joined(separator: " ")
  }

  @available(iOS 26.0, *)
  private static func summary(of text: String, title: String) async -> String? {
    let instructions = """
      You recap a passage of an audiobook for a listener who heard it days ago and is about to \
      continue. In two or three short sentences of your own words, past tense, say what \
      happened and who was involved. Add nothing the passage doesn't say, and never guess \
      what comes next. No preamble, title or quotes.
      """
    // Low temperature keeps the small model close to the passage.
    let options = GenerationOptions(temperature: 0.2)
    // The model reads about 4,000 tokens at a time: long passages are recapped in parts, then joined.
    let words = text.split(separator: " ")
    var parts: [String] = []
    for start in stride(from: 0, to: words.count, by: 900) {
      let chunk = words[start..<min(start + 900, words.count)].joined(separator: " ")
      let session = LanguageModelSession(instructions: instructions)
      guard let reply = try? await session.respond(to: "A passage from \(title):\n\n\(chunk)", options: options)
      else { return nil }
      parts.append(reply.content)
    }
    guard parts.count > 1 else { return parts.first }
    let session = LanguageModelSession(
      instructions: """
        These recap consecutive parts of one audiobook passage. Join them into one recap of two or \
        three plain sentences, past tense, keeping the events that matter most. No preamble.
        """
    )
    return try? await session.respond(to: parts.joined(separator: "\n\n"), options: options).content
  }

  // MARK: Storage

  private func log(_ key: Key) -> Log {
    if let log = logs[key] { return log }
    let log = (try? Data(contentsOf: file(key))).flatMap { try? JSONDecoder().decode(Log.self, from: $0) } ?? Log()
    logs[key] = log
    return log
  }

  private func save(_ key: Key) {
    guard let log = logs[key], let data = try? JSONEncoder().encode(log) else { return }
    let file = file(key)
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
  }

  private func file(_ key: Key) -> URL {
    func safe(_ text: String) -> String {
      text.map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "_" }.joined()
    }
    return folder.appending(path: safe(key.scope), directoryHint: .isDirectory).appending(
      path: safe(key.bookID) + ".json"
    )
  }
}
