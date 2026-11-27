import Foundation
import Nuke

extension ImagePipeline {
  // SIREN: Siren identifiers
  nonisolated private static let dataCache = try? DataCache(name: "com.inceptyon.siren.images")

  // SIREN: custom headers go only to the server's own hosts (covers also come from Audible's CDN
  // and request servers, which must not see them)
  nonisolated static func siren(customHeaders: [String: String]?, hosts: Set<String>) -> ImagePipeline {
    ImagePipeline {
      let configuration = DataLoader.defaultConfiguration
      configuration.urlCache = nil
      $0.dataLoader = ServerScopedDataLoader(
        loader: DataLoader(configuration: configuration),
        headers: customHeaders ?? [:],
        hosts: hosts
      )

      $0.dataCache = dataCache
    }
  }

  @MainActor static func siren(for server: Server?) -> ImagePipeline {
    .siren(customHeaders: server?.customHeaders, hosts: ServerScopedDataLoader.hosts(of: server))
  }
}

/// Loads image data, adding the server's custom headers only when the image is on one of the
/// server's hosts.
public struct ServerScopedDataLoader: DataLoading {
  private let loader: DataLoader
  private let headers: [String: String]
  private let hosts: Set<String>

  public init(loader: DataLoader, headers: [String: String], hosts: Set<String>) {
    self.loader = loader
    self.headers = headers
    self.hosts = Set(hosts.map { $0.lowercased() })
  }

  /// The primary and alternative hosts of a server.
  @MainActor public static func hosts(of server: Server?) -> Set<String> {
    hosts(of: [server?.baseURL, server?.alternativeURL])
  }

  public static func hosts(of urls: [URL?]) -> Set<String> {
    Set(urls.compactMap { $0?.host()?.lowercased() })
  }

  public func loadData(
    with request: URLRequest,
    didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
    completion: @escaping @Sendable (Error?) -> Void
  ) -> any Cancellable {
    var request = request
    if let host = request.url?.host()?.lowercased(), hosts.contains(host) {
      for (key, value) in headers where request.value(forHTTPHeaderField: key) == nil {
        request.setValue(value, forHTTPHeaderField: key)
      }
    }
    return loader.loadData(with: request, didReceiveData: didReceiveData, completion: completion)
  }
}
