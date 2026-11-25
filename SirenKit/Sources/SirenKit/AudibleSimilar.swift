import Foundation

/// A book in Audible's catalog.
public struct AudibleProduct: Codable, Sendable, Hashable, Identifiable {
  public let asin: String
  public let title: String
  public let authors: [String]
  public let narrators: [String]
  public let coverURL: URL?
  public let rating: AudibleRatings.Rating?
  /// `yyyy-MM-dd`.
  public let releaseDate: String?

  public var id: String { asin }
  public var author: String { authors.joined(separator: ", ") }
  public var narrator: String { narrators.joined(separator: ", ") }
}

/// Books Audible lists as similar to a book ("listeners also enjoyed"), by ASIN. Cached on the
/// device for 14 days.
@MainActor
public final class AudibleSimilar {
  public static let shared = AudibleSimilar()

  private struct Entry: Codable {
    let products: [AudibleProduct]
    let fetched: Date
  }

  private static let maxAge: TimeInterval = 14 * 24 * 3600
  private var entries: [String: Entry] = [:]
  private var pendingSave: Task<Void, Never>?
  private let cacheFile = URL.cachesDirectory.appending(path: "audible-similar.json")

  private init() {
    guard let data = try? Data(contentsOf: cacheFile),
      let saved = try? JSONDecoder().decode([String: Entry].self, from: data)
    else { return }
    let now = Date()
    entries = saved.filter { now.timeIntervalSince($0.value.fetched) < Self.maxAge }
  }

  /// Up to 20 books like this one, best match first; nil when Audible couldn't be reached.
  public func products(like asin: String) async -> [AudibleProduct]? {
    if let entry = entries[asin], Date().timeIntervalSince(entry.fetched) < Self.maxAge {
      return entry.products
    }
    guard
      let data = try? await AudibleCatalog.get(
        "catalog/products/\(asin)/sims",
        query: [
          URLQueryItem(name: "num_results", value: "20"),
          URLQueryItem(name: "response_groups", value: "product_desc,contributors,media,rating,product_attrs"),
        ]
      ),
      let response = try? AudibleCatalog.decoder().decode(Response.self, from: data)
    else { return nil }
    let products = response.similarProducts.compactMap(\.product)
    entries[asin] = Entry(products: products, fetched: Date())
    scheduleSave()
    return products
  }

  private struct Response: Decodable {
    let similarProducts: [Raw]
  }

  private struct Raw: Decodable {
    struct Person: Decodable { let name: String }

    let asin: String
    let title: String?
    let authors: [Person]?
    let narrators: [Person]?
    let productImages: [String: String]?
    let rating: AudibleCatalog.RawRatings?
    let releaseDate: String?

    var product: AudibleProduct? {
      guard let title else { return nil }
      return AudibleProduct(
        asin: asin,
        title: title,
        // Translators and the like come as "Name — Translator".
        authors: authors?.map(\.name).filter { !$0.contains("—") } ?? [],
        narrators: narrators?.map(\.name) ?? [],
        coverURL: productImages?["500"].flatMap(URL.init(string:)),
        rating: rating?.rating,
        releaseDate: releaseDate
      )
    }
  }

  private func scheduleSave() {
    pendingSave?.cancel()
    pendingSave = Task {
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled, let data = try? JSONEncoder().encode(entries) else { return }
      let file = cacheFile
      Task.detached(priority: .utility) { try? data.write(to: file, options: .atomic) }
    }
  }
}
