import API
import Nuke
import SwiftUI
import WatchKit

@main
struct SirenWatch: App {
  @WKApplicationDelegateAdaptor private var appDelegate: AppDelegate

  init() {
    let server = Audiobookshelf.shared.authentication.server
    ImagePipeline.shared = .watch(customHeaders: server?.customHeaders, hosts: ServerScopedDataLoader.hosts(of: server))
    _ = WatchConnectivityManager.shared
    DownloadManager.shared.start()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

extension ImagePipeline {
  // SIREN: Siren identifiers
  nonisolated private static let dataCache = try? DataCache(name: "com.inceptyon.siren.watch.images")

  // SIREN: custom headers go only to the server's own hosts
  nonisolated static func watch(customHeaders: [String: String]?, hosts: Set<String> = []) -> ImagePipeline {
    ImagePipeline {
      let config = URLSessionConfiguration.default
      config.timeoutIntervalForResource = 300
      config.timeoutIntervalForRequest = 60
      config.allowsCellularAccess = true
      config.waitsForConnectivity = true
      config.allowsExpensiveNetworkAccess = true
      config.allowsConstrainedNetworkAccess = true
      config.urlCache = nil

      $0.dataLoader = ServerScopedDataLoader(
        loader: DataLoader(configuration: config),
        headers: customHeaders ?? [:],
        hosts: hosts
      )
      $0.dataCache = dataCache
    }
  }
}

final class AppDelegate: NSObject, WKApplicationDelegate {
  func applicationDidBecomeActive() {
    DownloadManager.shared.applicationDidBecomeActive()
  }

  func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
    for task in backgroundTasks {
      switch task {
      case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
        DownloadManager.shared.reconnectBackgroundSession(
          withIdentifier: urlSessionTask.sessionIdentifier
        ) {
          urlSessionTask.setTaskCompletedWithSnapshot(false)
        }

      case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
        WatchConnectivityManager.shared.handleBackgroundTask(connectivityTask)

      default:
        task.setTaskCompletedWithSnapshot(false)
      }
    }
  }
}
