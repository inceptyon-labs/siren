import SwiftUI

/// Send a book to someone in the household. It lands on their Home under "From <sender>".
struct SirenSendSheet: View {
  let book: SirenBook

  @Environment(\.dismiss) private var dismiss
  @State private var recipients: Set<String> = [Demo.sarah.id]
  @State private var note = ""

  var body: some View {
    NavigationStack {
      List {
        Section {
          bookHeader
            .listRowBackground(SirenTheme.raised)
        }

        Section {
          ForEach(Demo.household) { member in
            memberRow(member)
              .listRowBackground(SirenTheme.raised)
          }
        } footer: {
          Text(footerText)
        }

        Section {
          TextField("Add a note", text: $note, axis: .vertical)
            .lineLimit(1...4)
            .listRowBackground(SirenTheme.raised)
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(SirenTheme.ground)
      .navigationTitle("Send to")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Send") { dismiss() }
            .buttonStyle(.borderedProminent)
            .fontWeight(.semibold)
            .disabled(recipients.isEmpty)
        }
      }
    }
    .tint(SirenTheme.tint)
  }

  private var bookHeader: some View {
    HStack(spacing: 14) {
      RevealCover(book: book, cornerRadius: 4)
        .frame(width: 56, height: 56)
      VStack(alignment: .leading, spacing: 2) {
        Text(book.title)
          .font(SirenType.bookTitle(.headline))
          .foregroundStyle(SirenTheme.ink)
        Text(book.author)
          .font(.subheadline)
          .foregroundStyle(SirenTheme.secondary)
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private func memberRow(_ member: DemoMember) -> some View {
    let available = isAvailable(member)
    let selected = recipients.contains(member.id)
    return Button {
      if selected {
        recipients.remove(member.id)
      } else {
        recipients.insert(member.id)
      }
    } label: {
      HStack(spacing: 12) {
        HouseholdPlate(member: member, size: 36)
          .opacity(available ? 1 : 0.4)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(member.name)
            .font(.body)
            .foregroundStyle(available ? SirenTheme.ink : SirenTheme.secondary)
          status(for: member)
            .font(.subheadline)
            .foregroundStyle(SirenTheme.secondary)
        }
        Spacer(minLength: 8)
        Image(systemName: "checkmark")
          .font(.body.weight(.semibold))
          .foregroundStyle(SirenTheme.tint)
          .opacity(selected ? 1 : 0)
          .accessibilityHidden(true)
      }
      .padding(.vertical, 4)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .disabled(!available)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  /// The kids profile only sees books tagged for kids; this one isn't.
  private func isAvailable(_ member: DemoMember) -> Bool {
    member.note == nil
  }

  private func status(for member: DemoMember) -> Text {
    if let note = member.note {
      return Text("\(note) · not available for this book")
    }
    if member.id == Demo.sarah.id {
      let current = Demo.glassOrchard
      let percent = "\(Int((current.progress * 100).rounded()))%"
      return Text("Listening to \(Text(current.title).font(SirenType.bookTitle(.subheadline))) · \(percent)")
    }
    return Text("Not listening right now")
  }

  private var footerText: String {
    if recipients.isEmpty {
      return "Choose who to send it to."
    }
    let sender = Demo.jason.name
    if recipients == [Demo.sarah.id] {
      return "It appears on her Home under From \(sender). She can listen any time."
    }
    return "It appears on their Home under From \(sender). They can listen any time."
  }
}

#Preview {
  Color.clear
    .sheet(isPresented: .constant(true)) {
      SirenSendSheet(book: Demo.saltRoad)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
