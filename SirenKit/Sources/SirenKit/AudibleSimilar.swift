import Foundation

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
          URLQueryItem(name: "response_groups", value: AudibleProducts.responseGroups),
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
    let similarProducts: [AudibleProducts.Raw]
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
