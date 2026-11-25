import API
import SirenKit
import SwiftUI

/// Finds books whose chapters are only numbered and saves Audible's chapter names to them, for
/// every app on the server. Names are saved only when Audible's timings fit the book.
struct SirenServerAdminChapters: View {
  @State private var libraries: [Library] = []
  @State private var libraryID = ""
  @State private var isScanning = false
  @State private var progress: ChapterNames.Progress?
  @State private var results: [ChapterNames.Result]?
  @State private var selected: Set<String> = []
  @State private var saved: Set<String> = []
  @State private var isSaving = false
  @State private var error: String?

  var body: some View {
    List {
      Section {
        if libraries.count > 1 {
          Picker("Library", selection: $libraryID) {
            ForEach(libraries, id: \.id) { library in
              Text(library.name).tag(library.id)
            }
          }
          .disabled(isBusy)
          .listRowBackground(SirenTheme.raised)
        }
        scanRow
          .listRowBackground(SirenTheme.raised)
      } footer: {
        Text(
          "Looks for books whose chapters are only numbered, like \u{201C}Chapter 1\u{201D}, and finds Audible's names for them by ASIN. Only titles change; chapter marks stay where they are. Saving changes the book on the server, for every app."
        )
      }

      if let results {
        resultSections(results)
      }

      if let error {
        SirenAdminErrorSection(message: error)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
    .navigationTitle("Chapter Names")
    .task { await loadLibraries() }
    .onChange(of: libraryID) { _, _ in
      results = nil
      selected = []
      saved = []
    }
  }

  private var isBusy: Bool { isScanning || isSaving }

  @ViewBuilder private var scanRow: some View {
    if isScanning {
      HStack(spacing: 12) {
        ProgressView()
        if let progress {
          Text("Checked \(progress.checked) of \(progress.total) books")
            .foregroundStyle(SirenTheme.secondary)
            .monospacedDigit()
        } else {
          Text("Loading the library…")
            .foregroundStyle(SirenTheme.secondary)
        }
      }
    } else {
      Button(results == nil ? "Find Books" : "Check Again") { scan() }
        .disabled(libraryID.isEmpty || isSaving)
    }
  }

  // MARK: Results

  @ViewBuilder private func resultSections(_ results: [ChapterNames.Result]) -> some View {
    let ready = results.filter { if case .ready = $0.outcome { true } else { false } }
    let numbered = results.filter { if case .noNames = $0.outcome { true } else { false } }
    let differs = results.filter { if case .lengthDiffers = $0.outcome { true } else { false } }
    let marksDiffer = results.filter { if case .marksDiffer = $0.outcome { true } else { false } }
    let missing = results.filter { if case .notFound = $0.outcome { true } else { false } }

    if results.isEmpty {
      Section {
        Text("Every book with an ASIN already has chapter names.")
          .foregroundStyle(SirenTheme.secondary)
          .listRowBackground(SirenTheme.raised)
      }
    }

    if !ready.isEmpty {
      Section {
        ForEach(ready) { result in
          readyRow(result)
            .listRowBackground(SirenTheme.raised)
        }
        let toSave = ready.filter { selected.contains($0.id) && !saved.contains($0.id) }
        if !toSave.isEmpty || isSaving {
          Button {
            save(toSave)
          } label: {
            HStack {
              Text(isSaving ? "Saving…" : "Save Names to ^[\(toSave.count) Book](inflect: true)")
              if isSaving {
                Spacer()
                ProgressView()
              }
            }
          }
          .disabled(isSaving)
          .listRowBackground(SirenTheme.raised)
        }
      } header: {
        Text("Names Found")
      } footer: {
        Text("Tap a book to leave it out.")
      }
    }

    if !differs.isEmpty {
      otherSection(
        "Different Length",
        footer: "Audible's edition is a different length, so its chapters wouldn't line up.",
        results: differs
      )
    }
    if !marksDiffer.isEmpty {
      otherSection(
        "Chapters Break Differently",
        footer: "Audible's chapters start in different places from this book's, so its names wouldn't line up.",
        results: marksDiffer
      )
    }
    if !numbered.isEmpty {
      otherSection("Numbered on Audible Too", footer: nil, results: numbered)
    }
    if !missing.isEmpty {
      otherSection("Not Found on Audible", footer: "Check the book's ASIN in Audiobookshelf.", results: missing)
    }
  }

  private func readyRow(_ result: ChapterNames.Result) -> some View {
    let isSaved = saved.contains(result.id)
    let isSelected = selected.contains(result.id)
    return Button {
      guard !isSaved, !isSaving else { return }
      if isSelected { selected.remove(result.id) } else { selected.insert(result.id) }
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(result.title)
            .font(SirenType.bookTitle(.body))
            .foregroundStyle(SirenTheme.ink)
          Text(preview(result))
            .font(.footnote)
            .foregroundStyle(SirenTheme.secondary)
            .lineLimit(2)
        }
        Spacer(minLength: 8)
        if isSaved {
          Text("Saved")
            .font(.footnote)
            .foregroundStyle(SirenTheme.secondary)
        } else if isSelected {
          Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(SirenTheme.tint)
            .accessibilityHidden(true)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected && !isSaved ? .isSelected : [])
  }

  /// "24 chapters: Prologue, The Boy Who Lived, …"
  private func preview(_ result: ChapterNames.Result) -> String {
    guard case .ready(let chapters) = result.outcome else { return "" }
    let names = chapters.map(\.title).filter { !ChapterNames.isCredits($0) }.prefix(3).joined(separator: ", ")
    return String(localized: "^[\(chapters.count) chapter](inflect: true): \(names)…")
  }

  private func otherSection(
    _ title: LocalizedStringKey,
    footer: LocalizedStringKey?,
    results: [ChapterNames.Result]
  )
    -> some View
  {
    Section {
      ForEach(results) { result in
        VStack(alignment: .leading, spacing: 2) {
          Text(result.title)
            .font(SirenType.bookTitle(.body))
            .foregroundStyle(SirenTheme.ink)
          if case .lengthDiffers(let seconds) = result.outcome {
            Text(lengthText(seconds))
              .font(.footnote)
              .foregroundStyle(SirenTheme.secondary)
          }
        }
        .listRowBackground(SirenTheme.raised)
      }
    } header: {
      Text(title)
    } footer: {
      if let footer { Text(footer) }
    }
  }

  private func lengthText(_ seconds: Double) -> String {
    let amount = Duration.seconds(abs(seconds)).formatted(
      .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)
    )
    return seconds > 0
      ? String(localized: "Audible's is \(amount) longer")
      : String(localized: "Audible's is \(amount) shorter")
  }

  // MARK: Loading and saving

  private func loadLibraries() async {
    do {
      let all = try await Audiobookshelf.shared.libraries.fetch()
      libraries = all.filter { $0.mediaType != .podcast }
      if libraryID.isEmpty {
        let current = Audiobookshelf.shared.libraries.current?.id
        libraryID = libraries.first { $0.id == current }?.id ?? libraries.first?.id ?? ""
      }
    } catch {
      self.error = "Couldn't load the libraries. \(error.localizedDescription)"
    }
  }

  private func scan() {
    let libraryID = libraryID
    error = nil
    isScanning = true
    progress = nil
    Task {
      defer {
        isScanning = false
        progress = nil
      }
      do {
        let found = try await ChapterNames.scan(libraryID: libraryID) { progress = $0 }
        guard libraryID == self.libraryID else { return }
        results = found
        saved = []
        selected = Set(found.compactMap { if case .ready = $0.outcome { $0.id } else { nil } })
      } catch {
        self.error = "Couldn't check the library. \(error.localizedDescription)"
      }
    }
  }

  private func save(_ results: [ChapterNames.Result]) {
    isSaving = true
    error = nil
    Task {
      defer { isSaving = false }
      var failed = 0
      for result in results {
        guard case .ready(let chapters) = result.outcome else { continue }
        do {
          try await ChapterNames.save(chapters, bookID: result.id)
          saved.insert(result.id)
        } catch {
          failed += 1
        }
      }
      if failed > 0 {
        error = String(
          localized: "Couldn't save ^[\(failed) book](inflect: true). Your account needs permission to update books."
        )
      } else {
        Toast(success: String(localized: "Saved chapter names to ^[\(results.count) book](inflect: true)")).show()
      }
    }
  }
}
