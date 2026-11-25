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

/// Audible's product lookups.
@MainActor
enum AudibleProducts {
  /// The response groups that fill in an `AudibleProduct`.
  static let responseGroups = "product_desc,contributors,media,rating,product_attrs"

  /// Up to 50 books by ASIN; nil when Audible couldn't be reached.
  static func lookup(_ asins: [String]) async -> [AudibleProduct]? {
    struct Response: Decodable {
      let products: [Raw]
    }
    guard
      let data = try? await AudibleCatalog.get(
        "catalog/products",
        query: [
          URLQueryItem(name: "asins", value: asins.joined(separator: ",")),
          URLQueryItem(name: "response_groups", value: responseGroups),
        ]
      ),
      let response = try? AudibleCatalog.decoder().decode(Response.self, from: data)
    else { return nil }
    return response.products.compactMap(\.product)
  }

  /// A product as Audible sends it.
  struct Raw: Decodable {
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
}
