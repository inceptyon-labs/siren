import API
import SirenKit
import SwiftUI

/// Admin tools for the household's Audiobookshelf server: who's listening, users, library scans
/// and backups. Presented as a sheet.
struct SirenServerAdminView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var authentication = Audiobookshelf.shared.authentication

  var body: some View {
    NavigationStack {
      Group {
        if authentication.isSirenAdmin {
          menu
        } else {
          ContentUnavailableView(
            "Admins Only",
            systemImage: "lock",
            description: Text("Sign in with an Audiobookshelf admin account to manage the server.")
          )
          .background(SirenTheme.ground)
        }
      }
      .navigationTitle("Server")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .tint(SirenTheme.tint)
  }

  private var menu: some View {
    List {
      link("Listening Now", systemImage: "headphones") { SirenServerAdminListening() }
      link("Users", systemImage: "person.2") { SirenServerAdminUsers() }
      link("Libraries", systemImage: "books.vertical") { SirenServerAdminLibraries() }
      link("Backups", systemImage: "externaldrive") { SirenServerAdminBackups() }
      link("Chapter Names", systemImage: "list.number") { SirenServerAdminChapters() }
      // ReadMeABook keeps approvals behind its own admin sign-in; API tokens can't reach them.
      if let client = SirenRequests.shared.client, SirenRequests.shared.user?.isAdmin == true {
        Section {
          Link(destination: client.account.url) {
            Label("Approve Requests in ReadMeABook", systemImage: "checkmark.seal")
              .foregroundStyle(SirenTheme.ink)
          }
          .listRowBackground(SirenTheme.raised)
        }
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
  }

  private func link(
    _ title: LocalizedStringKey,
    systemImage: String,
    @ViewBuilder destination: () -> some View
  ) -> some View {
    NavigationLink(destination: destination) {
      Label(title, systemImage: systemImage)
        .foregroundStyle(SirenTheme.ink)
    }
    .listRowBackground(SirenTheme.raised)
  }
}

/// A failed request, as its own list section.
struct SirenAdminErrorSection: View {
  let message: String

  var body: some View {
    Section {
      Label(message, systemImage: "exclamationmark.triangle")
        .foregroundStyle(SirenTheme.ink)
        .listRowBackground(SirenTheme.raised)
    }
  }
}

#Preview {
  SirenServerAdminView()
}
