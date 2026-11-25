import API
import Foundation

/// Audiobookshelf user and API key administration, for a server admin setting up a household.
/// Every call here needs an admin or root account.
@MainActor
public enum HouseholdAdmin {
  public struct Member: Decodable, Identifiable, Sendable, Hashable {
    public let id: String
    public let username: String
    public let type: UserType
    public let isActive: Bool
    let permissions: Access?
    let librariesAccessible: [String]?
    let itemTagsSelected: [String]?

    struct Access: Decodable, Sendable, Hashable {
      let accessAllLibraries: Bool?
      let accessAllTags: Bool?
      let accessExplicitContent: Bool?
      let selectedTagsNotAccessible: Bool?
    }

    public var isAdmin: Bool { type == .root || type == .admin }

    /// Whether they can see a book, by Audiobookshelf's rule: its library, explicit content, then
    /// tags (a kids profile sees only books tagged "kids").
    public func canSee(_ book: HouseholdSend.Book) -> Bool {
      if permissions?.accessAllLibraries != true, !(librariesAccessible ?? []).contains(book.libraryID) {
        return false
      }
      if book.isExplicit, permissions?.accessExplicitContent != true { return false }
      guard permissions?.accessAllTags == false else { return true }
      let selected = itemTagsSelected ?? []
      if permissions?.selectedTagsNotAccessible == true {
        return book.tags.allSatisfy { !selected.contains($0) }
      }
      return selected.contains { book.tags.contains($0) }
    }
  }

  /// Where a member is with one book.
  public struct Progress: Decodable, Sendable {
    public let libraryItemId: String?
    public let progress: Double
    public let isFinished: Bool
  }

  /// Everyone on the server (`GET /api/users`).
  public static func members() async throws -> [Member] {
    struct Response: Decodable { let users: [Member] }
    let response: Response = try await Audiobookshelf.shared.send("/api/users")
    return response.users.sorted { $0.username.localizedStandardCompare($1.username) == .orderedAscending }
  }

  /// Creates an active listener account (`POST /api/users`). Audiobookshelf requires a password,
  /// so this sets a random one that nobody sees: the member signs in with an invite instead, and
  /// an admin can set a real password later in Audiobookshelf.
  public static func addMember(username: String) async throws -> Member {
    struct Body: Encodable {
      let username: String
      let password: String
      let type = "user"
      let isActive = true
    }
    struct Response: Decodable { let user: Member }
    let body = Body(username: username, password: randomPassword())
    let response: Response = try await Audiobookshelf.shared.send("/api/users", method: .post, body: body)
    return response.user
  }

  /// A new API key that signs in as `member` and never expires (`POST /api/api-keys`). The key is
  /// only returned once; revoke it by deleting it under Settings › API Keys in Audiobookshelf.
  public static func makeKey(for member: Member, name: String) async throws -> String {
    struct Body: Encodable {
      let name: String
      let userId: String
      let isActive = true
    }
    struct Response: Decodable {
      struct Key: Decodable { let apiKey: String }
      let apiKey: Key
    }
    let response: Response = try await Audiobookshelf.shared.send(
      "/api/api-keys",
      method: .post,
      body: Body(name: name, userId: member.id)
    )
    return response.apiKey.apiKey
  }

  /// A member's listening progress on every book they've started (`GET /api/users/:id`).
  public static func progress(of member: Member) async throws -> [Progress] {
    struct Response: Decodable { let mediaProgress: [Progress] }
    let response: Response = try await Audiobookshelf.shared.send("/api/users/\(member.id)")
    return response.mediaProgress
  }

  private static func randomPassword() -> String {
    var bytes = [UInt8](repeating: 0, count: 24)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes).base64EncodedString()
  }
}
