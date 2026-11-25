import API
import LocalAuthentication
import SwiftUI

/// Several people on one phone. Each profile is one of upstream's server connections (the same
/// server signed in as different users). A profile can ask for Face ID before anyone switches to
/// it. A kids profile opens the assisted player and asks for Face ID before switching away.
@MainActor @Observable
final class SirenProfiles {
  static let shared = SirenProfiles()

  struct Profile: Identifiable {
    let id: String
    let name: String
    let server: String
  }

  /// The signed-in connection; views rebuild when it changes.
  private(set) var activeID: String?
  /// Covers the screen while a switch made outside the profile menu waits for Face ID.
  private(set) var isVerifying = false {
    didSet { isVerifying ? showGateWindow() : hideGateWindow() }
  }
  /// The cover's own window, above sheets and the full-screen player.
  @ObservationIgnored private var gateWindow: UIWindow?
  /// The check failed with no profile to go back to: the cover stays, with an Unlock button.
  private(set) var needsUnlock = false
  /// A switch `switchTo` already checked, so the switch hook doesn't ask again.
  private var approvedSwitch: String?
  /// The last profile that passed its check (or needed none): where a failed check returns to.
  private var verifiedID: String?
  private(set) var locked: Set<String>
  private(set) var kids: Set<String>

  private init() {
    let defaults = UserDefaults.standard
    locked = Set(defaults.stringArray(forKey: SirenSettings.lockedProfiles) ?? [])
    kids = Set(defaults.stringArray(forKey: SirenSettings.kidsProfiles) ?? [])
    activeID = Audiobookshelf.shared.authentication.server?.id
    // A check left unfinished (the app quit at the Face ID prompt) runs again at launch.
    verifiedID = activeID
    if let from = defaults.string(forKey: SirenSettings.pendingProfileCheck) {
      verifiedID = from.isEmpty ? nil : from
      // After init: the cover's view reads `shared`, which isn't set until init returns.
      Task { @MainActor in self.verify() }
    }
    // Every switch lands here, including ones made in the server list or by an invite link,
    // so Face ID and the kids lock can't be skipped by switching another way.
    let previous = Audiobookshelf.shared.onServerSwitched
    Audiobookshelf.shared.onServerSwitched = { [weak self] id, url in
      previous?(id, url)
      MainActor.assumeIsolated { self?.didSwitch(to: id) }
    }
  }

  private func didSwitch(to id: String) {
    let from = activeID
    activeID = id
    if approvedSwitch == id {
      approvedSwitch = nil
      if !isVerifying { verifiedID = id }
      return
    }
    // A check is already open: it covers this switch too, and still returns to `verifiedID`.
    guard !isVerifying else { return }
    guard needsCheck(from: from, to: id) else {
      verifiedID = id
      return
    }
    verify()
  }

  /// Covers the screen and asks for Face ID. On failure it switches back to the last checked
  /// profile, or, with none, keeps the cover up until Face ID passes. The pending check is saved
  /// first, so quitting at the prompt doesn't skip it.
  private func verify() {
    UserDefaults.standard.set(verifiedID ?? "", forKey: SirenSettings.pendingProfileCheck)
    isVerifying = true
    needsUnlock = false
    Task {
      if await Self.authenticate(reason: String(localized: "Switch profiles")) {
        verifiedID = activeID
        finishVerifying()
      } else if let back = verifiedID, Audiobookshelf.shared.authentication.servers[back] != nil {
        approvedSwitch = back
        try? await Audiobookshelf.shared.switchToServer(back)
        finishVerifying()
      } else {
        needsUnlock = true
      }
    }
  }

  func unlock() {
    Task {
      guard await Self.authenticate(reason: String(localized: "Unlock this profile")) else { return }
      verifiedID = activeID
      finishVerifying()
    }
  }

  private func showGateWindow() {
    guard gateWindow == nil,
      let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
    else { return }
    let window = UIWindow(windowScene: scene)
    window.windowLevel = .alert + 1
    window.rootViewController = UIHostingController(rootView: SirenProfileGate())
    window.isHidden = false
    gateWindow = window
  }

  private func hideGateWindow() {
    gateWindow?.isHidden = true
    gateWindow = nil
  }

  private func finishVerifying() {
    UserDefaults.standard.removeObject(forKey: SirenSettings.pendingProfileCheck)
    isVerifying = false
    needsUnlock = false
  }

  private func needsCheck(from: String?, to: String) -> Bool {
    (from.map(kids.contains) ?? false) || locked.contains(to)
  }

  var isKidsActive: Bool { activeID.map(kids.contains) ?? false }

  var profiles: [Profile] {
    Audiobookshelf.shared.authentication.servers.values
      .map { server in
        Profile(
          id: server.id,
          name: server.username ?? server.alias ?? server.baseURL.host() ?? "Profile",
          server: server.alias ?? server.baseURL.host() ?? ""
        )
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  func switchTo(_ id: String) async {
    guard id != activeID else { return }
    if needsCheck(from: activeID, to: id) {
      let name = profiles.first { $0.id == id }?.name ?? ""
      guard await Self.authenticate(reason: String(localized: "Switch to \(name)'s profile")) else { return }
    }
    await Self.closePlayback()
    approvedSwitch = id
    do {
      try await Audiobookshelf.shared.switchToServer(id)
      activeID = Audiobookshelf.shared.authentication.server?.id
      await Self.ensureLibrary()
    } catch {
      approvedSwitch = nil
      Toast(error: "Couldn't switch profiles").show()
    }
  }

  /// Turning protection on is free; turning it off needs Face ID or the passcode.
  func setLocked(_ isOn: Bool, for id: String) async {
    if !isOn, locked.contains(id) {
      guard await Self.authenticate(reason: String(localized: "Stop asking for Face ID")) else { return }
    }
    if isOn { locked.insert(id) } else { locked.remove(id) }
    UserDefaults.standard.set(locked.sorted(), forKey: SirenSettings.lockedProfiles)
  }

  func setKids(_ isOn: Bool, for id: String) async {
    if !isOn, kids.contains(id) {
      guard await Self.authenticate(reason: String(localized: "Turn off the kids profile")) else { return }
    }
    if isOn { kids.insert(id) } else { kids.remove(id) }
    UserDefaults.standard.set(kids.sorted(), forKey: SirenSettings.kidsProfiles)
  }

  /// The book playing and the queue are the previous person's. Close the session under their
  /// sign-in first, so their last progress is saved to them.
  private static func closePlayback() async {
    let player = PlayerManager.shared
    guard player.current != nil || !player.queue.isEmpty else { return }
    (player.current as? BookPlayerModel)?.stopPlayer()
    try? await SessionManager.shared.closeSession()
    player.clearCurrent()
    player.clearQueue()
  }

  /// A fresh sign-in (a new profile or an invite) has no library chosen yet: pick the server's
  /// default book library, else the first one.
  static func ensureLibrary() async {
    let libraries = Audiobookshelf.shared.libraries
    guard let server = Audiobookshelf.shared.authentication.server, libraries.current == nil,
      let fetched = try? await libraries.fetch(serverID: server.id),
      // Still the same profile, and nothing was chosen while the fetch ran.
      Audiobookshelf.shared.authentication.server?.id == server.id, libraries.current == nil
    else { return }
    libraries.current =
      fetched.first { $0.id == server.defaultLibraryID && $0.mediaType == .book }
      ?? fetched.first { $0.mediaType == .book }
      ?? fetched.first
  }

  /// Face ID, Touch ID or the passcode. True when the phone has none set up: nothing to check.
  private static func authenticate(reason: String) async -> Bool {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
    return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
  }
}

/// Hides the app while a profile switch waits for Face ID.
struct SirenProfileGate: View {
  @State private var profiles = SirenProfiles.shared

  var body: some View {
    if profiles.isVerifying {
      SirenTheme.ground
        .ignoresSafeArea()
        .overlay {
          VStack(spacing: 20) {
            Image(systemName: "lock.fill")
              .font(.largeTitle)
              .foregroundStyle(SirenTheme.secondary)
              .accessibilityHidden(true)
            if profiles.needsUnlock {
              Button("Unlock", action: profiles.unlock)
                .buttonStyle(.borderedProminent)
                .tint(SirenTheme.tint)
            } else {
              Text("Waiting for Face ID")
                .font(.subheadline)
                .foregroundStyle(SirenTheme.secondary)
            }
          }
        }
    }
  }
}

/// Profiles on this phone: Face ID and kids settings, and adding another person's sign-in.
struct SirenProfilesView: View {
  @State private var profiles = SirenProfiles.shared
  @State private var showingServerList = false

  var body: some View {
    Form {
      ForEach(profiles.profiles) { profile in
        Section {
          Toggle(
            "Ask for Face ID",
            isOn: Binding(
              get: { profiles.locked.contains(profile.id) },
              set: { isOn in Task { await profiles.setLocked(isOn, for: profile.id) } }
            )
          )
          Toggle(
            "Kids Profile",
            isOn: Binding(
              get: { profiles.kids.contains(profile.id) },
              set: { isOn in Task { await profiles.setKids(isOn, for: profile.id) } }
            )
          )
        } header: {
          HStack {
            Text(profile.name)
            if profile.id == profiles.activeID {
              Text("· Current")
            }
          }
        } footer: {
          Text(profile.server)
        }
        .listRowBackground(SirenTheme.raised)
      }

      Section {
        Button("Add Someone's Sign-In…", systemImage: "person.badge.plus") { showingServerList = true }
          .listRowBackground(SirenTheme.raised)
      } footer: {
        Text(
          "Ask for Face ID: switching to that profile needs Face ID or the passcode. Kids Profile: it opens the assisted player, and switching away needs Face ID or the passcode. Choose what kids can see in Audiobookshelf, with the \"kids\" tag."
        )
      }
    }
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
    .navigationTitle("Profiles")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $showingServerList) {
      ServerListPage(model: ServerListModel())
        .displaySheetScaled()
    }
  }
}
