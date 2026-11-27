import API
import Combine
import Foundation
import SwiftUI

class DeepLinkManager: ObservableObject {
  static let shared = DeepLinkManager()

  @Published var pendingExportConnection: ExportConnection?
  /// A link that signs in by itself, waiting for the person to say yes.
  @Published var pendingSignIn: ExportConnection?  // SIREN: confirm before a link signs in
  @Published private(set) var isImportingConnection = false

  private init() {}

  func handleDeepLink(_ url: URL) {
    guard
      url.scheme == "siren",  // SIREN: Siren identifiers
      let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
    else { return }

    switch components.host {
    case "play":
      handlePlayDeepLink(components)
    case "open":
      handleOpenDeepLink(components)
    case "connection":
      handleConnectionDeepLink(url)
    default:
      break
    }
  }

  private func handlePlayDeepLink(_ components: URLComponents) {
    let bookID = String(components.path.dropFirst())
    guard bookID.isSafePathComponent else { return }  // SIREN: an id, not a path (`../`)
    let playerManager = PlayerManager.shared

    Task {
      await playerManager.play(bookID)
    }
  }

  private func handleOpenDeepLink(_ components: URLComponents) {
    let bookID = String(components.path.dropFirst())
    guard bookID.isSafePathComponent else { return }  // SIREN: an id, not a path (`../`)
    let playerManager = PlayerManager.shared

    Task {
      await playerManager.open(bookID)
    }
  }

  private func handleConnectionDeepLink(_ url: URL) {
    guard let exportConnection = Self.decodeConnectionDeepLink(url) else {
      Toast(error: "Invalid connection link").show()
      return
    }

    // SIREN: a kids profile can't add sign-ins, and a link that carries one waits for a yes
    if SirenProfiles.shared.isKidsActive {
      Toast(error: "Leave the kids profile to add a sign-in").show()
      return
    }
    if exportConnection.token != nil {
      pendingSignIn = exportConnection
      return
    }

    importConnection(exportConnection)
  }

  /// The person said yes to a link that signs in.
  func confirmSignIn() {
    guard let exportConnection = pendingSignIn else { return }
    pendingSignIn = nil
    importConnection(exportConnection)
  }

  private func importConnection(_ exportConnection: ExportConnection) {
    Toast(message: "Testing shared connection...").show()
    isImportingConnection = true
    Task {
      await validateAndImportConnection(exportConnection)
      isImportingConnection = false
    }
  }

  private func validateAndImportConnection(_ exportConnection: ExportConnection) async {
    // SIREN: a link without a sign-in only fills in the server; the person adds any headers it
    // needs and signs in there
    guard exportConnection.token != nil else {
      pendingExportConnection = exportConnection
      return
    }

    do {
      _ = try await Audiobookshelf.shared.networkDiscovery.fetchServerStatus(
        serverURL: exportConnection.url,
        headers: exportConnection.headers
      )
    } catch {
      Toast(error: "Could not reach server with the shared URL and headers").show()
      return
    }

    guard let token = exportConnection.token else {
      pendingExportConnection = exportConnection
      return
    }

    do {
      let connectionID = try await Audiobookshelf.shared.authentication.loginWithJWT(
        serverURL: exportConnection.url,
        token: token,
        customHeaders: exportConnection.headers,
        alias: exportConnection.alias
      )
      try? await Audiobookshelf.shared.switchToServer(connectionID)
      Toast(success: "Connection imported successfully").show()
    } catch {
      Toast(error: "Server reachable, but Audiobookshelf credentials failed").show()
      pendingExportConnection = exportConnection
    }
  }

  static func createConnectionDeepLink(from connection: Connection, includeToken: Bool = false) -> URL? {
    let encoder = JSONEncoder()
    guard
      let connection = ExportConnection(connection, includeToken: includeToken),
      let data = try? encoder.encode(connection),
      let base64 = data.base64EncodedString()
        .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    else {
      return nil
    }

    return URL(string: "siren://connection/\(base64)")  // SIREN: Siren identifiers
  }

  static func decodeConnectionDeepLink(_ url: URL) -> ExportConnection? {
    guard url.scheme == "siren",  // SIREN: Siren identifiers
      let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
      components.host == "connection",
      let data = Data(base64Encoded: String(components.path.dropFirst()))
    else {
      return nil
    }

    return try? JSONDecoder().decode(ExportConnection.self, from: data)
  }
}

extension DeepLinkManager {
  public struct ExportConnection: Codable, Sendable, Equatable, Identifiable {
    public let url: URL
    public let token: String?
    public let headers: [String: String]
    public let alias: String?

    public var id: URL { url }

    init?(_ connection: Connection, includeToken: Bool = false) {
      url = connection.serverURL
      // SIREN: custom headers are often proxy secrets, so they travel only with the credentials
      headers = includeToken ? connection.customHeaders : [:]
      alias = connection.alias

      if includeToken {
        switch connection.token {
        case .bearer(_, let refreshToken, _, _):
          token = refreshToken
        case .apiKey(let key):
          token = key
        case .legacy:
          return nil
        }
      } else {
        token = nil
      }
    }
  }
}

struct DeepLinkHandlerModifier: ViewModifier {
  @ObservedObject private var deepLinkManager = DeepLinkManager.shared

  func body(content: Content) -> some View {
    content
      .onOpenURL { url in
        DeepLinkManager.shared.handleDeepLink(url)
      }
      .sheet(item: $deepLinkManager.pendingExportConnection) { exportConnection in
        ServerListPage(model: ServerListModel(pendingExportConnection: exportConnection))
      }
      // SIREN: confirm before a link signs in
      .alert(
        "Sign In from This Link?",
        isPresented: Binding(
          get: { deepLinkManager.pendingSignIn != nil },
          set: { if !$0 { deepLinkManager.pendingSignIn = nil } }
        ),
        presenting: deepLinkManager.pendingSignIn
      ) { _ in
        Button("Sign In") { deepLinkManager.confirmSignIn() }
        Button("Cancel", role: .cancel) { deepLinkManager.pendingSignIn = nil }
      } message: { connection in
        Text(
          "This link signs Siren in to \(connection.url.host() ?? connection.url.absoluteString) and switches to that sign-in. Only continue if you know who sent it."
        )
      }
  }
}

extension View {
  func handleDeepLinks() -> some View {
    modifier(DeepLinkHandlerModifier())
  }
}
