import API
import SwiftUI

/// The household on this TV: each Audiobookshelf sign-in is a profile, as on the phone. Pick one to
/// switch, add another, or sign one out.
struct TVProfiles: View {
  @State private var account = TVAccount.shared
  @State private var adding = false
  @State private var failure: String?

  private var profiles: [Server] {
    Audiobookshelf.shared.authentication.servers.values.sorted { Self.name($0) < Self.name($1) }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(profiles, id: \.id) { server in
            Button {
              Task { await choose(server) }
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(Self.name(server))
                  Text(server.baseURL.host() ?? server.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(SirenTheme.secondary)
                }
                Spacer()
                if server.id == account.serverID {
                  Image(systemName: "checkmark").foregroundStyle(SirenTheme.tint)
                }
              }
            }
            .contextMenu {
              Button("Sign Out", role: .destructive) { Task { await signOut(server) } }
            }
          }
        } footer: {
          Text("Press and hold a profile to sign it out.")
        }
        Section {
          Button("Add Someone", systemImage: "person.badge.plus") { adding = true }
        }
        if let failure {
          Text(failure).foregroundStyle(SirenTheme.secondary)
        }
      }
      .navigationTitle("Profiles")
    }
    .fullScreenCover(isPresented: $adding) {
      TVSignIn { adding = false }
    }
  }

  static func name(_ server: Server) -> String {
    server.alias ?? server.username ?? server.baseURL.host() ?? ""
  }

  private func choose(_ server: Server) async {
    guard server.id != account.serverID else { return }
    do {
      try await account.switchTo(server.id)
      failure = nil
    } catch {
      failure = error.localizedDescription
    }
  }

  private func signOut(_ server: Server) async {
    if server.id == account.serverID {
      await TVPlayer.shared.stop()
    }
    Audiobookshelf.shared.authentication.logout(serverID: server.id)
    if Audiobookshelf.shared.authentication.server == nil,
      let next = Audiobookshelf.shared.authentication.servers.keys.sorted().first
    {
      try? await account.switchTo(next)
    }
    account.refresh()
  }
}

/// Signs in to an Audiobookshelf server. On the TV the keyboard can come from your iPhone, and
/// saved passwords can fill in.
struct TVSignIn: View {
  var onDone: (() -> Void)?

  @State private var address = "http://"
  @State private var username = ""
  @State private var password = ""
  @State private var isSigningIn = false
  @State private var failure: String?

  var body: some View {
    VStack(spacing: 28) {
      Text("Siren")
        .font(SirenType.bookTitle(.largeTitle))
        .foregroundStyle(SirenTheme.ink)
      Text("Sign in to your Audiobookshelf server.")
        .font(.title3)
        .foregroundStyle(SirenTheme.secondary)
      VStack(spacing: 20) {
        TextField("Server address", text: $address)
          .keyboardType(.URL)
          .textContentType(.URL)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
        TextField("Username", text: $username)
          .textContentType(.username)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
        SecureField("Password", text: $password)
          .textContentType(.password)
      }
      .frame(width: 760)
      Button {
        Task { await signIn() }
      } label: {
        if isSigningIn { ProgressView() } else { Text("Sign In").frame(minWidth: 240) }
      }
      .disabled(isSigningIn || username.isEmpty || address.count < 10)
      if let failure {
        Text(failure)
          .font(.callout)
          .foregroundStyle(SirenTheme.secondary)
          .multilineTextAlignment(.center)
          .frame(width: 760)
      }
      if let onDone {
        Button("Cancel", action: onDone)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(SirenTheme.ground.ignoresSafeArea())
  }

  private func signIn() async {
    isSigningIn = true
    defer { isSigningIn = false }
    var server = address.trimmingCharacters(in: .whitespacesAndNewlines)
    if !server.contains("://") { server = "http://" + server }
    while server.hasSuffix("/") { server.removeLast() }
    do {
      let id = try await Audiobookshelf.shared.authentication.login(
        serverURL: server,
        username: username.trimmingCharacters(in: .whitespaces),
        password: password
      )
      password = ""
      try await TVAccount.shared.switchTo(id)
      onDone?()
    } catch {
      failure = String(localized: "Couldn't sign in. \(error.localizedDescription)")
    }
  }
}
