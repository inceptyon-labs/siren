import API
import Foundation

/// Sending a book to someone tags it `for:<username>`. Their Home lists the unfinished books
/// with that tag. Tags work across users and show in every Audiobookshelf client; playlists are
/// private to their owner and collections are visible to everyone. Tagging needs the `update`
/// permission.
@MainActor
public enum HouseholdSend {
  public static let tagPrefix = "for:"

  public static func tag(for username: String) -> String { tagPrefix + username }

  /// The usernames a book's tags say it was sent to.
  public static func recipients(in tags: [String]) -> [String] {
    tags.filter { $0.hasPrefix(tagPrefix) }.map { String($0.dropFirst(tagPrefix.count)) }
  }

  /// What decides who can see a book.
  public struct Book: Sendable {
    public let libraryID: String
    public let tags: [String]
    public let isExplicit: Bool
  }

  /// The book's library, tags and explicit flag (`GET /api/items/:id`).
  public static func book(itemID: String) async throws -> Book {
    struct Response: Decodable {
      struct Media: Decodable {
        struct Metadata: Decodable { let explicit: Bool? }
        let tags: [String]?
        let metadata: Metadata?
      }
      let libraryId: String
      let media: Media
    }
    let response: Response = try await Audiobookshelf.shared.send("/api/items/\(itemID)")
    return Book(
      libraryID: response.libraryId,
      tags: response.media.tags ?? [],
      isExplicit: response.media.metadata?.explicit ?? false
    )
  }

  /// Adds a `for:` tag per recipient, keeping the book's other tags
  /// (`PATCH /api/items/:id/media`).
  public static func send(itemID: String, to usernames: [String]) async throws {
    struct Body: Encodable { let tags: [String] }
    var tags = try await book(itemID: itemID).tags
    for username in usernames where !tags.contains(tag(for: username)) {
      tags.append(tag(for: username))
    }
    try await Audiobookshelf.shared.send("/api/items/\(itemID)/media", method: .patch, body: Body(tags: tags))
  }
}
