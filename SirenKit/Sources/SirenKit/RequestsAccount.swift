import Foundation
import Security

/// Each profile's ReadMeABook address and API token. The token is a credential, so it lives in
/// the Keychain (this device only); the address lives in UserDefaults. Keyed by the
/// Audiobookshelf connection, so every person on a shared phone has their own.
public struct RequestsAccount: Sendable, Equatable {
  public let url: URL
  public let token: String

  public init(url: URL, token: String) {
    self.url = url
    self.token = token
  }

  private static let service = "com.inceptyon.siren.readmeabook"

  private static func urlKey(_ profileID: String) -> String { "siren.requests.url.\(profileID)" }

  public static func load(profileID: String) -> RequestsAccount? {
    guard let address = UserDefaults.standard.string(forKey: urlKey(profileID)),
      let url = URL(string: address),
      let token = readToken(profileID)
    else { return nil }
    return RequestsAccount(url: url, token: token)
  }

  public func save(profileID: String) throws {
    UserDefaults.standard.set(url.absoluteString, forKey: Self.urlKey(profileID))
    try Self.writeToken(token, profileID: profileID)
  }

  public static func remove(profileID: String) {
    UserDefaults.standard.removeObject(forKey: urlKey(profileID))
    SecItemDelete(query(profileID) as CFDictionary)
  }

  private static func query(_ profileID: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: profileID,
    ]
  }

  private static func readToken(_ profileID: String) -> String? {
    var request = query(profileID)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func writeToken(_ token: String, profileID: String) throws {
    SecItemDelete(query(profileID) as CFDictionary)
    var item = query(profileID)
    item[kSecValueData as String] = Data(token.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
  }
}
