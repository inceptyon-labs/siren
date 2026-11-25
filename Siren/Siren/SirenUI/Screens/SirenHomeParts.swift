import SwiftUI

/// Home's lead: the book you're in, half inked, with Resume.
struct SirenContinueCard: View {
  let book: SirenBook
  var isPlaying = false
  var onOpen: () -> Void
  var onResume: () -> Void

  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    // At accessibility text sizes the details need the full width, so they go under the cover.
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    layout {
      Button(action: onOpen) {
        RevealCover(book: book, showTicks: true, resolution: .large)
          .frame(width: 150, height: 150)
      }
      .buttonStyle(.plain)

      VStack(alignment: .leading, spacing: 4) {
        Text(book.title)
          .font(SirenType.bookTitle(.title2))
          .foregroundStyle(SirenTheme.ink)
          .lineLimit(3)
        Text(book.author)
          .font(.subheadline)
          .foregroundStyle(SirenTheme.secondary)
          .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
        if book.chapterCount > 1, !book.chapterRemaining.isEmpty {
          Text("Ch \(book.currentChapter) · \(book.chapterRemaining) left")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SirenTheme.ink)
            .monospacedDigit()
            .padding(.top, 8)
        }
        if !book.timeLeft.isEmpty {
          Text("\(book.timeLeft) left in book")
            .font(.footnote)
            .foregroundStyle(SirenTheme.secondary)
            .padding(.top, book.chapterCount > 1 ? 0 : 8)
        }
        Button(action: onResume) {
          Label(isPlaying ? "Pause" : "Resume", systemImage: isPlaying ? "pause.fill" : "play.fill")
            .font(.headline)
            .foregroundStyle(SirenTheme.onTint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .padding(.top, 10)
      }
    }
  }
}

/// The personal yearly goal: a slot per book, filled with the covers finished so far.
struct SirenGoalCard: View {
  enum Unit { case books, hours }

  /// Finished books, newest last. Only the first `goal` get a slot.
  let finished: [SirenBook]
  /// Books finished, or hours listened.
  let count: Int
  let goal: Int
  var unit: Unit = .books

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 10)

  private var year: Int { Calendar.current.component(.year, from: .now) }

  private var daysLeft: Int {
    let calendar = Calendar.current
    guard let nextYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return 0 }
    return calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: nextYear).day ?? 0
  }

  private var status: String {
    if count >= goal { return "\(String(year)) goal reached" }
    return "\(String(year)) goal · \(goal - count) to go · \(daysLeft) days left"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(count)")
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(SirenTheme.ink)
          .monospacedDigit()
        Text(unit == .books ? "of \(goal) books" : "of \(goal) hours")
          .font(.headline)
          .foregroundStyle(SirenTheme.ink)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(SirenTheme.secondary.opacity(0.6))
      }
      Text(status)
        .font(.subheadline)
        .foregroundStyle(SirenTheme.secondary)
      if unit == .books, goal <= 60 {
        LazyVGrid(columns: columns, spacing: 6) {
          ForEach(0..<goal, id: \.self) { index in
            if index < finished.count {
              RevealCover(book: finished[index], progress: 1, cornerRadius: 3, shadow: false)
            } else if index < count {
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(SirenTheme.tint.opacity(0.35))
                .aspectRatio(1, contentMode: .fit)
            } else {
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(SirenTheme.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .aspectRatio(1, contentMode: .fit)
            }
          }
        }
      } else {
        ProgressView(value: Double(min(count, goal)), total: Double(max(goal, 1)))
          .tint(SirenTheme.tint)
      }
    }
    .padding(16)
    .background(SirenTheme.raised, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      unit == .books
        ? "\(String(year)) goal: \(count) of \(goal) books finished"
        : "\(String(year)) goal: \(count) of \(goal) hours listened"
    )
  }
}

/// A horizontal row of covers with titles.
struct SirenCoverShelf: View {
  let books: [SirenBook]
  var side: CGFloat = 120
  var onOpen: (SirenBook) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      LazyHStack(alignment: .top, spacing: 14) {
        ForEach(books) { book in
          Button {
            onOpen(book)
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              RevealCover(book: book)
                .frame(width: side, height: side)
              Text(book.title)
                .font(SirenType.bookTitle(.footnote))
                .foregroundStyle(SirenTheme.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(2, reservesSpace: true)
              if !book.author.isEmpty {
                Text(book.author)
                  .font(.caption)
                  .foregroundStyle(SirenTheme.secondary)
                  .lineLimit(1)
              }
            }
            .frame(width: side, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("\(book.title), \(book.author)"))
        }
      }
    }
    .scrollClipDisabled()
  }
}

/// Body text clipped to a few lines, with More only when the clip actually hides something.
struct SirenExpandableText: View {
  let text: String
  var lineLimit = 6

  @State private var isExpanded = false
  @State private var isTruncated = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(text)
        .font(.body)
        .foregroundStyle(SirenTheme.ink)
        .lineLimit(isExpanded ? nil : lineLimit)
        .fixedSize(horizontal: false, vertical: true)
        .background {
          // The full text fits in the clipped frame only when nothing is hidden.
          ViewThatFits(in: .vertical) {
            Text(text)
              .font(.body)
              .fixedSize(horizontal: false, vertical: true)
              .hidden()
              .onAppear { isTruncated = false }
            Color.clear
              .onAppear { isTruncated = true }
          }
          .id(text)
        }
      if isTruncated, !isExpanded {
        Button("More") { isExpanded = true }
          .font(.subheadline.weight(.semibold))
      }
    }
  }
}
