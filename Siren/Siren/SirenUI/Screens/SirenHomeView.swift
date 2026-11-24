import Foundation
import SwiftUI

struct SirenHomeView: View {
  var onResume: () -> Void
  var onOpenBook: (DemoBook) -> Void
  var onOpenSettings: () -> Void
  var viewer: DemoMember = Demo.jason

  @Environment(\.horizontalSizeClass) private var sizeClass

  private var isSarah: Bool { viewer.id == Demo.sarah.id }
  private var current: DemoBook { isSarah ? Demo.glassOrchard : Demo.saltRoad }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        if sizeClass == .regular && !isSarah {
          HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
              SirenSectionHeader(title: "Continue Listening")
              continueBlock
              householdRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 14) {
              SirenSectionHeader(title: "Your 2026")
              GoalCard(finished: Demo.finished2026, goal: Demo.yearlyGoal)
            }
            .frame(maxWidth: 460)
          }
          SirenSectionHeader(title: "Requests")
          requests
        } else if isSarah {
          SirenSectionHeader(title: "Continue Listening")
          continueBlock
          SirenSectionHeader(title: "From Jason")
          FromSenderShelf(sender: Demo.jason, books: Demo.sentToSarah)
          GoalCard(finished: Array(Demo.finished2026.suffix(6)), goal: 12)
        } else {
          SirenSectionHeader(title: "Continue Listening")
          continueBlock
          GoalCard(finished: Demo.finished2026, goal: Demo.yearlyGoal)
          householdRow
          SirenSectionHeader(title: "Requests")
          requests
        }
        SirenSectionHeader(title: "Because you liked \(current.title)")
        recommendations
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 32)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(SirenTheme.ground)
    .navigationTitle("Home")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(action: onOpenSettings) {
          HouseholdPlate(member: viewer, size: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings")
      }
    }
  }

  private var continueBlock: some View {
    HStack(alignment: .top, spacing: 16) {
      Button { onOpenBook(current) } label: {
        RevealCover(book: current, showTicks: true)
          .frame(width: 150, height: 150)
      }
      .buttonStyle(.plain)

      VStack(alignment: .leading, spacing: 4) {
        Text(current.title)
          .font(SirenType.bookTitle(.title2))
          .foregroundStyle(SirenTheme.ink)
        Text(current.author)
          .font(.subheadline)
          .foregroundStyle(SirenTheme.secondary)
        Text("Ch \(current.currentChapter) · \(current.chapterRemaining) left")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(SirenTheme.ink)
          .monospacedDigit()
          .padding(.top, 8)
        Text("\(current.timeLeft) left in book")
          .font(.footnote)
          .foregroundStyle(SirenTheme.secondary)
        Button(action: onResume) {
          Label("Resume", systemImage: "play.fill")
            .font(.headline)
            .padding(.horizontal, 6)
            .frame(minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .padding(.top, 10)
      }
    }
  }

  private var householdRow: some View {
    HStack(spacing: 12) {
      HouseholdPlate(member: Demo.sarah, size: 32)
      VStack(alignment: .leading, spacing: 2) {
        Text(Demo.glassOrchard.title)
          .font(SirenType.bookTitle(.headline))
          .foregroundStyle(SirenTheme.ink)
        Text("Sarah is 41% in · you sent it Nov 18")
          .font(.footnote)
          .foregroundStyle(SirenTheme.secondary)
      }
      Spacer(minLength: 8)
      RevealCover(book: Demo.glassOrchard, cornerRadius: 4, shadow: false)
        .frame(width: 40, height: 40)
    }
    .padding(12)
    .background(SirenTheme.raised, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private var requests: some View {
    VStack(spacing: 0) {
      ForEach(Array(Demo.requests.enumerated()), id: \.element.id) { index, book in
        RequestRow(book: book)
        if index < Demo.requests.count - 1 {
          Divider().padding(.leading, 68)
        }
      }
    }
    .background(SirenTheme.raised, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius, style: .continuous))
  }

  private var recommendations: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 14) {
        ForEach([Demo.wolves, Demo.ironAndOrchid, Demo.cartographersWidow]) { book in
          VStack(alignment: .leading, spacing: 6) {
            RevealCover(book: book, progress: book.inLibrary ? book.progress : 0)
              .frame(width: 120, height: 120)
            Text(book.title)
              .font(SirenType.bookTitle(.footnote))
              .foregroundStyle(SirenTheme.ink)
              .lineLimit(2)
            StarRating(rating: book.rating, count: book.ratingCount, compact: true)
          }
          .frame(width: 120, alignment: .leading)
        }
      }
    }
    .scrollClipDisabled()
  }
}

private struct RequestRow: View {
  let book: DemoBook

  var body: some View {
    HStack(spacing: 12) {
      RevealCover(book: book, progress: 0, cornerRadius: 4, shadow: false)
        .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 3) {
        Text(book.title)
          .font(SirenType.bookTitle(.headline))
          .foregroundStyle(SirenTheme.ink)
        if let status = book.request {
          HStack(spacing: 8) {
            Text(status.label)
              .font(.footnote)
              .foregroundStyle(isDownloading(status) ? SirenTheme.tint : SirenTheme.secondary)
              .monospacedDigit()
            if case .downloading(let p) = status {
              ProgressView(value: p)
                .frame(width: 44)
                .tint(SirenTheme.tint)
            }
          }
        }
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(SirenTheme.secondary.opacity(0.6))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  private func isDownloading(_ status: DemoRequestStatus) -> Bool {
    if case .downloading = status { return true }
    return false
  }
}

/// Books someone in the household sent this listener, newest first.
private struct FromSenderShelf: View {
  let sender: DemoMember
  let books: [(book: DemoBook, sent: String, note: String?, progress: Double)]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 14) {
        ForEach(books, id: \.book.id) { item in
          VStack(alignment: .leading, spacing: 6) {
            RevealCover(book: item.book, progress: item.progress)
              .frame(width: 132, height: 132)
              .overlay(alignment: .bottomTrailing) {
                HouseholdPlate(member: sender, size: 26)
                  .overlay(Circle().stroke(SirenTheme.raised, lineWidth: 2))
                  .offset(x: 6, y: 6)
              }
            Text(item.book.title)
              .font(SirenType.bookTitle(.footnote))
              .foregroundStyle(SirenTheme.ink)
              .lineLimit(2)
            Text("Sent \(item.sent)")
              .font(.caption)
              .foregroundStyle(SirenTheme.secondary)
            if let note = item.note {
              Text("\u{201C}\(note)\u{201D}")
                .font(.caption)
                .italic()
                .foregroundStyle(SirenTheme.ink)
                .lineLimit(3)
            }
          }
          .frame(width: 132, alignment: .leading)
          .accessibilityElement(children: .combine)
        }
      }
    }
    .scrollClipDisabled()
  }
}

private struct GoalCard: View {
  let finished: [DemoBook]
  let goal: Int

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 10)

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(finished.count)")
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(SirenTheme.ink)
        Text("of \(goal) books")
          .font(.headline)
          .foregroundStyle(SirenTheme.ink)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(SirenTheme.secondary.opacity(0.6))
      }
      Text("2026 goal · \(goal - finished.count) to go · 37 days left")
        .font(.subheadline)
        .foregroundStyle(SirenTheme.secondary)
      LazyVGrid(columns: columns, spacing: 6) {
        ForEach(0..<goal, id: \.self) { index in
          if index < finished.count {
            RevealCover(book: finished[index], cornerRadius: 3, shadow: false)
          } else {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
              .strokeBorder(SirenTheme.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
              .aspectRatio(1, contentMode: .fit)
          }
        }
      }
    }
    .padding(16)
    .background(SirenTheme.raised, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("2026 goal: \(finished.count) of \(goal) books finished")
  }
}

#Preview {
  NavigationStack {
    SirenHomeView(onResume: {}, onOpenBook: { _ in }, onOpenSettings: {})
  }
}
