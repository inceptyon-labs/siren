import Foundation

/// What the Top Shelf shows: the app writes it to the shared container after Home loads, and the
/// extension reads it. The extension has no sign-in of its own.
nonisolated struct TopShelfSnapshot: Codable, Sendable {
  struct Item: Codable, Sendable {
    let id: String
    let title: String
    let imageURL: URL?
    let progress: Double?
    let playURL: URL
  }

  let items: [Item]

  static var file: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.inceptyon.siren")?
      .appending(path: "Library/Caches/TopShelf.json")
  }

  static func load() -> TopShelfSnapshot? {
    guard let file, let data = try? Data(contentsOf: file) else { return nil }
    return try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
  }

  func save() {
    guard let file = Self.file, let data = try? JSONEncoder().encode(self) else { return }
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
  }
}
