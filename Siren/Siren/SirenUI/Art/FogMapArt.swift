import OSLog
import SwiftUI

/// The player's map page for a book. Generates the map off the main thread (cached per book and
/// chapter layout), shows bare paper until it's ready, and recomputes the fog only when listening
/// moves to the next step of the route.
struct FogMapArt: View {
  let book: SirenBook
  /// Bookmarks as fractions of the book.
  var flags: [Double] = []

  @State private var map: FogMap?
  @State private var reveal: FogMapReveal?

  init(book: SirenBook, flags: [Double] = []) {
    self.book = book
    self.flags = flags
    let key = FogMap.Key(bookID: book.id, chapterStarts: book.chapterStarts)
    _map = State(initialValue: FogMapStore.shared.cached(key))
    _reveal = State(initialValue: FogMapStore.shared.cachedReveal(key))
  }

  var body: some View {
    let key = FogMap.Key(bookID: book.id, chapterStarts: book.chapterStarts)
    Group {
      if let map, map.key == key, let reveal {
        FogMapView(map: map, reveal: reveal, title: book.title, author: book.author) {
          RevealCover(book: book, progress: 1, cornerRadius: 0, shadow: false)
        }
      } else {
        FogInk.paper
          .aspectRatio(1, contentMode: .fit)
          .accessibilityLabel("Map of \(book.title)")
      }
    }
    .task(id: key) {
      let map = await FogMapStore.shared.map(for: key)
      let reveal = await FogMapStore.shared.reveal(revealKey(on: map), on: map)
      guard !Task.isCancelled else { return }
      self.map = map
      self.reveal = reveal
    }
    .task(id: map.map { revealKey(on: $0) }) {
      guard let map, map.key == key else { return }
      let wanted = revealKey(on: map)
      guard reveal?.key != wanted else { return }
      let next = await FogMapStore.shared.reveal(wanted, on: map)
      guard !Task.isCancelled else { return }
      reveal = next
    }
  }

  private func revealKey(on map: FogMap) -> FogMapReveal.Key {
    FogMapReveal.Key(
      step: map.step(at: book.progress),
      flags: flags,
      chapter: book.currentChapter,
      chapterTitle: book.chapterTitle
    )
  }
}

/// Generated maps and their latest reveal, kept for the last few books.
nonisolated final class FogMapStore: @unchecked Sendable {
  static let shared = FogMapStore()

  private let lock = NSLock()
  private var maps: [FogMap.Key: FogMap] = [:]
  private var reveals: [FogMap.Key: FogMapReveal] = [:]
  private var recent: [FogMap.Key] = []
  private var running: [FogMap.Key: Task<FogMap, Never>] = [:]
  private let log = Logger(subsystem: "com.inceptyon.siren", category: "FogMap")

  func cached(_ key: FogMap.Key) -> FogMap? { lock.withLock { maps[key] } }

  func cachedReveal(_ key: FogMap.Key) -> FogMapReveal? { lock.withLock { reveals[key] } }

  func map(for key: FogMap.Key) async -> FogMap {
    if let hit = cached(key) { return hit }
    let task = lock.withLock {
      if let running = running[key] { return running }
      let log = log
      let task = Task.detached(priority: .userInitiated) {
        let start = ContinuousClock.now
        let map = FogMapGenerator.generate(key)
        let elapsed = (ContinuousClock.now - start) / .milliseconds(1)
        log.info("Generated map (\(key.chapterStarts.count) chapters) in \(elapsed, format: .fixed(precision: 1)) ms")
        _ = FogMapTextures.grain
        _ = FogMapTextures.stains
        return map
      }
      running[key] = task
      return task
    }
    let map = await task.value
    lock.withLock {
      running[key] = nil
      guard maps[key] == nil else { return }
      maps[key] = map
      recent.append(key)
      if recent.count > 6 {
        let old = recent.removeFirst()
        maps[old] = nil
        reveals[old] = nil
      }
    }
    return map
  }

  func reveal(_ key: FogMapReveal.Key, on map: FogMap) async -> FogMapReveal {
    if let hit = cachedReveal(map.key), hit.key == key { return hit }
    let reveal = await Task.detached(priority: .userInitiated) { map.reveal(key) }.value
    lock.withLock {
      if maps[map.key] != nil { reveals[map.key] = reveal }
    }
    return reveal
  }
}
