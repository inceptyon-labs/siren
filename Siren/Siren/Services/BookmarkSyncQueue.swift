import API
import Foundation
import Logging
import Models
import SwiftData

final class BookmarkSyncQueue {
  static let shared = BookmarkSyncQueue()

  private var task: Task<Void, Never>?

  private init() {}

  // SIREN: deletes that haven't reached the server, kept per sign-in so they can be retried and
  // so the next pull doesn't bring the bookmark back
  private static let pendingDeletesKey = "siren.pendingBookmarkDeletes"

  var pendingDeletes: Set<String> {
    get {
      let storage = Audiobookshelf.shared.authentication.server?.storage
      return Set(storage?.stringArray(forKey: Self.pendingDeletesKey) ?? [])
    }
    set {
      Audiobookshelf.shared.authentication.server?.storage.set(newValue.sorted(), forKey: Self.pendingDeletesKey)
    }
  }

  func syncPending() {
    guard task == nil else {
      AppLogger.player.info("Bookmark sync already in progress")
      return
    }

    task = Task {
      defer { task = nil }

      await retryPendingDeletes()

      do {
        var pendingBookmarks = try Bookmark.fetchAll()
        pendingBookmarks = pendingBookmarks.filter { [.pending, .failed].contains($0.status) }

        guard !pendingBookmarks.isEmpty else {
          AppLogger.player.info("No pending bookmarks to sync")
          return
        }

        AppLogger.player.info("Syncing \(pendingBookmarks.count) pending bookmark(s)")

        for bookmark in pendingBookmarks {
          await sync(bookmark, retrying: true)
        }

        AppLogger.player.info("Bookmark sync completed")
      } catch {
        AppLogger.player.error("Failed to fetch pending bookmarks: \(error)")
      }
    }
  }

  /// Sends a bookmark. A retry may be an edit the server already has a copy of, so it updates
  /// first and creates only when the server has none.
  private func sync(_ bookmark: Bookmark, retrying: Bool = false) async {
    let bookID = bookmark.bookID
    let title = bookmark.title
    let time = bookmark.time

    do {
      let createdBookmark: User.Bookmark
      if retrying {
        createdBookmark = try await updateOrCreate(bookmark)
      } else {
        createdBookmark = try await Audiobookshelf.shared.bookmarks.create(bookID: bookID, title: title, time: time)
      }

      bookmark.status = .synced
      bookmark.createdAt = Date(
        timeIntervalSince1970: TimeInterval(createdBookmark.createdAt / 1000)
      )
      try bookmark.save()

      AppLogger.player.info("Successfully synced bookmark: \(title)")
    } catch {
      bookmark.status = .failed
      try? bookmark.save()

      AppLogger.player.error("Failed to sync bookmark \(title): \(error)")
    }
  }

  func create(
    bookID: String,
    title: String,
    time: Int
  ) async throws -> Bookmark {
    let bookmark = Bookmark(
      bookID: bookID,
      time: time,
      title: title,
      createdAt: Date(),
      status: .pending
    )

    try bookmark.save()

    Task { @MainActor in
      await sync(bookmark)
    }

    return bookmark
  }

  func update(
    bookmark: Bookmark,
    newTitle: String
  ) async throws {
    let bookID = bookmark.bookID
    let time = bookmark.time
    let createdAt = bookmark.createdAt

    bookmark.title = newTitle
    bookmark.status = .pending
    try bookmark.save()

    Task { @MainActor in
      do {
        let apiBookmark = User.Bookmark(
          bookID: bookID,
          time: Double(time),
          title: newTitle,
          createdAt: Int64(createdAt.timeIntervalSince1970 * 1000)
        )

        _ = try await Audiobookshelf.shared.bookmarks.update(bookmark: apiBookmark)

        bookmark.status = .synced
        try bookmark.save()

        AppLogger.player.info("Successfully updated bookmark: \(newTitle)")
      } catch {
        bookmark.status = .failed
        try? bookmark.save()

        AppLogger.player.error("Failed to update bookmark: \(error)")
      }
    }
  }

  func delete(_ bookmark: Bookmark) async throws {
    let bookID = bookmark.bookID
    let time = bookmark.time
    let title = bookmark.title
    let key = Bookmark.pendingKey(bookID: bookID, time: time)

    try bookmark.delete()
    pendingDeletes.insert(key)

    Task { @MainActor in
      do {
        try await Audiobookshelf.shared.bookmarks.delete(bookID: bookID, time: time)
        pendingDeletes.remove(key)
        AppLogger.player.info("Successfully deleted bookmark from server: \(title)")
      } catch {
        AppLogger.player.error("Failed to delete bookmark from server, will retry: \(error)")
      }
    }
  }

  private func updateOrCreate(_ bookmark: Bookmark) async throws -> User.Bookmark {
    let apiBookmark = User.Bookmark(
      bookID: bookmark.bookID,
      time: Double(bookmark.time),
      title: bookmark.title,
      createdAt: Int64(bookmark.createdAt.timeIntervalSince1970 * 1000)
    )
    do {
      return try await Audiobookshelf.shared.bookmarks.update(bookmark: apiBookmark)
    } catch NetworkError.httpError(let statusCode, _) where statusCode == 404 {
      return try await Audiobookshelf.shared.bookmarks.create(
        bookID: bookmark.bookID,
        title: bookmark.title,
        time: bookmark.time
      )
    }
  }

  private func retryPendingDeletes() async {
    for key in pendingDeletes {
      let parts = key.split(separator: "|", maxSplits: 1)
      guard parts.count == 2, let time = Int(parts[1]) else {
        pendingDeletes.remove(key)
        continue
      }
      do {
        try await Audiobookshelf.shared.bookmarks.delete(bookID: String(parts[0]), time: time)
        pendingDeletes.remove(key)
      } catch NetworkError.httpError(let statusCode, _) where statusCode == 404 {
        pendingDeletes.remove(key)  // already gone on the server
      } catch {
        AppLogger.player.error("Failed to delete bookmark from server: \(error)")
      }
    }
  }
}
