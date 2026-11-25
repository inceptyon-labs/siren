import API
import SirenKit
import SwiftUI

/// Who's playing what on the server, and who else is connected. Loads on appear and on
/// pull-to-refresh; it doesn't follow the server's socket.
struct SirenServerAdminListening: View {
  @State private var listening: ServerAdmin.Listening?
  @State private var error: String?

  var body: some View {
    List {
      if let listening {
        if !listening.sessions.isEmpty {
          Section("Playing") {
            ForEach(listening.sessions) { session in
              sessionRow(session)
                .listRowBackground(SirenTheme.raised)
            }
          }
        }
        let playing = Set(listening.sessions.compactMap { $0.user?.id })
        let idle = listening.online.filter { !playing.contains($0.id) }
        if !idle.isEmpty {
          Section {
            ForEach(idle) { user in
              Text(user.username)
                .foregroundStyle(SirenTheme.ink)
                .listRowBackground(SirenTheme.raised)
            }
          } header: {
            Text("Online")
          } footer: {
            Text(
              "People with the Audiobookshelf web app or another live-connected app open. Siren listeners show under Playing while a book plays."
            )
          }
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
      if let listening, listening.sessions.isEmpty, listening.online.isEmpty, error == nil {
        ContentUnavailableView(
          "Nobody's Listening",
          systemImage: "headphones",
          description: Text("Pull down to check again.")
        )
      } else if listening == nil, error == nil {
        ProgressView()
      }
    }
    .navigationTitle("Listening Now")
    .task { await load() }
    .refreshable { await load() }
  }

  private func sessionRow(_ session: ServerAdmin.OpenSession) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline) {
        Text(session.user?.username ?? String(localized: "Someone"))
          .font(.headline)
          .foregroundStyle(SirenTheme.ink)
        Spacer()
        if let updated = session.lastUpdate {
          Text(updated.formatted(.relative(presentation: .named)))
            .font(.footnote)
            .foregroundStyle(SirenTheme.secondary)
        }
      }
      if let title = session.displayTitle {
        Text(title)
          .font(SirenType.bookTitle(.subheadline))
          .foregroundStyle(SirenTheme.ink)
      }
      let detail = [session.displayAuthor, position(of: session), session.deviceInfo?.name]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
      if !detail.isEmpty {
        Text(detail)
          .font(.footnote)
          .foregroundStyle(SirenTheme.secondary)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }

  /// "1 hr, 20 min of 9 hr, 41 min".
  private func position(of session: ServerAdmin.OpenSession) -> String? {
    guard let current = session.currentTime else { return nil }
    guard let duration = session.duration, duration > 0 else { return Self.clock(current) }
    return String(localized: "\(Self.clock(current)) of \(Self.clock(duration))")
  }

  private static func clock(_ seconds: Double) -> String {
    Duration.seconds(Int(seconds.rounded())).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
  }

  private func load() async {
    do {
      listening = try await ServerAdmin.listening()
      error = nil
    } catch {
      self.error = "Couldn't load who's listening. \(error.localizedDescription)"
    }
  }
}
