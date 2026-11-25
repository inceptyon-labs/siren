import API
import Foundation

/// Audiobookshelf server administration for the household's admin: who's listening, the server's
/// users and what they can see, library scans and backups. Every call here needs an admin or root
/// account.
@MainActor
public enum ServerAdmin {
  // MARK: - Listening now

  /// A book or episode someone is playing. Apps open a session when playback starts and close it
  /// when it stops.
  public struct OpenSession: Decodable, Identifiable, Sendable {
    public let id: String
    public let displayTitle: String?
    public let displayAuthor: String?
    /// The book's length, in seconds.
    public let duration: Double?
    /// The listener's position, in seconds.
    public let currentTime: Double?
    public let user: Listener?
    public let deviceInfo: Device?
    let updatedAt: Double?

    public struct Listener: Decodable, Sendable {
      public let id: String
      public let username: String
    }

    public struct Device: Decodable, Sendable {
      let deviceName: String?
      let model: String?
      let clientName: String?
      let browserName: String?
      let osName: String?

      /// The device's name, its model, or the browser and system it's playing in.
      public var name: String? {
        if let deviceName, !deviceName.isEmpty { return deviceName }
        if let model, !model.isEmpty { return model }
        guard let browserName else { return clientName }
        return osName.map { "\(browserName) on \($0)" } ?? browserName
      }
    }

    /// When the player last reported its position.
    public var lastUpdate: Date? { updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
  }

  /// Someone connected to the server's socket: the web app, or an app that keeps one open.
  public struct OnlineUser: Decodable, Identifiable, Sendable {
    public let id: String
    public let username: String
  }

  public struct Listening: Sendable {
    public let sessions: [OpenSession]
    public let online: [OnlineUser]
  }

  /// What's playing (`GET /api/sessions/open`) and who's connected (`GET /api/users/online`).
  public static func listening() async throws -> Listening {
    struct Open: Decodable { let sessions: [OpenSession] }
    struct Online: Decodable { let usersOnline: [OnlineUser] }
    async let open: Open = Audiobookshelf.shared.send("/api/sessions/open")
    async let online: Online = Audiobookshelf.shared.send("/api/users/online")
    let (sessions, users) = try await (open.sessions, online.usersOnline)
    return Listening(
      sessions: sessions.sorted { ($0.lastUpdate ?? .distantPast) > ($1.lastUpdate ?? .distantPast) },
      online: users.sorted { $0.username.localizedStandardCompare($1.username) == .orderedAscending }
    )
  }

  // MARK: - Users

  /// A server account, with its type, status and access.
  public struct Account: Decodable, Identifiable, Sendable, Hashable {
    public let id: String
    public let username: String
    public let type: UserType
    public let isActive: Bool
    public let permissions: Permissions
    /// The libraries they can open, when `permissions.accessAllLibraries` is off.
    public let librariesAccessible: [String]
    /// The tags `permissions.selectedTagsNotAccessible` allows or blocks, when
    /// `permissions.accessAllTags` is off.
    public let itemTagsSelected: [String]
    let lastSeen: Double?

    public var lastSeenDate: Date? { lastSeen.map { Date(timeIntervalSince1970: $0 / 1000) } }

    enum CodingKeys: String, CodingKey {
      case id, username, type, isActive, permissions, librariesAccessible, itemTagsSelected, lastSeen
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      username = try container.decode(String.self, forKey: .username)
      type = try container.decode(UserType.self, forKey: .type)
      isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
      permissions = try container.decodeIfPresent(Permissions.self, forKey: .permissions) ?? Permissions()
      librariesAccessible = try container.decodeIfPresent([String].self, forKey: .librariesAccessible) ?? []
      itemTagsSelected = try container.decodeIfPresent([String].self, forKey: .itemTagsSelected) ?? []
      lastSeen = try container.decodeIfPresent(Double.self, forKey: .lastSeen)
    }
  }

  /// Audiobookshelf's permission flags. A missing flag is off, as the server reads it.
  public struct Permissions: Decodable, Sendable, Hashable {
    public var download = false
    public var update = false
    public var delete = false
    public var upload = false
    public var accessExplicitContent = false
    public var accessAllLibraries = false
    public var accessAllTags = false
    public var selectedTagsNotAccessible = false

    init() {}

    enum CodingKeys: String, CodingKey {
      case download, update, delete, upload, accessExplicitContent, accessAllLibraries, accessAllTags
      case selectedTagsNotAccessible
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      func flag(_ key: CodingKeys) throws -> Bool { try container.decodeIfPresent(Bool.self, forKey: key) ?? false }
      download = try flag(.download)
      update = try flag(.update)
      delete = try flag(.delete)
      upload = try flag(.upload)
      accessExplicitContent = try flag(.accessExplicitContent)
      accessAllLibraries = try flag(.accessAllLibraries)
      accessAllTags = try flag(.accessAllTags)
      selectedTagsNotAccessible = try flag(.selectedTagsNotAccessible)
    }
  }

  /// An account's type, status and access as an editable draft, sent with `PATCH /api/users/:id`.
  /// Audiobookshelf reads `librariesAccessible` and `itemTagsSelected` from inside `permissions`,
  /// and changes `isActive` only when it's in the body.
  public struct AccountChanges: Encodable, Sendable, Equatable {
    public static let kidsTag = "kids"

    public var type: UserType
    public var isActive: Bool
    public var download: Bool
    public var update: Bool
    public var delete: Bool
    public var upload: Bool
    public var accessExplicitContent: Bool
    public var accessAllLibraries: Bool
    public var librariesAccessible: Set<String>
    public var accessAllTags: Bool
    public var itemTagsSelected: Set<String>
    /// Whether the selected tags are blocked rather than the only ones allowed.
    public var selectedTagsNotAccessible: Bool

    public init(_ account: Account) {
      type = account.type
      isActive = account.isActive
      download = account.permissions.download
      update = account.permissions.update
      delete = account.permissions.delete
      upload = account.permissions.upload
      accessExplicitContent = account.permissions.accessExplicitContent
      accessAllLibraries = account.permissions.accessAllLibraries
      librariesAccessible = Set(account.librariesAccessible)
      accessAllTags = account.permissions.accessAllTags
      itemTagsSelected = Set(account.itemTagsSelected)
      selectedTagsNotAccessible = account.permissions.selectedTagsNotAccessible
    }

    /// Books tagged "kids" only, and nothing explicit.
    public mutating func applyKidsPreset() {
      accessAllTags = false
      itemTagsSelected = [Self.kidsTag]
      selectedTagsNotAccessible = false
      accessExplicitContent = false
    }

    /// Audiobookshelf refuses an account limited to no libraries or no tags.
    public var isValid: Bool {
      (accessAllLibraries || !librariesAccessible.isEmpty) && (accessAllTags || !itemTagsSelected.isEmpty)
    }

    private enum Key: String, CodingKey {
      case type, isActive, permissions
      case download, update, delete, upload, accessExplicitContent
      case accessAllLibraries, librariesAccessible, accessAllTags, itemTagsSelected, selectedTagsNotAccessible
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: Key.self)
      // Audiobookshelf accepts admin, user and guest. Root can't be given or taken away.
      if [.admin, .user, .guest].contains(type) {
        try container.encode(type.rawValue, forKey: .type)
      }
      try container.encode(isActive, forKey: .isActive)
      var permissions = container.nestedContainer(keyedBy: Key.self, forKey: .permissions)
      try permissions.encode(download, forKey: .download)
      try permissions.encode(update, forKey: .update)
      try permissions.encode(delete, forKey: .delete)
      try permissions.encode(upload, forKey: .upload)
      try permissions.encode(accessExplicitContent, forKey: .accessExplicitContent)
      try permissions.encode(accessAllLibraries, forKey: .accessAllLibraries)
      try permissions.encode(accessAllLibraries ? [] : librariesAccessible.sorted(), forKey: .librariesAccessible)
      try permissions.encode(accessAllTags, forKey: .accessAllTags)
      try permissions.encode(accessAllTags ? [] : itemTagsSelected.sorted(), forKey: .itemTagsSelected)
      try permissions.encode(!accessAllTags && selectedTagsNotAccessible, forKey: .selectedTagsNotAccessible)
    }
  }

  /// Everyone on the server (`GET /api/users`).
  public static func accounts() async throws -> [Account] {
    struct Response: Decodable { let users: [Account] }
    let response: Response = try await Audiobookshelf.shared.send("/api/users")
    return response.users.sorted { $0.username.localizedStandardCompare($1.username) == .orderedAscending }
  }

  /// Saves an account's type, status and access (`PATCH /api/users/:id`).
  public static func update(_ account: Account, with changes: AccountChanges) async throws -> Account {
    struct Response: Decodable { let user: Account }
    let response: Response = try await Audiobookshelf.shared.send(
      "/api/users/\(account.id)",
      method: .patch,
      body: changes
    )
    return response.user
  }

  /// Deletes an account and its playlists; its listening history stays, unattributed
  /// (`DELETE /api/users/:id`). The server refuses root and the signed-in account.
  public static func delete(_ account: Account) async throws {
    try await Audiobookshelf.shared.send("/api/users/\(account.id)", method: .delete)
  }

  /// Every tag on a book or podcast, in any library (`GET /api/tags`).
  public static func tags() async throws -> [String] {
    struct Response: Decodable { let tags: [String] }
    let response: Response = try await Audiobookshelf.shared.send("/api/tags")
    return response.tags
  }

  // MARK: - Libraries

  /// Something the server is working on, such as a library scan.
  public struct ServerTask: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let description: String?
    public let error: String?
    public let isFailed: Bool
    public let isFinished: Bool
    let action: String?
    let libraryId: String?

    /// The library a scan task is scanning.
    public var scanningLibraryID: String? { action == "library-scan" ? libraryId : nil }

    enum CodingKeys: String, CodingKey {
      case id, title, description, error, isFailed, isFinished, action, data
    }

    private struct Details: Decodable { let libraryId: String? }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      title = try container.decodeIfPresent(String.self, forKey: .title)
      description = try container.decodeIfPresent(String.self, forKey: .description)
      error = try container.decodeIfPresent(String.self, forKey: .error)
      isFailed = try container.decodeIfPresent(Bool.self, forKey: .isFailed) ?? false
      isFinished = try container.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
      action = try container.decodeIfPresent(String.self, forKey: .action)
      // Each kind of task keeps its own data; only a scan's library matters here.
      libraryId = (try? container.decodeIfPresent(Details.self, forKey: .data))?.libraryId
    }
  }

  /// What the server is working on (`GET /api/tasks`).
  public static func tasks() async throws -> [ServerTask] {
    struct Response: Decodable { let tasks: [ServerTask] }
    let response: Response = try await Audiobookshelf.shared.send("/api/tasks")
    return response.tasks
  }

  /// Starts scanning a library's folders for new and changed books (`POST /api/libraries/:id/scan`).
  /// The server answers straight away and scans in the background, as a task.
  public static func scan(libraryID: String) async throws {
    try await Audiobookshelf.shared.send("/api/libraries/\(libraryID)/scan", method: .post)
  }

  // MARK: - Backups

  /// A backup of the server's database and its item and author metadata.
  public struct Backup: Decodable, Identifiable, Sendable {
    public let id: String
    public let serverVersion: String?
    let fileSize: Double?
    let createdAt: Double

    public var date: Date { Date(timeIntervalSince1970: createdAt / 1000) }
    public var bytes: Int64? { fileSize.map { Int64($0) } }
  }

  public struct Backups: Sendable {
    /// Newest first.
    public let backups: [Backup]
    /// The folder on the server they're saved in.
    public let location: String?
  }

  /// The server's backups (`GET /api/backups`).
  public static func backups() async throws -> Backups {
    struct Response: Decodable {
      let backups: [Backup]
      let backupLocation: String?
    }
    let response: Response = try await Audiobookshelf.shared.send("/api/backups")
    return Backups(backups: newestFirst(response.backups), location: response.backupLocation)
  }

  /// Makes a backup now and returns the list after it, with the oldest removed when there are more
  /// than the server keeps (`POST /api/backups`). The server answers when the backup is finished.
  public static func makeBackup() async throws -> [Backup] {
    struct Response: Decodable { let backups: [Backup] }
    let response: Response = try await Audiobookshelf.shared.send("/api/backups", method: .post)
    return newestFirst(response.backups)
  }

  /// Deletes a backup and returns the list after it (`DELETE /api/backups/:id`).
  public static func delete(_ backup: Backup) async throws -> [Backup] {
    struct Response: Decodable { let backups: [Backup] }
    let response: Response = try await Audiobookshelf.shared.send("/api/backups/\(backup.id)", method: .delete)
    return newestFirst(response.backups)
  }

  /// Replaces the server's database and item and author metadata with a backup's
  /// (`GET /api/backups/:id/apply`). Everything changed since the backup is lost.
  public static func restore(_ backup: Backup) async throws {
    try await Audiobookshelf.shared.send("/api/backups/\(backup.id)/apply", method: .get)
  }

  /// When the server backs itself up, and how many backups it keeps.
  public struct BackupSchedule: Codable, Sendable, Equatable {
    /// A cron expression, or nil when automatic backups are off.
    public var cron: String?
    /// The server deletes the oldest backup past this many.
    public var backupsToKeep: Int

    public init(cron: String?, backupsToKeep: Int) {
      self.cron = cron
      self.backupsToKeep = backupsToKeep
    }

    enum CodingKeys: String, CodingKey {
      case cron = "backupSchedule"
      case backupsToKeep
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      // A cron string, or false when automatic backups are off.
      cron = try? container.decodeIfPresent(String.self, forKey: .cron)
      backupsToKeep = (try? container.decodeIfPresent(Int.self, forKey: .backupsToKeep)) ?? 2
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      if let cron {
        try container.encode(cron, forKey: .cron)
      } else {
        try container.encode(false, forKey: .cron)
      }
      try container.encode(backupsToKeep, forKey: .backupsToKeep)
    }
  }

  /// The backup schedule from the server settings. Audiobookshelf has no settings read endpoint;
  /// they come with the signed-in user from `POST /api/authorize`.
  public static func backupSchedule() async throws -> BackupSchedule {
    struct Response: Decodable { let serverSettings: BackupSchedule }
    let response: Response = try await Audiobookshelf.shared.send("/api/authorize", method: .post)
    return response.serverSettings
  }

  /// Saves the backup schedule (`PATCH /api/settings`) and returns the server's copy.
  public static func setBackupSchedule(_ schedule: BackupSchedule) async throws -> BackupSchedule {
    struct Response: Decodable { let serverSettings: BackupSchedule }
    let response: Response = try await Audiobookshelf.shared.send("/api/settings", method: .patch, body: schedule)
    return response.serverSettings
  }

  private static func newestFirst(_ backups: [Backup]) -> [Backup] {
    backups.sorted { $0.createdAt > $1.createdAt }
  }
}
