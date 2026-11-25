import API
import SirenKit
import SwiftUI

extension AuthenticationService {
  /// Admins can list the server's users, so only they can send books and see others' progress.
  var isSirenAdmin: Bool {
    server?.userType == .root || server?.userType == .admin
  }
}

extension HouseholdAdmin.Member {
  /// Household plates: admins slate, other listeners plum.
  var plateColor: Color { isAdmin ? Color(sirenHex: 0x3B4A5C) : Color(sirenHex: 0x8E4A8C) }

  /// "Finished it", "41% in" or nil, for one book.
  func status(in progress: [HouseholdAdmin.Progress], itemID: String) -> String? {
    guard let entry = progress.first(where: { $0.libraryItemId == itemID }) else { return nil }
    if entry.isFinished { return String(localized: "Finished it") }
    guard entry.progress > 0 else { return nil }
    return String(localized: "\(Int((entry.progress * 100).rounded()))% in")
  }
}

/// The Send sheet over the server's users. Sending tags the book `for:<username>`.
struct SirenLiveSendSheet: View {
  let book: SirenBook
  var onSent: () -> Void = {}

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var authentication = Audiobookshelf.shared.authentication

  @State private var members: [HouseholdAdmin.Member] = []
  @State private var recipients: [SirenRecipient] = []
  @State private var selection: Set<String> = []
  @State private var isLoading = true
  @State private var isSending = false
  @State private var error: String?

  var body: some View {
    SirenSendSheet(
      book: book,
      recipients: recipients,
      selection: $selection,
      isLoading: isLoading,
      isSending: isSending,
      error: error,
      onSend: send
    )
    .task { await load() }
  }

  private func load() async {
    defer { isLoading = false }
    do {
      let me = authentication.server?.username
      let item = try await HouseholdSend.book(itemID: book.id)
      let sentTo = Set(HouseholdSend.recipients(in: item.tags))
      members = try await HouseholdAdmin.members().filter { $0.username != me && $0.isActive }
      var rows: [SirenRecipient] = []
      for member in members {
        let progress = (try? await HouseholdAdmin.progress(of: member)) ?? []
        let listening = member.status(in: progress, itemID: book.id)
        let sent = sentTo.contains(member.username)
        rows.append(
          SirenRecipient(
            id: member.id,
            name: member.username,
            color: member.plateColor,
            status: sent
              ? [String(localized: "Already sent"), listening].compactMap { $0 }.joined(separator: " · ") : listening,
            unavailable: member.canSee(item) ? nil : String(localized: "Can't see this book")
          )
        )
      }
      recipients = rows
    } catch {
      self.error = "Couldn't load the household. \(error.localizedDescription)"
    }
  }

  private func send() {
    let usernames = members.filter { selection.contains($0.id) }.map(\.username)
    guard !usernames.isEmpty else { return }
    isSending = true
    error = nil
    Task {
      defer { isSending = false }
      do {
        try await HouseholdSend.send(itemID: book.id, to: usernames)
        Toast(success: "Sent to \(usernames.formatted(.list(type: .and)))").show()
        onSent()
        dismiss()
      } catch {
        self.error = "Couldn't send it. \(error.localizedDescription)"
      }
    }
  }
}

/// On a book you sent: who it went to and how far they are. Admins only.
struct SirenSentProgress: View {
  let itemID: String
  let tags: [String]

  @State private var rows: [Row] = []

  private struct Row: Identifiable {
    let id: String
    let name: String
    let color: Color
    let status: String
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if !rows.isEmpty {
        SirenSectionHeader(title: "Sent To")
        VStack(spacing: 0) {
          ForEach(rows) { row in
            HStack(spacing: 12) {
              Text(row.name.first.map { String($0).uppercased() } ?? "?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(row.color, in: Circle())
                .accessibilityHidden(true)
              Text(row.name)
                .foregroundStyle(SirenTheme.ink)
              Spacer()
              Text(row.status)
                .font(.subheadline)
                .foregroundStyle(SirenTheme.secondary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .accessibilityElement(children: .combine)
          }
        }
        .background(SirenTheme.raised, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius))
      }
    }
    .padding(.horizontal, 20)
    .task(id: tags) { await load() }
  }

  private func load() async {
    let usernames = Set(HouseholdSend.recipients(in: tags))
    guard !usernames.isEmpty, let members = try? await HouseholdAdmin.members() else {
      rows = []
      return
    }
    var loaded: [Row] = []
    for member in members where usernames.contains(member.username) {
      let progress = (try? await HouseholdAdmin.progress(of: member)) ?? []
      loaded.append(
        Row(
          id: member.id,
          name: member.username,
          color: member.plateColor,
          status: member.status(in: progress, itemID: itemID) ?? String(localized: "Not started")
        )
      )
    }
    rows = loaded
  }
}

/// Home's "Sent to You": unfinished books tagged `for:<you>`, over upstream's tag listing.
struct SirenSentShelf: View {
  @StateObject private var model: LibraryPage.Model
  /// Changes when Home appears or refreshes, to pick up new sends and finished books.
  var refreshID: Int
  var onOpen: (SirenBook) -> Void

  init(username: String, libraryID: String, refreshID: Int, onOpen: @escaping (SirenBook) -> Void) {
    _model = StateObject(
      wrappedValue: LibraryPageModel(
        destination: .tag(name: HouseholdSend.tag(for: username), libraryID: libraryID)
      )
    )
    self.refreshID = refreshID
    self.onOpen = onOpen
  }

  var body: some View {
    let books = model.items.compactMap { item -> SirenBook? in
      guard case .book(let card) = item else { return nil }
      let book = SirenBook(card: card)
      return book.isFinished ? nil : book
    }
    VStack(alignment: .leading, spacing: 14) {
      if !books.isEmpty {
        SirenSectionHeader(title: "Sent to You")
        SirenCoverShelf(books: books, onOpen: onOpen)
      }
    }
    .task(id: refreshID) { await model.refresh() }
    // Finished books keep their tag, so read every page: unfinished ones may be on a later page.
    .onChange(of: model.items.count) { _, _ in
      // Not mid-refresh: a refresh loads the first page itself.
      if !model.items.isEmpty, !model.isLoading, model.hasMorePages, !model.pageLoadFailed {
        model.loadNextPageIfNeeded()
      }
    }
  }
}
