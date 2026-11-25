import SwiftUI

/// Someone in the household a book can go to.
struct SirenRecipient: Identifiable, Hashable {
  let id: String
  let name: String
  var color = Color(sirenHex: 0x8E4A8C)
  /// Where they are with this book: "41% in", "Finished it", "Already sent".
  var status: String?
  /// Why they can't get it, such as a kids profile that can't see this book. Nil when they can.
  var unavailable: String?

  var initial: String { name.first.map { String($0).uppercased() } ?? "?" }
}

/// Send a book to someone in the household. It lands on their Home under "Sent to You".
struct SirenSendSheet: View {
  let book: SirenBook
  let recipients: [SirenRecipient]
  @Binding var selection: Set<String>
  var isLoading = false
  var isSending = false
  var error: String?
  var onSend: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          bookHeader
            .listRowBackground(SirenTheme.raised)
        }

        Section {
          if isLoading {
            ProgressView()
              .frame(maxWidth: .infinity)
              .listRowBackground(SirenTheme.raised)
          }
          ForEach(recipients) { recipient in
            row(recipient)
              .listRowBackground(SirenTheme.raised)
          }
        } footer: {
          Text(footerText)
        }

        if let error {
          Section {
            Label(error, systemImage: "exclamationmark.triangle")
              .foregroundStyle(SirenTheme.ink)
              .listRowBackground(SirenTheme.raised)
          }
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
          if isSending {
            ProgressView()
          } else {
            Button(action: onSend) {
              Text("Send").foregroundStyle(SirenTheme.onTint)
            }
            .buttonStyle(.borderedProminent)
            .fontWeight(.semibold)
            .disabled(selection.isEmpty)
          }
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

  private func row(_ recipient: SirenRecipient) -> some View {
    let available = recipient.unavailable == nil
    let selected = selection.contains(recipient.id)
    return Button {
      if selected {
        selection.remove(recipient.id)
      } else {
        selection.insert(recipient.id)
      }
    } label: {
      HStack(spacing: 12) {
        Text(recipient.initial)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 36, height: 36)
          .background(recipient.color, in: Circle())
          .opacity(available ? 1 : 0.4)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(recipient.name)
            .font(.body)
            .foregroundStyle(available ? SirenTheme.ink : SirenTheme.secondary)
          if let detail = recipient.unavailable ?? recipient.status {
            Text(detail)
              .font(.subheadline)
              .foregroundStyle(SirenTheme.secondary)
          }
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
    .buttonStyle(.plain)
    .disabled(!available)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var footerText: String {
    if !isLoading, recipients.isEmpty {
      return "No one else is on this server yet. Invite someone from your profile menu on Home."
    }
    if selection.isEmpty {
      return "Choose who to send it to."
    }
    return "It appears on their Home under Sent to You, until they finish it."
  }
}

/// The Send sheet over the demo household.
struct SirenSendSheetDemo: View {
  let book: SirenBook
  @State private var selection: Set<String> = [Demo.sarah.id]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    SirenSendSheet(
      book: book,
      recipients: Demo.household.map { member in
        SirenRecipient(
          id: member.id,
          name: member.name,
          color: member.color,
          status: member.id == Demo.sarah.id ? "41% into \(Demo.glassOrchard.title)" : "Not started",
          unavailable: member.note.map { "\($0) · can't see this book" }
        )
      },
      selection: $selection,
      onSend: { dismiss() }
    )
  }
}

#Preview {
  Color.clear
    .sheet(isPresented: .constant(true)) {
      SirenSendSheetDemo(book: Demo.saltRoad)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
