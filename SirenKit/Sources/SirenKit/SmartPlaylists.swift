import API
import Foundation
import Observation

/// Your smart playlists. The definitions live in iCloud key-value storage, so they follow your
/// Apple ID to every device; the books are worked out against the current library each time.
/// One can also be saved to an Audiobookshelf playlist, so other apps see it and Home can pin it.
@MainActor @Observable
public final class SmartPlaylists {
  public static let shared = SmartPlaylists()

  public private(set) var all: [SmartPlaylist] = []

  private static let key = "siren.smartPlaylists"
  @ObservationIgnored private let store = NSUbiquitousKeyValueStore.default
  @ObservationIgnored private var lastSync: (library: String, at: Date)?

  private init() {
    load()
    NotificationCenter.default.addObserver(
      forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: store,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated { SmartPlaylists.shared.load() }
    }
    store.synchronize()
  }

  public func playlist(_ id: UUID) -> SmartPlaylist? {
    all.first { $0.id == id }
  }

  public func save(_ playlist: SmartPlaylist) {
    if let index = all.firstIndex(where: { $0.id == playlist.id }) {
      all[index] = playlist
    } else {
      all.append(playlist)
    }
    write()
  }

  public func delete(_ id: UUID) {
    all.removeAll { $0.id == id }
    write()
  }

  private func load() {
    guard let data = store.data(forKey: Self.key),
      let saved = try? JSONDecoder().decode([SmartPlaylist].self, from: data)
    else { return }
    all = saved
  }

  private func write() {
    guard let data = try? JSONEncoder().encode(all) else { return }
    store.set(data, forKey: Self.key)
    store.synchronize()
  }

  // MARK: Books

  /// The playlist's books in the current library. Audiobookshelf applies its most selective rule;
  /// the device checks them all.
  public func books(for playlist: SmartPlaylist) async throws -> [Book] {
    let filterData: FilterData? =
      if let cached = Audiobookshelf.shared.filterData.cached() {
        cached
      } else {
        try? await Audiobookshelf.shared.filterData.fetch()
      }
    guard let libraryID = Audiobookshelf.shared.libraries.current?.id else { return [] }
    var query = ["minified": "1"]
    if let filter = playlist.serverFilter(filterData) { query["filter"] = filter }
    let items: Items = try await Audiobookshelf.shared.send("/api/libraries/\(libraryID)/items", query: query)
    let library = items.results

    var progress: [String: (progress: Double, isFinished: Bool)] = [:]
    if playlist.rules.contains(where: { if case .progress = $0 { true } else { false } }) {
      for item in try await MyProgress.books() {
        progress[item.libraryItemId] = (item.progress, item.isFinished)
      }
    }

    var ratings: [String: Double] = [:]
    if playlist.usesRatings {
      let asins = library.compactMap(\.media.metadata.asin)
      await AudibleRatings.shared.load(asins)
      for asin in asins {
        if let rating = AudibleRatings.shared.rating(for: asin) { ratings[asin] = rating.average }
      }
    }
    return playlist.books(from: library, context: .init(progress: progress, ratings: ratings))
  }

  /// A library's books, all of them (no `limit`).
  nonisolated private struct Items: Decodable, Sendable {
    let results: [Book]
  }

  // MARK: On the server

  /// Where the Audiobookshelf playlist ID is kept: per server (this sign-in's storage) and library,
  /// since a playlist belongs to one library.
  private func savedKey(_ id: UUID) -> String? {
    guard let library = Audiobookshelf.shared.libraries.current?.id else { return nil }
    return "siren.smartPlaylist.\(id.uuidString).\(library)"
  }

  /// The Audiobookshelf playlist this one was saved to, in the current library.
  public func savedPlaylistID(_ id: UUID) -> String? {
    guard let key = savedKey(id) else { return nil }
    return Audiobookshelf.shared.authentication.server?.storage.string(forKey: key)
  }

  /// Creates or updates the Audiobookshelf playlist with these books. Returns its ID.
  @discardableResult
  public func saveToServer(_ playlist: SmartPlaylist, books: [Book]) async throws -> String {
    let ids = books.map(\.id)
    if let existing = savedPlaylistID(playlist.id) {
      do {
        return try await Audiobookshelf.shared.playlists.update(playlistID: existing, name: playlist.name, items: ids)
          .id
      } catch {
        // Deleted on the server: make it again below. Anything else is a real failure.
        guard (try? await Audiobookshelf.shared.playlists.fetch(id: existing)) == nil else { throw error }
      }
    }
    // Audiobookshelf won't create an empty playlist.
    guard !ids.isEmpty else { throw SaveError.empty }
    let created = try await Audiobookshelf.shared.playlists.create(name: playlist.name, items: ids)
    if let key = savedKey(playlist.id) {
      Audiobookshelf.shared.authentication.server?.storage.set(created.id, forKey: key)
    }
    return created.id
  }

  /// Stops keeping the Audiobookshelf copy up to date (the playlist itself stays on the server).
  public func forgetServerCopy(_ id: UUID) {
    guard let key = savedKey(id) else { return }
    Audiobookshelf.shared.authentication.server?.storage.removeObject(forKey: key)
  }

  public enum SaveError: LocalizedError {
    case empty

    public var errorDescription: String? {
      String(localized: "No books match yet, and Audiobookshelf can't save an empty playlist.")
    }
  }

  /// Brings the saved Audiobookshelf copies in this library up to date, at most once an hour.
  public func syncSaved(force: Bool = false) async {
    guard let library = Audiobookshelf.shared.libraries.current?.id else { return }
    if !force, let lastSync, lastSync.library == library, Date().timeIntervalSince(lastSync.at) < 3600 { return }
    lastSync = (library, Date())
    for playlist in all where savedPlaylistID(playlist.id) != nil {
      guard let books = try? await books(for: playlist),
        Audiobookshelf.shared.libraries.current?.id == library
      else { continue }
      _ = try? await saveToServer(playlist, books: books)
    }
  }
}

/// Your listening progress, straight from the server.
public enum MyProgress {
  nonisolated private struct Me: Decodable, Sendable {
    let mediaProgress: [User.MediaProgress]
  }

  /// Progress on every book (`GET /api/me`); podcast episodes left out. From the server rather
  /// than the local store, which may not have synced yet.
  public static func books() async throws -> [User.MediaProgress] {
    let me: Me = try await Audiobookshelf.shared.send("/api/me")
    return me.mediaProgress.filter { $0.episodeId == nil }
  }
}
