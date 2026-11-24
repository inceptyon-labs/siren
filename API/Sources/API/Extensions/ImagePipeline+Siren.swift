import Foundation
import Nuke

extension ImagePipeline {
  // SIREN: Siren identifiers
  nonisolated private static let dataCache = try? DataCache(name: "com.inceptyon.siren.images")

  nonisolated static func siren(customHeaders: [String: String]?) -> ImagePipeline {
    ImagePipeline {
      let configuration = DataLoader.defaultConfiguration
      configuration.urlCache = nil
      configuration.httpAdditionalHeaders = customHeaders
      $0.dataLoader = DataLoader(configuration: configuration)

      $0.dataCache = dataCache
    }
  }
}
