import Foundation

// SIREN: lets SirenKit call Audiobookshelf endpoints that upstream has no service for. Requests
// go through the signed-in server's NetworkService, so they get its custom headers, token
// refresh and alternative URL.
extension Audiobookshelf {
  public enum RequestMethod: Sendable {
    case get, post, patch, delete

    var http: HTTPMethod {
      switch self {
      case .get: .get
      case .post: .post
      case .patch: .patch
      case .delete: .delete
      }
    }
  }

  nonisolated public func send<Response: Decodable & Sendable>(
    _ path: String,
    method: RequestMethod = .get,
    body: (any Encodable & Sendable)? = nil,
    query: [String: String]? = nil
  ) async throws -> Response {
    guard let networkService else {
      throw AudiobookshelfError.networkError("Network service not configured. Please login first.")
    }
    let request = NetworkRequest<Response>(path: path, method: method.http, body: body, query: query)
    return try await networkService.send(request).value
  }

  /// For endpoints whose response Siren doesn't read.
  nonisolated public func send(
    _ path: String,
    method: RequestMethod,
    body: (any Encodable & Sendable)? = nil
  ) async throws {
    let _: Data = try await send(path, method: method, body: body)
  }
}
