import SwiftUI

/// Search tab root. "Request" searches the Audible catalog through ReadMeABook; "In library"
/// searches the books already on the server.
struct SirenRequestSearchView: View {
  @Binding var query: String

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var scope: Scope = .request
  @State private var requested: Set<String> = []

  private enum Scope: Hashable {
    case library, request
  }

  private var results: [DemoBook] {
    switch scope {
    case .library: Demo.catalogResults.filter { $0.inLibrary }
    case .request: Demo.catalogResults
    }
  }

  private var hasQuery: Bool {
    !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    List {
      Section {
        Picker("Search in", selection: $scope) {
          Text("In library").tag(Scope.library)
          Text("Request").tag(Scope.request)
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      }

      if hasQuery {
        Section {
          ForEach(results) { book in
            resultRow(book)
              .listRowBackground(SirenTheme.raised)
          }
        } footer: {
          if scope == .request {
            Text("Requests go to ReadMeABook. You'll get a notification when a book is ready.")
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .listSectionSpacing(.compact)
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
    .overlay {
      if !hasQuery {
        ContentUnavailableView(
          "Find a Book",
          systemImage: "magnifyingglass",
          description: Text(
            scope == .request
              ? "Search the Audible catalog. Books you don't have can be requested."
              : "Search your library by title, author or narrator.")
        )
      }
    }
    .navigationTitle("Search")
    .navigationBarTitleDisplayMode(.large)
    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Title, author or narrator")
  }

  // MARK: Rows

  private func resultRow(_ book: DemoBook) -> some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    return layout {
      HStack(alignment: .top, spacing: 12) {
        RevealCover(book: book, progress: book.inLibrary ? book.progress : 0, cornerRadius: 4)
          .frame(width: 56, height: 56)
        VStack(alignment: .leading, spacing: 3) {
          Text(book.title)
            .font(SirenType.bookTitle(.body))
            .foregroundStyle(SirenTheme.ink)
          Text(byline(for: book))
            .font(.subheadline)
            .foregroundStyle(SirenTheme.secondary)
          if book.rating > 0 || book.hours > 0 {
            ViewThatFits(in: .horizontal) {
              HStack(spacing: 8) { meta(for: book) }
              VStack(alignment: .leading, spacing: 2) { meta(for: book) }
            }
            .padding(.top, 2)
          }
          stateControl(for: book)
            .fixedSize()
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.vertical, 6)
  }

  @ViewBuilder private func meta(for book: DemoBook) -> some View {
    if book.rating > 0 {
      StarRating(rating: book.rating, count: book.ratingCount)
    }
    if book.hours > 0 {
      Text(lengthText(book.hours))
        .font(.footnote)
        .foregroundStyle(SirenTheme.secondary)
        .monospacedDigit()
    }
  }

  private func byline(for book: DemoBook) -> String {
    guard let series = book.series else { return book.author }
    guard let index = book.seriesIndex else { return "\(book.author) · \(series)" }
    return "\(book.author) · \(series), Book \(index)"
  }

  private func lengthText(_ hours: Double) -> String {
    let minutes = Int((hours * 60).rounded())
    return "\(minutes / 60)h \(minutes % 60)m"
  }

  // MARK: State control

  /// The one vocabulary for a result's trailing control.
  private enum RowState {
    case play
    case downloading(Double)
    case pending(DemoRequestStatus)
    case requested
    case requestable(releaseDate: String?)
  }

  private func rowState(for book: DemoBook) -> RowState {
    if book.inLibrary { return .play }
    if requested.contains(book.id) { return .requested }
    if let request = book.request {
      if case .downloading(let fraction) = request { return .downloading(fraction) }
      return .pending(request)
    }
    return .requestable(releaseDate: book.releaseDate)
  }

  @ViewBuilder private func stateControl(for book: DemoBook) -> some View {
    switch rowState(for: book) {
    case .play:
      Button("Play") {}
        .buttonStyle(RequestSearchCapsuleStyle(filled: false))
        .accessibilityLabel("Play \(book.title)")
    case .downloading(let fraction):
      VStack(alignment: .leading, spacing: 5) {
        Text(DemoRequestStatus.downloading(fraction).label)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(SirenTheme.tint)
          .monospacedDigit()
        ProgressView(value: fraction)
          .tint(SirenTheme.tint)
          .frame(width: 72)
          .accessibilityHidden(true)
      }
    case .pending(let status):
      Text(status.label)
        .font(.footnote)
        .foregroundStyle(SirenTheme.secondary)
    case .requested:
      Label("Requested", systemImage: "checkmark")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(SirenTheme.secondary)
    case .requestable(let releaseDate):
      VStack(alignment: .trailing, spacing: 0) {
        Button("Request") {
          requested.insert(book.id)
        }
        .buttonStyle(RequestSearchCapsuleStyle(filled: releaseDate == nil))
        .accessibilityLabel("Request \(book.title)")
        if let releaseDate {
          Text("Out \(releaseDate)")
            .font(.caption)
            .foregroundStyle(SirenTheme.secondary)
        }
      }
    }
  }
}

/// Filled for a book you can request now; tinted for Play and for books not yet released.
/// Draws 30pt tall and keeps a 44pt hit area.
private struct RequestSearchCapsuleStyle: ButtonStyle {
  var filled: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(filled ? SirenTheme.onTint : SirenTheme.tint)
      .padding(.horizontal, 16)
      .frame(minWidth: 76, minHeight: 30)
      .background(filled ? SirenTheme.tint : SirenTheme.tintWash, in: Capsule())
      .padding(.vertical, 7)
      .contentShape(Rectangle())
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

#Preview {
  @Previewable @State var query = "Kessling"
  NavigationStack {
    SirenRequestSearchView(query: $query)
  }
  .tint(SirenTheme.tint)
}
