import CryptoKit
import Foundation

// SIREN: server ids and extensions go into file paths; keep them from reaching outside their folder
extension String {
  /// Whether this works as one file or folder name as it is: letters, digits, `-`, `_` and `.`,
  /// not starting with a dot. Audiobookshelf ids are UUIDs, which always qualify.
  public var isSafePathComponent: Bool {
    guard !isEmpty, count <= 128, !hasPrefix(".") else { return false }
    return unicodeScalars.allSatisfy { scalar in
      scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "-_.".unicodeScalars.contains(scalar))
    }
  }

  /// This string as one file or folder name. A safe one comes back unchanged; anything else (a
  /// slash, `..`, other characters) becomes a hash of itself, so it can't name a path elsewhere.
  public var safePathComponent: String {
    guard !isSafePathComponent else { return self }
    let digest = SHA256.hash(data: Data(utf8))
    return "h-" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
  }

  /// A file extension such as `.mp3`, with its dot, or nil when this isn't one.
  public var safeFileExtension: String? {
    let bare = hasPrefix(".") ? String(dropFirst()) : self
    guard (1...10).contains(bare.count),
      bare.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) })
    else { return nil }
    return "." + bare
  }
}
