import API
import SirenKit
import SwiftUI

/// The server's users: type, whether they can sign in, and when they were last seen. Tap one to
/// change their access, swipe to delete, or invite someone new.
struct SirenServerAdminUsers: View {
  @ObservedObject private var authentication = Audiobookshelf.shared.authentication

  @State private var accounts: [ServerAdmin.Account] = []
  @State private var isLoading = true
  @State private var error: String?
  @State private var showingInvite = false
  @State private var deleting: ServerAdmin.Account?

  var body: some View {
    List {
      Section {
        ForEach(accounts) { account in
          accountRow(account)
            .listRowBackground(SirenTheme.raised)
            .swipeActions {
              if canDelete(account) {
                Button("Delete", role: .destructive) { deleting = account }
              }
            }
        }
      }
      if let error {
        SirenAdminErrorSection(message: error)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
    .overlay {
      if accounts.isEmpty, isLoading { ProgressView() }
    }
    .navigationTitle("Users")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Add Someone", systemImage: "person.badge.plus") { showingInvite = true }
      }
    }
    .sheet(isPresented: $showingInvite, onDismiss: { Task { await load() } }) {
      SirenInviteView()
    }
    .sirenDeleteUserDialog($deleting) { account in
      Task { await delete(account) }
    }
    .task { await load() }
    .refreshable { await load() }
  }

  @ViewBuilder
  private func accountRow(_ account: ServerAdmin.Account) -> some View {
    // Only root can change root, and root already has every permission.
    if account.type == .root {
      SirenAdminUserRow(account: account, isYou: isYou(account))
    } else {
      NavigationLink {
        SirenServerAdminUserEditor(
          account: account,
          isYou: isYou(account),
          canDelete: canDelete(account),
          onSaved: { saved in
            if let index = accounts.firstIndex(where: { $0.id == saved.id }) { accounts[index] = saved }
          },
          onDeleted: { deleted in accounts.removeAll { $0.id == deleted.id } }
        )
      } label: {
        SirenAdminUserRow(account: account, isYou: isYou(account))
      }
    }
  }

  private func isYou(_ account: ServerAdmin.Account) -> Bool {
    account.username == authentication.server?.username
  }

  /// Audiobookshelf refuses to delete root or the signed-in account.
  private func canDelete(_ account: ServerAdmin.Account) -> Bool {
    account.type != .root && !isYou(account)
  }

  private func load() async {
    defer { isLoading = false }
    do {
      accounts = try await ServerAdmin.accounts()
      error = nil
    } catch {
      self.error = "Couldn't load the server's users. \(error.localizedDescription)"
    }
  }

  private func delete(_ account: ServerAdmin.Account) async {
    do {
      try await ServerAdmin.delete(account)
      accounts.removeAll { $0.id == account.id }
      Toast(success: "Deleted \(account.username)").show()
    } catch {
      self.error = "Couldn't delete \(account.username). \(error.localizedDescription)"
    }
  }
}

/// A user's name, then their type, whether they're off, and when they were last seen.
struct SirenAdminUserRow: View {
  let account: ServerAdmin.Account
  let isYou: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(isYou ? "\(account.username) (you)" : account.username)
        .foregroundStyle(SirenTheme.ink)
      Text(detail)
        .font(.footnote)
        .foregroundStyle(SirenTheme.secondary)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }

  private var detail: String {
    let seen =
      account.lastSeenDate.map { String(localized: "Seen \($0.formatted(.relative(presentation: .named)))") }
      ?? String(localized: "Never seen")
    return [account.type.sirenName, account.isActive ? nil : String(localized: "Inactive"), seen]
      .compactMap { $0 }
      .joined(separator: " · ")
  }
}

extension UserType {
  var sirenName: String {
    switch self {
    case .root: String(localized: "Root")
    case .admin: String(localized: "Admin")
    case .user: String(localized: "User")
    case .guest: String(localized: "Guest")
    case .unknown: String(localized: "Unknown")
    }
  }
}

extension View {
  /// Asks before deleting a user, then calls `onConfirm`.
  func sirenDeleteUserDialog(
    _ account: Binding<ServerAdmin.Account?>,
    onConfirm: @escaping (ServerAdmin.Account) -> Void
  ) -> some View {
    confirmationDialog(
      "Delete \(account.wrappedValue?.username ?? "")?",
      isPresented: Binding(
        get: { account.wrappedValue != nil },
        set: { if !$0 { account.wrappedValue = nil } }
      ),
      titleVisibility: .visible,
      presenting: account.wrappedValue
    ) { target in
      Button("Delete User", role: .destructive) { onConfirm(target) }
    } message: { target in
      Text("This deletes \(target.username)'s account and playlists from the server. It can't be undone.")
    }
  }
}

/// Edits one user's type, status, permissions, libraries and tags, saved together.
struct SirenServerAdminUserEditor: View {
  let account: ServerAdmin.Account
  let isYou: Bool
  let canDelete: Bool
  var onSaved: (ServerAdmin.Account) -> Void
  var onDeleted: (ServerAdmin.Account) -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var draft: ServerAdmin.AccountChanges
  @State private var libraries: [Library] = []
  @State private var tags: [String] = []
  @State private var isSaving = false
  @State private var error: String?
  @State private var deleting: ServerAdmin.Account?

  init(
    account: ServerAdmin.Account,
    isYou: Bool,
    canDelete: Bool,
    onSaved: @escaping (ServerAdmin.Account) -> Void,
    onDeleted: @escaping (ServerAdmin.Account) -> Void
  ) {
    self.account = account
    self.isYou = isYou
    self.canDelete = canDelete
    self.onSaved = onSaved
    self.onDeleted = onDeleted
    _draft = State(initialValue: ServerAdmin.AccountChanges(account))
  }

  var body: some View {
    Form {
      Section {
        Picker("Type", selection: $draft.type) {
          Text("User").tag(UserType.user)
          Text("Guest").tag(UserType.guest)
          Text("Admin").tag(UserType.admin)
        }
        Toggle("Active", isOn: $draft.isActive)
      } footer: {
        if isYou {
          Text("You can't change your own type or make yourself inactive here.")
        } else {
          Text("Inactive users can't sign in.")
        }
      }
      .disabled(isYou)

      Section("Permissions") {
        Toggle("Download Books", isOn: $draft.download)
        Toggle("Edit Books", isOn: $draft.update)
        Toggle("Delete Books", isOn: $draft.delete)
        Toggle("Upload Books", isOn: $draft.upload)
        Toggle("Explicit Content", isOn: $draft.accessExplicitContent)
      }

      librariesSection
      kidsSection
      tagsSection

      if canDelete {
        Section {
          Button("Delete User", role: .destructive) { deleting = account }
        }
      }

      if let error {
        Section {
          Label(error, systemImage: "exclamationmark.triangle")
            .foregroundStyle(SirenTheme.ink)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
    .navigationTitle(account.username)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        if isSaving {
          ProgressView()
        } else {
          Button("Save", action: save)
            .disabled(!canSave)
        }
      }
    }
    .sirenDeleteUserDialog($deleting) { account in
      Task { await delete(account) }
    }
    .task { await loadChoices() }
  }

  private var librariesSection: some View {
    Section {
      Toggle("All Libraries", isOn: $draft.accessAllLibraries)
      if !draft.accessAllLibraries {
        ForEach(libraries, id: \.id) { library in
          Toggle(library.name, isOn: membership(of: library.id, in: \.librariesAccessible))
        }
      }
    } header: {
      Text("Libraries")
    } footer: {
      if !draft.accessAllLibraries, draft.librariesAccessible.isEmpty {
        Text("Pick at least one library.")
      }
    }
  }

  private var kidsSection: some View {
    Section {
      Button("Kids Preset", systemImage: "figure.and.child.holdinghands") {
        draft.applyKidsPreset()
      }
    } footer: {
      Text("Only books tagged “\(ServerAdmin.AccountChanges.kidsTag)”, and nothing explicit. Save to apply it.")
    }
  }

  private var tagsSection: some View {
    Section {
      Toggle("All Tags", isOn: $draft.accessAllTags)
      if !draft.accessAllTags {
        Picker("Selected Tags", selection: $draft.selectedTagsNotAccessible) {
          Text("Allow").tag(false)
          Text("Block").tag(true)
        }
        .pickerStyle(.segmented)
        ForEach(tagChoices, id: \.self) { tag in
          Toggle(tag, isOn: membership(of: tag, in: \.itemTagsSelected))
        }
      }
    } header: {
      Text("Tags")
    } footer: {
      if !draft.accessAllTags {
        if draft.itemTagsSelected.isEmpty {
          Text("Pick at least one tag.")
        } else if draft.selectedTagsNotAccessible {
          Text("They see every book except ones with a selected tag.")
        } else {
          Text("They see only books with a selected tag.")
        }
      }
    }
  }

  /// The server's tags, plus any selected tag no book has yet.
  private var tagChoices: [String] {
    Set(tags).union(draft.itemTagsSelected).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  private func membership(
    of id: String,
    in set: WritableKeyPath<ServerAdmin.AccountChanges, Set<String>>
  ) -> Binding<Bool> {
    Binding(
      get: { draft[keyPath: set].contains(id) },
      set: { isOn in
        if isOn { draft[keyPath: set].insert(id) } else { draft[keyPath: set].remove(id) }
      }
    )
  }

  private var canSave: Bool {
    draft != ServerAdmin.AccountChanges(account) && draft.isValid
  }

  private func loadChoices() async {
    do {
      async let libraries = Audiobookshelf.shared.libraries.fetch()
      async let tags = ServerAdmin.tags()
      (self.libraries, self.tags) = try await (libraries, tags)
    } catch {
      self.error = "Couldn't load the server's libraries and tags. \(error.localizedDescription)"
    }
  }

  private func save() {
    isSaving = true
    error = nil
    Task {
      defer { isSaving = false }
      do {
        let saved = try await ServerAdmin.update(account, with: draft)
        onSaved(saved)
        Toast(success: "Saved \(saved.username)").show()
        dismiss()
      } catch {
        self.error = "Couldn't save \(account.username). \(error.localizedDescription)"
      }
    }
  }

  private func delete(_ account: ServerAdmin.Account) async {
    do {
      try await ServerAdmin.delete(account)
      onDeleted(account)
      Toast(success: "Deleted \(account.username)").show()
      dismiss()
    } catch {
      self.error = "Couldn't delete \(account.username). \(error.localizedDescription)"
    }
  }
}
