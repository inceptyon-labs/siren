import API
import Foundation

/// Books you liked, kept in a playlist named "Liked" in the current library. Audiobookshelf has
/// no rating field, and playlists are private to their owner and sync through the server, so
/// every device and client sees the same likes. Recommendations use them as seeds.
@MainActor
public enum Likes {
  public static let playlistName = "Liked"

  /// Saves run one after another: each reads the playlist, then changes it, and two first likes
  /// at once would otherwise create two playlists.
  private static var lastSave: Task<Void, Error>?

  /// The "Liked" playlist, if you've liked anything in this library.
  public static func playlist() async throws -> Playlist? {
    // No paging: with a page parameter Audiobookshelf echoes `page` back as a string, which
    // upstream's Page decoder rejects. Without one it returns every playlist.
    try await Audiobookshelf.shared.playlists.fetch().results.first { $0.name == playlistName }
  }

  /// IDs of the books you liked in this library.
  public static func likedIDs() async throws -> Set<String> {
    Set(try await playlist()?.items.map(\.libraryItemID) ?? [])
  }

  /// Likes or unlikes a book, creating the playlist on the first like.
  public static func set(_ isLiked: Bool, itemID: String) async throws {
    let context = Context()
    let previous = lastSave
    let save = Task {
      _ = await previous?.result
      try await apply(isLiked, itemID: itemID, in: context)
    }
    lastSave = save
    try await save.value
  }

  /// The profile and library a save started in. Playlists go through the app's current sign-in,
  /// so a save is dropped if someone switched profiles or libraries before it ran.
  @MainActor private struct Context: Equatable {
    let serverID: String?
    let libraryID: String?

    init() {
      serverID = Audiobookshelf.shared.authentication.server?.id
      libraryID = Audiobookshelf.shared.libraries.current?.id
    }

    func check() throws {
      guard self == Context() else { throw CancellationError() }
    }
  }

  private static func apply(_ isLiked: Bool, itemID: String, in context: Context) async throws {
    try context.check()
    let liked = try await playlist()
    try context.check()
    switch (isLiked, liked) {
    case (true, nil):
      _ = try await Audiobookshelf.shared.playlists.create(name: playlistName, items: [itemID])
    case (true, let liked?):
      guard !liked.items.contains(where: { $0.libraryItemID == itemID }) else { return }
      _ = try await Audiobookshelf.shared.playlists.addItems(playlistID: liked.id, items: [itemID])
    case (false, let liked?):
      guard liked.items.contains(where: { $0.libraryItemID == itemID }) else { return }
      _ = try await Audiobookshelf.shared.playlists.removeItem(playlistID: liked.id, libraryItemID: itemID)
    case (false, nil):
      return
    }
  }
}
