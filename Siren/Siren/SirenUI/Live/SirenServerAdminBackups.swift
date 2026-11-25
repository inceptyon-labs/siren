import API
import SirenKit
import SwiftUI

/// The server's backups: make one, delete one, restore one, and set when the server makes them
/// itself. Siren doesn't download backups; they can run to hundreds of megabytes.
struct SirenServerAdminBackups: View {
  /// The server this screen opened on.
  @State private var serverID = Audiobookshelf.shared.authentication.server?.id
  @State private var backups: [ServerAdmin.Backup] = []
  @State private var location: String?
  /// The server's copy, and the one being edited. Edits save themselves after a short pause.
  @State private var schedule: ServerAdmin.BackupSchedule?
  @State private var draft: ServerAdmin.BackupSchedule?
  @State private var isLoading = true
  @State private var isBackingUp = false
  @State private var working: String?
  @State private var restoring: ServerAdmin.Backup?
  @State private var deleting: ServerAdmin.Backup?
  @State private var error: String?

  /// Audiobookshelf's default schedule, and a weekly one at the same time.
  private static let daily = "30 1 * * *"
  private static let weekly = "30 1 * * 0"

  var body: some View {
    List {
      Section {
        Button(action: backUp) {
          HStack {
            Label("Back Up Now", systemImage: "plus.circle")
            Spacer()
            if isBackingUp { ProgressView() }
          }
        }
        .disabled(isBackingUp)
        .listRowBackground(SirenTheme.raised)
        ForEach(backups) { backup in
          backupRow(backup)
            .listRowBackground(SirenTheme.raised)
        }
      } header: {
        Text("Backups")
      } footer: {
        if let location {
          Text("Saved on the server in \(location).")
        }
      }

      if draft != nil {
        scheduleSection
      }

      if let error {
        SirenAdminErrorSection(message: error)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
    .overlay {
      if backups.isEmpty, draft == nil, isLoading { ProgressView() }
    }
    .navigationTitle("Backups")
    .confirmationDialog(
      "Restore the backup from \(restoring.map(Self.date) ?? "")?",
      isPresented: isPresented($restoring),
      titleVisibility: .visible,
      presenting: restoring
    ) { backup in
      Button("Replace Server Database", role: .destructive) { restore(backup) }
    } message: { backup in
      Text(
        "This replaces the server's database with this backup, for everyone. Users, listening progress and settings changed since \(Self.date(backup)) are lost, and anyone who signed in since then, you included, may have to sign in again. Books added since then come back with a library scan."
      )
    }
    .confirmationDialog(
      "Delete the backup from \(deleting.map(Self.date) ?? "")?",
      isPresented: isPresented($deleting),
      titleVisibility: .visible,
      presenting: deleting
    ) { backup in
      Button("Delete Backup", role: .destructive) { delete(backup) }
    } message: { _ in
      Text("This deletes the backup file from the server.")
    }
    .task { await load() }
    .refreshable { await load() }
    .task(id: draft) { await saveScheduleAfterPause() }
    // Leaving during the pause still saves: this task isn't tied to the view.
    .onDisappear {
      // Only on the server it was edited for: a profile switch also closes this screen.
      guard let draft, draft != schedule, Audiobookshelf.shared.authentication.server?.id == serverID else {
        return
      }
      Task { _ = try? await ServerAdmin.setBackupSchedule(draft) }
    }
  }

  private func backupRow(_ backup: ServerAdmin.Backup) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(Self.date(backup))
          .foregroundStyle(SirenTheme.ink)
        let detail = [
          backup.bytes.map { $0.formatted(.byteCount(style: .file)) },
          backup.serverVersion.map { "v\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        if !detail.isEmpty {
          Text(detail)
            .font(.footnote)
            .foregroundStyle(SirenTheme.secondary)
        }
      }
      Spacer()
      if working == backup.id {
        ProgressView()
      } else {
        Menu {
          Button("Restore…", systemImage: "clock.arrow.circlepath") { restoring = backup }
          Button("Delete…", systemImage: "trash", role: .destructive) { deleting = backup }
        } label: {
          Image(systemName: "ellipsis.circle")
            .imageScale(.large)
        }
        .accessibilityLabel("Actions for the backup from \(Self.date(backup))")
      }
    }
    .swipeActions {
      Button("Delete", role: .destructive) { deleting = backup }
    }
  }

  private var scheduleSection: some View {
    Section {
      Toggle("Automatic Backups", isOn: automatic)
        .listRowBackground(SirenTheme.raised)
      if let cron = draft?.cron {
        Picker("When", selection: cronSelection) {
          Text("Every day at 1:30 AM").tag(Self.daily)
          Text("Every Sunday at 1:30 AM").tag(Self.weekly)
          if cron != Self.daily, cron != Self.weekly {
            Text("Custom: \(cron)").tag(cron)
          }
        }
        .listRowBackground(SirenTheme.raised)
      }
      Stepper(value: Binding(get: { draft?.backupsToKeep ?? 2 }, set: { draft?.backupsToKeep = $0 }), in: 1...99) {
        LabeledContent("Backups to Keep", value: "\(draft?.backupsToKeep ?? 2)")
      }
      .listRowBackground(SirenTheme.raised)
    } header: {
      Text("Schedule")
    } footer: {
      Text(
        "Times are in the server's time zone. When a new backup takes the count past the number to keep, the server deletes the oldest."
      )
    }
  }

  private var automatic: Binding<Bool> {
    Binding(
      get: { draft?.cron != nil },
      set: { isOn in draft?.cron = isOn ? Self.daily : nil }
    )
  }

  private var cronSelection: Binding<String> {
    Binding(get: { draft?.cron ?? Self.daily }, set: { draft?.cron = $0 })
  }

  private func isPresented(_ backup: Binding<ServerAdmin.Backup?>) -> Binding<Bool> {
    Binding(get: { backup.wrappedValue != nil }, set: { if !$0 { backup.wrappedValue = nil } })
  }

  nonisolated private static func date(_ backup: ServerAdmin.Backup) -> String {
    backup.date.formatted(date: .abbreviated, time: .shortened)
  }

  private func load() async {
    defer { isLoading = false }
    do {
      async let list = ServerAdmin.backups()
      async let schedule = ServerAdmin.backupSchedule()
      let (loaded, saved) = try await (list, schedule)
      backups = loaded.backups
      location = loaded.location
      self.schedule = saved
      draft = saved
      error = nil
    } catch {
      self.error = "Couldn't load the backups. \(error.localizedDescription)"
    }
  }

  private func saveScheduleAfterPause() async {
    guard let draft, draft != schedule else { return }
    // A pause, so a run of Stepper taps saves once.
    try? await Task.sleep(for: .milliseconds(700))
    guard !Task.isCancelled else { return }
    do {
      let saved = try await ServerAdmin.setBackupSchedule(draft)
      schedule = saved
      if self.draft == draft { self.draft = saved }
      error = nil
    } catch {
      // A newer edit cancelled this save; that edit saves itself.
      guard !Task.isCancelled, !(error is CancellationError), self.draft == draft else { return }
      self.draft = schedule
      self.error = "Couldn't save the schedule. \(error.localizedDescription)"
    }
  }

  private func backUp() {
    isBackingUp = true
    error = nil
    Task {
      defer { isBackingUp = false }
      do {
        backups = try await ServerAdmin.makeBackup()
        Toast(success: "Backup made").show()
      } catch let failure as URLError where failure.code == .timedOut {
        self.error = "The server is still making the backup. Pull down in a minute to see it."
      } catch {
        self.error = "Couldn't make a backup. \(error.localizedDescription)"
      }
    }
  }

  private func delete(_ backup: ServerAdmin.Backup) {
    working = backup.id
    error = nil
    Task {
      defer { working = nil }
      do {
        backups = try await ServerAdmin.delete(backup)
      } catch {
        self.error = "Couldn't delete the backup. \(error.localizedDescription)"
      }
    }
  }

  private func restore(_ backup: ServerAdmin.Backup) {
    working = backup.id
    error = nil
    Task {
      defer { working = nil }
      do {
        try await ServerAdmin.restore(backup)
        Toast(success: "Restored the backup from \(Self.date(backup))").show()
        await load()
      } catch {
        self.error = "Couldn't restore the backup. \(error.localizedDescription)"
      }
    }
  }
}
