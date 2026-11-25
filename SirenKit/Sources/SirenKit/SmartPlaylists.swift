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
  @ObservationIgnored private var isSyncing = false
  /// Playlists this version can't read (a rule from a newer version), kept as they are so a save
  /// here doesn't drop them from iCloud.
  @ObservationIgnored private var unreadable: [Any] = []

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
      let elements = try? JSONSerialization.jsonObject(with: data) as? [Any]
    else { return }
    var read: [SmartPlaylist] = []
    var kept: [Any] = []
    for element in elements {
      if let json = try? JSONSerialization.data(withJSONObject: element),
        let playlist = try? JSONDecoder().decode(SmartPlaylist.self, from: json)
      {
        read.append(playlist)
      } else {
        kept.append(element)
      }
    }
    all = read
    unreadable = kept
  }

  private func write() {
    guard let encoded = try? JSONEncoder().encode(all),
      let known = try? JSONSerialization.jsonObject(with: encoded) as? [Any],
      let data = try? JSONSerialization.data(withJSONObject: known + unreadable)
    else { return }
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

  /// Marks the Audiobookshelf playlist Siren keeps for one smart playlist, so another device finds
  /// it without taking over a playlist someone made by hand or another smart playlist's copy.
  private static func marker(_ id: UUID) -> String {
    "Smart playlist kept up to date by Siren. [\(id.uuidString)]"
  }

  /// Saves the playlist's current books to Audiobookshelf, creating the playlist there or updating
  /// it. Returns its ID.
  @discardableResult
  public func saveToServer(_ playlist: SmartPlaylist) async throws -> String {
    let existing = serverPlaylistID(for: playlist, in: try await Audiobookshelf.shared.playlists.fetch().results)
    return try await write(playlist, to: existing)
  }

  /// Puts the playlist's books in `existing`, or in a new playlist when nil.
  private func write(_ playlist: SmartPlaylist, to existing: String?) async throws -> String {
    let server = Audiobookshelf.shared.authentication.server?.id
    let library = Audiobookshelf.shared.libraries.current?.id
    func checkUnchanged() throws {
      guard Audiobookshelf.shared.authentication.server?.id == server,
        Audiobookshelf.shared.libraries.current?.id == library
      else { throw CancellationError() }
    }

    let ids = try await books(for: playlist).map(\.id)
    // Audiobookshelf won't keep an empty playlist; the last copy stays rather than being cleared.
    guard !ids.isEmpty else { throw SaveError.empty }
    try checkUnchanged()
    let saved: Playlist
    if let existing {
      saved = try await Audiobookshelf.shared.playlists.update(
        playlistID: existing,
        name: playlist.name,
        description: Self.marker(playlist.id),
        items: ids
      )
    } else {
      let created = try await Audiobookshelf.shared.playlists.create(name: playlist.name, items: ids)
      saved = try await Audiobookshelf.shared.playlists.update(
        playlistID: created.id,
        description: Self.marker(playlist.id)
      )
    }
    try checkUnchanged()
    if let key = savedKey(playlist.id) {
      Audiobookshelf.shared.authentication.server?.storage.set(saved.id, forKey: key)
    }
    return saved.id
  }

  /// The server playlist kept for this one: the one saved here if it's still there, else the one
  /// marked with its ID (saved from another device). Nil when there's none.
  private func serverPlaylistID(for playlist: SmartPlaylist, in all: [Playlist]) -> String? {
    if let saved = savedPlaylistID(playlist.id), all.contains(where: { $0.id == saved }) { return saved }
    return all.first { $0.description == Self.marker(playlist.id) }?.id
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

  /// Brings the Audiobookshelf copies in this library up to date, at most once an hour, including
  /// ones saved from another device. A run that fails somewhere is tried again next time rather
  /// than an hour later.
  public func syncSaved(force: Bool = false) async {
    guard !isSyncing, let library = Audiobookshelf.shared.libraries.current?.id else { return }
    if !force, let lastSync, lastSync.library == library, Date().timeIntervalSince(lastSync.at) < 3600 { return }
    isSyncing = true
    defer { isSyncing = false }
    guard let onServer = try? await Audiobookshelf.shared.playlists.fetch().results else { return }
    var failed = false
    for playlist in all {
      guard Audiobookshelf.shared.libraries.current?.id == library else { return }
      guard let existing = serverPlaylistID(for: playlist, in: onServer) else { continue }
      do {
        try await write(playlist, to: existing)
      } catch SaveError.empty {
        // Nothing matches right now; the server copy keeps its last books.
      } catch {
        failed = true
      }
    }
    if !failed { lastSync = (library, Date()) }
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
