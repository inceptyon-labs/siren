import API
import CoreImage.CIFilterBuiltins
import SirenKit
import SwiftUI

/// An admin signs a household member in on their own phone: pick or create their Audiobookshelf
/// account, then show a QR code that signs Siren in as them with an API key. No password.
struct SirenInviteView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var authentication = Audiobookshelf.shared.authentication

  @State private var members: [HouseholdAdmin.Member] = []
  @State private var choice: Choice = .new
  @State private var newName = ""
  @State private var isLoading = true
  @State private var isCreating = false
  @State private var error: String?
  @State private var invite: Invite?

  private enum Choice: Hashable {
    case new
    case member(HouseholdAdmin.Member)
  }

  private struct Invite {
    let name: String
    let url: URL
    let host: String
  }

  var body: some View {
    NavigationStack {
      Group {
        if let invite {
          SirenInviteCode(name: invite.name, url: invite.url, host: invite.host)
        } else {
          picker
        }
      }
      .navigationTitle(invite == nil ? "Invite to Siren" : "Invite for \(invite?.name ?? "")")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if invite == nil {
            Button("Cancel") { dismiss() }
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          if invite == nil {
            if isCreating {
              ProgressView()
            } else {
              Button("Create", action: create)
                .disabled(!canCreate)
            }
          } else {
            Button("Done") { dismiss() }
          }
        }
      }
    }
    .task { await loadMembers() }
  }

  private var picker: some View {
    Form {
      Section {
        choiceRow(.new, title: "Someone New")
        if choice == .new {
          TextField("Username", text: $newName)
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { if canCreate { create() } }
        }
        if isLoading {
          ProgressView()
            .frame(maxWidth: .infinity)
        }
        ForEach(invitable) { member in
          choiceRow(.member(member), title: member.username, detail: member.isAdmin ? "Admin" : nil)
        }
      } header: {
        Text("Who's it for?")
      } footer: {
        Text(
          "Siren signs them in with an Audiobookshelf API key that doesn't expire. To sign them out, delete the key under Settings › API Keys in Audiobookshelf."
        )
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
  }

  private func choiceRow(_ value: Choice, title: String, detail: String? = nil) -> some View {
    Button {
      choice = value
    } label: {
      HStack {
        Text(title)
          .foregroundStyle(SirenTheme.ink)
        Spacer()
        if let detail {
          Text(detail)
            .font(.footnote)
            .foregroundStyle(SirenTheme.secondary)
        }
        if choice == value {
          Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(SirenTheme.tint)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(choice == value ? .isSelected : [])
  }

  /// Everyone but you and the root account (only root can make a key for root).
  private var invitable: [HouseholdAdmin.Member] {
    let me = authentication.server?.username
    return members.filter { $0.username != me && $0.type != .root && $0.isActive }
  }

  private var trimmedName: String {
    newName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canCreate: Bool {
    !isCreating && (choice != .new || !trimmedName.isEmpty)
  }

  private func loadMembers() async {
    defer { isLoading = false }
    do {
      members = try await HouseholdAdmin.members()
    } catch {
      self.error = "Couldn't load the server's users. \(error.localizedDescription)"
    }
  }

  private func create() {
    guard let server = authentication.server else { return }
    isCreating = true
    error = nil
    Task {
      defer { isCreating = false }
      do {
        let member: HouseholdAdmin.Member
        switch choice {
        case .new:
          member = try await HouseholdAdmin.addMember(username: trimmedName)
          // Select the new account, so a retry after a failed key doesn't create it again.
          members.append(member)
          choice = .member(member)
          newName = ""
        case .member(let existing): member = existing
        }
        let date = Date.now.formatted(date: .abbreviated, time: .omitted)
        let key = try await HouseholdAdmin.makeKey(for: member, name: "Siren invite for \(member.username), \(date)")
        let connection = Connection(
          serverURL: server.baseURL,
          token: .apiKey(key: key),
          customHeaders: server.customHeaders,
          alias: server.alias
        )
        guard let url = DeepLinkManager.createConnectionDeepLink(from: connection, includeToken: true) else {
          error = "Couldn't build the invite link."
          return
        }
        let host = server.baseURL.host().map { host in server.baseURL.port.map { "\(host):\($0)" } ?? host }
        invite = Invite(name: member.username, url: url, host: host ?? server.baseURL.absoluteString)
      } catch {
        self.error = "Couldn't create the invite. \(error.localizedDescription)"
      }
    }
  }
}

/// The finished invite: a QR code for the Camera app, and a share button for Messages or AirDrop.
struct SirenInviteCode: View {
  let name: String
  let url: URL
  let host: String

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        if let code = Self.qrCode(url.absoluteString) {
          Image(decorative: code, scale: 1)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius))
            .frame(maxWidth: 300)
            .accessibilityLabel("Invite code for \(name)")
        }

        Text(
          "On \(name)'s iPhone, with Siren installed, point the Camera at this code and tap the Siren link. Siren opens signed in as \(name)."
        )
        .font(.body)
        .foregroundStyle(SirenTheme.ink)
        .multilineTextAlignment(.center)

        ShareLink(
          item: url,
          subject: Text("Siren invite"),
          message: Text("Open this on your iPhone to sign in to Siren.")
        ) {
          Label("Send Invite", systemImage: "square.and.arrow.up")
            .font(.headline)
            .foregroundStyle(SirenTheme.onTint)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(SirenTheme.tint, in: Capsule())
        }
        .buttonStyle(.plain)

        VStack(alignment: .leading, spacing: 8) {
          Label("Connects to \(host). It works wherever that address is reachable.", systemImage: "network")
          Label("Anyone with this code or link can sign in as \(name). Send it only to them.", systemImage: "lock")
        }
        .font(.footnote)
        .foregroundStyle(SirenTheme.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(24)
      .frame(maxWidth: 520)
      .frame(maxWidth: .infinity)
    }
    .background(SirenTheme.ground)
  }

  private static func qrCode(_ text: String) -> CGImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
    return CIContext().createCGImage(output, from: output.extent)
  }
}
