import Foundation

/// Audible's catalog API, which needs no sign-in. It's undocumented, so it could change or be
/// blocked; callers treat a failure as "nothing to show". Every request goes through here, so
/// they stay at least 300 ms apart.
@MainActor
enum AudibleCatalog {
  private static var nextRequest = ContinuousClock.now
  private static let spacing = Duration.milliseconds(300)

  /// `GET /1.0/<path>` on the device region's Audible store, once it's this request's turn.
  static func get(_ path: String, query: [URLQueryItem]) async throws -> Data {
    // Reserve the next slot before waiting, so requests started together still go 300 ms apart.
    let slot = max(ContinuousClock.now, nextRequest)
    nextRequest = slot + spacing
    try await Task.sleep(until: slot)
    return try await fetch(path, query: query)
  }

  nonisolated private static func fetch(_ path: String, query: [URLQueryItem]) async throws -> Data {
    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.path = "/1.0/\(path)"
    components.queryItems = query
    guard let url = components.url else { throw URLError(.badURL) }
    let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    return data
  }

  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }

  /// The Audible store for the device's region. Each store has its own ratings and catalog.
  nonisolated private static var host: String {
    switch Locale.current.region?.identifier {
    case "GB", "IE": "api.audible.co.uk"
    case "DE", "AT", "CH": "api.audible.de"
    case "FR", "BE": "api.audible.fr"
    case "CA": "api.audible.ca"
    case "AU", "NZ": "api.audible.com.au"
    case "IN": "api.audible.in"
    case "IT": "api.audible.it"
    case "ES": "api.audible.es"
    case "JP": "api.audible.co.jp"
    case "BR": "api.audible.com.br"
    default: "api.audible.com"
    }
  }

  // MARK: Response parts

  struct RawRatings: Decodable {
    let overallDistribution: Distribution?
    let storyDistribution: Distribution?
    let performanceDistribution: Distribution?

    struct Distribution: Decodable {
      let averageRating: Double?
      let numRatings: Int?

      /// The average, when anyone has rated it.
      var average: Double? {
        guard let averageRating, (numRatings ?? 0) > 0 else { return nil }
        return averageRating
      }
    }

    var rating: AudibleRatings.Rating? {
      guard let overall = overallDistribution, let average = overall.average else { return nil }
      return AudibleRatings.Rating(
        average: average,
        count: overall.numRatings ?? 0,
        story: storyDistribution?.average,
        performance: performanceDistribution?.average
      )
    }
  }
}
