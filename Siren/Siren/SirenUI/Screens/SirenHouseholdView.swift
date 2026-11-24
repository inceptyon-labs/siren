import Foundation
import SwiftUI

/// Household tab: who is listening, what you've sent, and (admins only) the server.
struct SirenHouseholdView: View {
  var body: some View {
    List {
      Section("Listening now") {
        memberRow(
          Demo.sarah,
          book: Demo.glassOrchard,
          detail: "41% · Ch 11 · listening now",
          live: true
        )
        memberRow(Demo.kids, book: nil, detail: "Last listened Saturday", live: false)
      }

      Section {
        sentRow(Demo.harborOfBells, to: Demo.sarah, status: "Sent today · not started")
        sentRow(Demo.saltRoad, to: Demo.sarah, status: "Sent today · not started")
        sentRow(Demo.glassOrchard, to: Demo.sarah, status: "41% in · sent Nov 18")
        sentRow(Demo.smallHours, to: Demo.sarah, status: "Sent Oct 2 · finished Oct 30")
      } header: {
        Text("Sent by you")
      }

      Section {
        adminRow("checkmark.circle", "Requests to approve", value: "1", badge: true)
        adminRow("person.2", "Users", value: "3")
        adminRow("externaldrive", "Backups", value: "Today 3:00 AM")
        adminRow("arrow.triangle.2.circlepath", "Library scan", value: "2h ago")
      } header: {
        Text("Server")
      } footer: {
        Text("Only admins see this section.")
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
    .navigationTitle("Household")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
        } label: {
          Image(systemName: "person.badge.plus")
        }
        .accessibilityLabel("Add household member")
      }
    }
  }

  private func memberRow(_ member: DemoMember, book: DemoBook?, detail: String, live: Bool) -> some View {
    HStack(spacing: 12) {
      HouseholdPlate(member: member, size: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text(member.name)
          .font(.headline)
          .foregroundStyle(SirenTheme.ink)
        if let book {
          Text(book.title)
            .font(SirenType.bookTitle(.subheadline))
            .foregroundStyle(SirenTheme.ink)
        }
        HStack(spacing: 6) {
          if live {
            Circle().fill(Color(sirenLight: 0x1E8A4C, dark: 0x4CC383)).frame(width: 7, height: 7)
          }
          Text(detail)
            .font(.footnote)
            .foregroundStyle(SirenTheme.secondary)
        }
      }
      Spacer(minLength: 8)
      if let book {
        RevealCover(book: book, cornerRadius: 4, shadow: false)
          .frame(width: 44, height: 44)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }

  private func sentRow(_ book: DemoBook, to member: DemoMember, status: String) -> some View {
    HStack(spacing: 12) {
      RevealCover(book: book, progress: progress(of: book, for: member), cornerRadius: 4, shadow: false)
        .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 2) {
        Text(book.title)
          .font(SirenType.bookTitle(.body))
          .foregroundStyle(SirenTheme.ink)
        Text(status)
          .font(.footnote)
          .foregroundStyle(SirenTheme.secondary)
      }
      Spacer(minLength: 8)
      HouseholdPlate(member: member, size: 24)
    }
    .accessibilityElement(children: .combine)
  }

  /// How far the recipient is, which is what the sender's cover shows here.
  private func progress(of book: DemoBook, for member: DemoMember) -> Double {
    switch book.id {
    case Demo.glassOrchard.id: 0.41
    case Demo.smallHours.id: 1
    default: 0
    }
  }

  private func adminRow(_ symbol: String, _ title: String, value: String, badge: Bool = false) -> some View {
    NavigationLink {
      ContentUnavailableView(title, systemImage: symbol)
    } label: {
      HStack {
        Label(title, systemImage: symbol)
          .foregroundStyle(SirenTheme.ink)
        Spacer()
        if badge {
          Text(value)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SirenTheme.onTint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(SirenTheme.tint, in: Capsule())
        } else {
          Text(value)
            .font(.subheadline)
            .foregroundStyle(SirenTheme.secondary)
        }
      }
    }
  }
}

#Preview {
  NavigationStack { SirenHouseholdView() }
}
