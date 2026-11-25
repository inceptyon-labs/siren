import Foundation

/// A client for ReadMeABook, which finds and downloads requested audiobooks into the
/// Audiobookshelf library. It signs in with a person's own API token (`rmab_...`, made under
/// Profile › API Tokens in ReadMeABook). Tokens reach only search, the token owner's requests
/// and `auth/me`; approving requests needs an admin session in ReadMeABook's web app.
public struct ReadMeABook: Sendable {
  public let account: RequestsAccount

  public init(account: RequestsAccount) {
    self.account = account
  }

  /// The ReadMeABook address on the same host as the Audiobookshelf server: its default port.
  public static func suggestedURL(near server: URL) -> URL? {
    guard var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return nil }
    components.port = 3030
    components.path = ""
    components.query = nil
    return components.url
  }

  /// Where people make their token.
  public var tokenPage: URL { account.url.appending(path: "profile") }

  // MARK: Models

  public struct User: Decodable, Sendable {
    public let username: String?
    public let role: String

    public var isAdmin: Bool { role == "admin" }
  }

  public struct SearchResult: Decodable, Sendable, Identifiable, Hashable {
    public let asin: String
    public let title: String
    public let author: String
    public let narrator: String?
    public let coverArtUrl: String?
    public let durationMinutes: Double?
    public let releaseDate: String?
    public let rating: Double?
    public let series: String?
    public let seriesPart: String?
    public let isAvailable: Bool
    public let isRequested: Bool
    public let requestStatus: String?

    public var id: String { asin }
    public var coverURL: URL? { coverArtUrl.flatMap(URL.init(string:)) }
  }

  public struct SearchPage: Decodable, Sendable {
    public let results: [SearchResult]
    public let page: Int
    public let hasMore: Bool
  }

  public struct Request: Decodable, Sendable, Identifiable {
    public let id: String
    public let status: Status
    /// 0...100 while downloading.
    public let progress: Int
    public let releaseDate: String?
    public let createdAt: String?
    /// When the status last changed.
    public let updatedAt: String?
    public let audiobook: Audiobook

    public struct Audiobook: Decodable, Sendable {
      public let audibleAsin: String?
      public let title: String
      public let author: String
      public let coverArtUrl: String?

      public var coverURL: URL? { coverArtUrl.flatMap(URL.init(string:)) }
    }
  }

  /// ReadMeABook's request states, grouped the way a listener sees them.
  public enum Status: Decodable, Sendable, Equatable {
    case waitingForApproval
    case searching
    case downloading
    case adding
    case awaitingRelease
    case available
    case failed
    case declined
    case cancelled
    case other(String)

    public init(from decoder: Decoder) throws {
      let raw = try decoder.singleValueContainer().decode(String.self)
      self = Status(raw)
    }

    public init(_ raw: String) {
      switch raw {
      case "awaiting_approval": self = .waitingForApproval
      case "pending", "searching", "awaiting_search": self = .searching
      case "downloading": self = .downloading
      case "processing", "downloaded", "awaiting_import": self = .adding
      case "awaiting_release": self = .awaitingRelease
      case "available", "completed": self = .available
      case "failed", "warn": self = .failed
      case "denied": self = .declined
      case "cancelled": self = .cancelled
      default: self = .other(raw)
      }
    }

    /// Still on its way: worth showing on Home and polling.
    public var isActive: Bool {
      switch self {
      case .waitingForApproval, .searching, .downloading, .adding, .awaitingRelease: true
      default: false
      }
    }

    /// Statuses ReadMeABook accepts a new request for the same book after.
    public var canRequestAgain: Bool { self == .failed || self == .cancelled }

    /// Statuses ReadMeABook lets the requester cancel.
    public var canCancel: Bool {
      switch self {
      case .waitingForApproval, .searching, .downloading, .awaitingRelease: true
      default: false
      }
    }
  }

  public struct Failure: LocalizedError, Sendable {
    public let status: Int
    public let code: String?
    public let message: String?

    public var errorDescription: String? {
      if let message, !message.isEmpty { return message }
      switch status {
      case 401: return String(localized: "ReadMeABook didn't accept the token.")
      case 403: return String(localized: "This token isn't allowed to do that.")
      default: return String(localized: "ReadMeABook returned an error (\(status)).")
      }
    }
  }

  // MARK: Calls

  /// The token's owner (`GET /api/auth/me`). Also checks the address and token.
  public func me() async throws -> User {
    struct Response: Decodable { let user: User }
    let response: Response = try await send("api/auth/me")
    return response.user
  }

  /// The Audible catalog, 50 a page, flagged with what's in the library or requested
  /// (`GET /api/audiobooks/search`). A page can be empty while `hasMore` is true.
  public func search(_ query: String, page: Int = 1) async throws -> SearchPage {
    try await send(
      "api/audiobooks/search",
      query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "page", value: String(page))]
    )
  }

  /// Asks ReadMeABook to find the book (`POST /api/requests`). Throws a 409 `Failure` when it's
  /// already in the library, already requested or ignored.
  public func request(_ book: SearchResult) async throws {
    try await request(
      asin: book.asin,
      title: book.title,
      author: book.author,
      narrator: book.narrator,
      coverArtUrl: book.coverArtUrl
    )
  }

  /// `POST /api/requests` for a book known only by its Audible details.
  public func request(
    asin: String,
    title: String,
    author: String,
    narrator: String?,
    coverArtUrl: String?
  ) async throws {
    struct Body: Encodable {
      struct Book: Encodable {
        let asin: String
        let title: String
        let author: String
        let narrator: String?
        let coverArtUrl: String?
      }
      let audiobook: Book
    }
    let body = Body(
      audiobook: .init(asin: asin, title: title, author: author, narrator: narrator, coverArtUrl: coverArtUrl)
    )
    let _: Ignored = try await send("api/requests", method: "POST", body: body)
  }

  /// What Home shows: everything still on its way, then the few most recently ready. Fetched by
  /// status group, so a long history can't push an old outstanding request off the first page.
  public func myRequests() async throws -> [Request] {
    async let active = myRequests(status: "active", limit: 100)
    async let waiting = myRequests(status: "waiting", limit: 100)
    // The server orders by request date, so take enough history to find recent arrivals.
    async let ready = myRequests(status: "completed", limit: 50)
    async let failed = myRequests(status: "failed", limit: 10)
    async let warned = myRequests(status: "warn", limit: 10)
    async let declined = myRequests(status: "cancelled", limit: 10)
    let all = try await active + waiting + ready + failed + warned + declined.filter { $0.status == .declined }
    return all.sorted { ($0.updatedAt ?? $0.createdAt ?? "") > ($1.updatedAt ?? $1.createdAt ?? "") }
  }

  /// Your requests in one status group, newest first (`GET /api/requests?myOnly=true&status=`).
  public func myRequests(status: String, limit: Int) async throws -> [Request] {
    struct Response: Decodable { let requests: [Request] }
    let response: Response = try await send(
      "api/requests",
      query: [
        URLQueryItem(name: "myOnly", value: "true"),
        URLQueryItem(name: "type", value: "audiobook"),
        URLQueryItem(name: "status", value: status),
        URLQueryItem(name: "take", value: String(limit)),
      ]
    )
    return response.requests
  }

  /// `POST /api/requests/:id/cancel`.
  public func cancel(_ request: Request) async throws {
    let _: Ignored = try await send("api/requests/\(request.id)/cancel", method: "POST")
  }

  // MARK: Transport

  private struct Ignored: Decodable {}

  private struct ErrorBody: Decodable {
    let error: String?
    let message: String?
  }

  private func send<Response: Decodable>(
    _ path: String,
    method: String = "GET",
    query: [URLQueryItem] = [],
    body: (any Encodable)? = nil
  ) async throws -> Response {
    var url = account.url.appending(path: path)
    if !query.isEmpty { url.append(queryItems: query) }
    var request = URLRequest(url: url, timeoutInterval: 30)
    request.httpMethod = method
    request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.httpBody = try JSONEncoder().encode(body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      let error = try? JSONDecoder().decode(ErrorBody.self, from: data)
      throw Failure(status: status, code: error?.error, message: error?.message)
    }
    return try JSONDecoder().decode(Response.self, from: data)
  }
}
