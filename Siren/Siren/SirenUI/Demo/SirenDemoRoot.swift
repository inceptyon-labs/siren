import Foundation
import SwiftUI

/// Launch with `-SirenDemo <screen>` to open a demo screen instead of the app.
enum SirenDemoScreen: String, CaseIterable {
  case home, library, book, send, request, car, household
  case homeSarah = "home-sarah"
  case playerCover = "player-cover"
  case playerMap = "player-map"
  case playerVoice = "player-voice"
  case settingsArt = "settings-art"

  static var requested: SirenDemoScreen? {
    UserDefaults.standard.string(forKey: "SirenDemo").flatMap(SirenDemoScreen.init(rawValue:))
  }
}

enum PlayerArt: Int, CaseIterable, Identifiable {
  case cover, map, voice
  var id: Int { rawValue }
  var label: String {
    switch self {
    case .cover: "Cover"
    case .map: "Map"
    case .voice: "Voice print"
    }
  }
}

enum SirenTab: Hashable { case home, library, household, search }

enum SirenRoute: Hashable {
  case book(String)
  case progressArt
}

struct SirenRootSwitch: View {
  var body: some View {
    if let screen = SirenDemoScreen.requested {
      SirenDemoRoot(screen: screen)
    } else {
      ContentView()
    }
  }
}

struct SirenDemoRoot: View {
  let screen: SirenDemoScreen

  @State private var tab: SirenTab = .home
  @State private var homePath: [SirenRoute] = []
  @State private var showPlayer = false
  @State private var playerArt: PlayerArt = .cover
  @State private var showCar = false
  @State private var showSend = false
  @State private var searchText = ""
  @State private var viewer = Demo.jason

  var body: some View {
    shell
      .tint(SirenTheme.tint)
      .onAppear(perform: route)
      .sheet(isPresented: $showPlayer) {
        SirenPlayerView(art: $playerArt, onCarMode: { showPlayer = false; showCar = true })
          .presentationDragIndicator(.visible)
          .sirenPageSizing()
      }
      .sheet(isPresented: $showSend) {
        SirenSendSheet(book: Demo.saltRoad)
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
      }
      .fullScreenCover(isPresented: $showCar) {
        SirenCarModeView(onClose: { showCar = false })
      }
  }

  private func route() {
    switch screen {
    case .home: break
    case .homeSarah: viewer = Demo.sarah
    case .household: tab = .household
    case .library: tab = .library
    case .book: homePath = [.book(Demo.saltRoad.id)]
    case .send:
      homePath = [.book(Demo.saltRoad.id)]
      showSend = true
    case .request:
      tab = .search
      searchText = "Kessling"
    case .car: showCar = true
    case .playerCover: open(.cover)
    case .playerMap: open(.map)
    case .playerVoice: open(.voice)
    case .settingsArt: homePath = [.progressArt]
    }
  }

  private func open(_ art: PlayerArt) {
    playerArt = art
    showPlayer = true
  }

  @ViewBuilder private var shell: some View {
    if #available(iOS 26.0, *) {
      TabView(selection: $tab) {
        Tab("Home", systemImage: "house", value: SirenTab.home) {
          NavigationStack(path: $homePath) {
            SirenHomeView(
              onResume: { open(.cover) },
              onOpenBook: { homePath.append(.book($0.id)) },
              onOpenSettings: { homePath.append(.progressArt) },
              viewer: viewer
            )
            .navigationDestination(for: SirenRoute.self, destination: destination)
          }
        }
        Tab("Library", systemImage: "books.vertical", value: SirenTab.library) {
          NavigationStack { SirenLibraryView() }
        }
        Tab("Household", systemImage: "person.2", value: SirenTab.household) {
          NavigationStack { SirenHouseholdView() }
        }
        Tab(value: SirenTab.search, role: .search) {
          NavigationStack { SirenRequestSearchView(query: $searchText) }
        }
      }
      .tabViewBottomAccessory {
        SirenMiniPlayer(book: viewer.id == Demo.sarah.id ? Demo.glassOrchard : Demo.saltRoad) { open(.cover) }
      }
    } else {
      NavigationStack(path: $homePath) {
        SirenHomeView(
          onResume: { open(.cover) },
          onOpenBook: { homePath.append(.book($0.id)) },
          onOpenSettings: { homePath.append(.progressArt) }
        )
        .navigationDestination(for: SirenRoute.self, destination: destination)
      }
    }
  }

  @ViewBuilder private func destination(_ route: SirenRoute) -> some View {
    switch route {
    case .book(let id):
      SirenBookDetailView(
        book: Demo.tidewater.first { $0.id == id } ?? Demo.saltRoad,
        onSend: { showSend = true },
        onPlay: { open(.cover) }
      )
    case .progressArt:
      SirenProgressArtSettingsView()
    }
  }
}

struct SirenMiniPlayer: View {
  let book: DemoBook
  var onOpen: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      RevealCover(book: book, cornerRadius: 4, shadow: false)
        .frame(width: 34, height: 34)
      VStack(alignment: .leading, spacing: 1) {
        Text(book.title)
          .font(SirenType.bookTitle(.subheadline))
          .foregroundStyle(SirenTheme.ink)
        Text("Ch \(book.currentChapter) · \(book.chapterRemaining) left")
          .font(.caption)
          .foregroundStyle(SirenTheme.secondary)
          .monospacedDigit()
      }
      Spacer(minLength: 8)
      Button {} label: {
        Image(systemName: "pause.fill").font(.title3)
      }
      .buttonStyle(.plain)
      .frame(width: 44, height: 44)
      .accessibilityLabel("Pause")
      Button {} label: {
        Image(systemName: "goforward.30").font(.title3)
      }
      .buttonStyle(.plain)
      .frame(width: 44, height: 44)
      .accessibilityLabel("Forward 30 seconds")
    }
    .foregroundStyle(SirenTheme.ink)
    .padding(.leading, 10)
    .padding(.trailing, 4)
    .contentShape(Rectangle())
    .onTapGesture(perform: onOpen)
  }
}

extension View {
  /// Full-page player sheet on iPad; iPhone sheets are already full height.
  @ViewBuilder func sirenPageSizing() -> some View {
    if #available(iOS 18.0, *) {
      presentationSizing(.page)
    } else {
      self
    }
  }
}
