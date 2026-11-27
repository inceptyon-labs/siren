import Foundation

actor CredentialsActor {
  private var refreshTask: Task<Credentials, Error>?
  private weak var server: Server?

  private var consecutiveFailures: Int = 0
  private var nextRetryAt: Date?

  init(server: Server) {
    self.server = server
  }

  var freshCredentials: Credentials {
    get async throws {
      guard let server else {
        throw Audiobookshelf.AudiobookshelfError.networkError("No server")
      }

      let currentToken = await server.token

      if let refreshTask {
        return try await refreshTask.value
      }

      guard case .bearer(_, let refreshToken, let expiresAt, _) = currentToken else {
        return currentToken
      }

      let currentTime = Date().timeIntervalSince1970
      let bufferTime: TimeInterval = 60

      if currentTime < (expiresAt - bufferTime) {
        return currentToken
      }

      if refreshToken.isEmpty {
        throw Audiobookshelf.AudiobookshelfError.networkError(
          "Refresh token is no longer valid, re-authentication required"
        )
      }

      if let nextRetryAt, Date() < nextRetryAt {
        throw Audiobookshelf.AudiobookshelfError.networkError(
          "Token refresh temporarily unavailable, retrying later"
        )
      }

      let task = Task<Credentials, Error> { [server] in
        do {
          return try await Audiobookshelf.shared.authentication.refreshToken(for: server)
        } catch {
          if let fallback = await self.handleError(error) {
            return fallback
          }
          throw error
        }
      }

      refreshTask = task
      defer { refreshTask = nil }

      let credentials = try await task.value
      consecutiveFailures = 0
      nextRetryAt = nil
      return credentials
    }
  }

  private func handleError(_ error: Error) async -> Credentials? {
    if case NetworkError.httpError(let statusCode, _) = error,
      statusCode == 401 || statusCode == 403
    {
      consecutiveFailures += 1
      nextRetryAt = Date().addingTimeInterval(min(15 * 60, 60 * pow(2.0, Double(consecutiveFailures - 1))))
      return await MainActor.run { [weak server] () -> Credentials? in
        guard let server else { return nil }
        if case .bearer(_, _, _, .some(let legacyToken)) = server.token, !legacyToken.isEmpty {
          let fallback = Credentials.legacy(token: legacyToken)
          Audiobookshelf.shared.authentication.updateToken(server.id, token: fallback)
          return fallback
        }
        // SIREN: keep the refresh token. A 401 or 403 can come from a proxy in front of the
        // server (an expired access policy), and wiping the sign-in then can't be undone. The
        // server shows as signed out, and refresh is tried again after the backoff set above.
        server.status = .authenticationError
        return nil
      }
    }

    consecutiveFailures += 1
    let delay = min(60, pow(2.0, Double(consecutiveFailures)))
    nextRetryAt = Date().addingTimeInterval(delay)
    return nil
  }
}
