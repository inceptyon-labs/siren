import API
import SirenKit
import SwiftUI

/// The server's libraries, each with a Scan button, and what the server is working on.
struct SirenServerAdminLibraries: View {
  @State private var libraries: [Library] = []
  @State private var tasks: [ServerAdmin.ServerTask] = []
  @State private var isLoading = true
  @State private var starting: Set<String> = []
  @State private var error: String?

  var body: some View {
    List {
      Section {
        ForEach(libraries, id: \.id) { library in
          libraryRow(library)
            .listRowBackground(SirenTheme.raised)
        }
      } header: {
        Text("Libraries")
      } footer: {
        Text("A scan finds new, changed and missing books in the library's folders.")
      }

      Section("Running") {
        if tasks.isEmpty, !isLoading {
          Text("Nothing running.")
            .foregroundStyle(SirenTheme.secondary)
            .listRowBackground(SirenTheme.raised)
        }
        ForEach(tasks) { task in
          taskRow(task)
            .listRowBackground(SirenTheme.raised)
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
      if libraries.isEmpty, isLoading { ProgressView() }
    }
    .navigationTitle("Libraries")
    .task { await load() }
    .refreshable { await load() }
  }

  private func libraryRow(_ library: Library) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(library.name)
          .foregroundStyle(SirenTheme.ink)
        Text(library.mediaType == .podcast ? "Podcasts" : "Books")
          .font(.footnote)
          .foregroundStyle(SirenTheme.secondary)
      }
      Spacer()
      if isScanning(library) {
        Text("Scanning…")
          .font(.subheadline)
          .foregroundStyle(SirenTheme.secondary)
      } else if starting.contains(library.id) {
        ProgressView()
      } else {
        Button("Scan") { scan(library) }
          .buttonStyle(.bordered)
          .accessibilityLabel("Scan \(library.name)")
      }
    }
  }

  private func taskRow(_ task: ServerAdmin.ServerTask) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(task.title ?? String(localized: "Task"))
        .foregroundStyle(SirenTheme.ink)
      if let description = task.description, !description.isEmpty {
        Text(description)
          .font(.footnote)
          .foregroundStyle(SirenTheme.secondary)
      }
      if task.isFailed {
        Label(task.error ?? String(localized: "Failed"), systemImage: "exclamationmark.triangle")
          .font(.footnote)
          .foregroundStyle(SirenTheme.ink)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private func isScanning(_ library: Library) -> Bool {
    tasks.contains { $0.scanningLibraryID == library.id && !$0.isFinished }
  }

  private func load() async {
    defer { isLoading = false }
    do {
      async let libraries = Audiobookshelf.shared.libraries.fetch()
      async let tasks = ServerAdmin.tasks()
      (self.libraries, self.tasks) = try await (libraries, tasks)
      error = nil
    } catch {
      self.error = "Couldn't load the libraries. \(error.localizedDescription)"
    }
  }

  private func scan(_ library: Library) {
    starting.insert(library.id)
    error = nil
    Task {
      defer { starting.remove(library.id) }
      do {
        try await ServerAdmin.scan(libraryID: library.id)
        Toast(success: "Scanning \(library.name)").show()
        // The server answers before it adds the scan task.
        try? await Task.sleep(for: .seconds(1))
        tasks = (try? await ServerAdmin.tasks()) ?? tasks
      } catch {
        self.error = "Couldn't scan \(library.name). \(error.localizedDescription)"
      }
    }
  }
}
