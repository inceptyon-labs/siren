import API
import SwiftUI

/// The Siren player bound to upstream's `BookPlayer.Model`. Speed, sleep, chapters, bookmarks and
/// the other sheets are upstream's.
struct SirenLivePlayer: View {
  @Bindable var model: BookPlayer.Model
  var onGoToBook: (String) -> Void

  @ObservedObject private var preferences = UserPreferences.shared
  @AppStorage(SirenSettings.playerArt) private var playerArt: PlayerArt = .cover
  @AppStorage(SirenSettings.voiceBoost) private var voiceBoost = false
  @AppStorage(SirenSettings.trimSilence) private var trimSilence = false
  @AppStorage(SirenSettings.trimSilenceSaved) private var trimSaved = 0.0
  @State private var art: PlayerArt = .cover
  @State private var showingSend = false
  /// The book's files and chapters, when it's downloaded and the voice print is chosen.
  @State private var voiceSource: SirenVoicePrint.Source?
  @ObservedObject private var authentication = Audiobookshelf.shared.authentication

  var body: some View {
    SirenPlayerView(
      book: SirenBook(player: model),
      playback: playback,
      pages: pages,
      flags: flags,
      voiceRidges: voiceRidges,
      art: $art
    ) {
      moreMenu
    }
    .task(id: VoiceKey(bookID: model.id, art: playerArt, download: model.downloadState)) { await loadVoicePrint() }
    .onAppear {
      art = pages.last ?? .cover
      model.onAppear()
      UIApplication.shared.isIdleTimerDisabled = preferences.keepScreenAwakeInPlayer
    }
    .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    .onChange(of: preferences.keepScreenAwakeInPlayer) { _, newValue in
      UIApplication.shared.isIdleTimerDisabled = newValue
    }
    .modifier(SirenPlayerSheets(model: model))
    .sheet(isPresented: $showingSend) {
      SirenLiveSendSheet(book: SirenBook(player: model))
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
    }
  }

  /// With Map or Voice print chosen the player opens on it, and the cover is a swipe away. The voice
  /// print needs the book downloaded.
  private var pages: [PlayerArt] {
    switch playerArt {
    case .cover: [.cover]
    case .map: [.cover, .map]
    case .voice: voiceSource == nil ? [.cover] : [.cover, .voice]
    }
  }

  private struct VoiceKey: Equatable {
    let bookID: String
    let art: PlayerArt
    let download: DownloadManager.DownloadState
  }

  private var voiceRidges: [[Double]?]? {
    guard let voiceSource else { return nil }
    _ = SirenAudioScan.shared.revision
    return SirenVoicePrint.ridges(voiceSource, samples: VoicePrintView.samples)
  }

  /// Finds the book's files and reads them, from the one playing now.
  private func loadVoicePrint() async {
    let source = playerArt == .voice ? SirenVoicePrint.source(bookID: model.id) : nil
    let opening = voiceSource == nil && source != nil
    voiceSource = source
    if opening { art = .voice }
    guard let source else { return }
    let now = model.playbackProgress.totalProgress * model.playbackProgress.total
    let current = source.files.lastIndex { $0.start <= now } ?? 0
    let files = source.files[current...] + source.files[..<current]
    await SirenAudioScan.shared.scanAll(files.map(\.url))
  }

  /// Bookmarks as fractions of the book, for the map's flags.
  private var flags: [Double] {
    let total = model.playbackProgress.total
    guard total > 0, let bookmarks = model.bookmarks?.bookmarks else { return [] }
    return bookmarks.map { min(max(Double($0.time) / total, 0), 1) }
  }

  private var playback: SirenPlayback {
    SirenPlayback(player: model, preferences: preferences)
  }

  /// Trim silence only works on downloaded books; once it has saved a minute, it says how much.
  private var trimLabel: String {
    guard trimSaved >= 60 else { return String(localized: "Downloaded books") }
    let saved = Duration.seconds(trimSaved).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    return String(localized: "Saved \(saved)")
  }

  @ViewBuilder private var moreMenu: some View {
    if model.podcastID == nil {
      Button("Go to Book", systemImage: "book") { onGoToBook(model.id) }
    }
    if model.podcastID == nil, authentication.isSirenAdmin {
      Button("Send…", systemImage: "paperplane") { showingSend = true }
    }
    Button("Car Mode", systemImage: "car") { SirenCarMode.shared.open() }
    Button("Queue", systemImage: "list.number") { model.isQueuePresented = true }
    if model.history != nil {
      Button("History", systemImage: "clock.arrow.circlepath", action: model.onHistoryTapped)
    }
    Button("Volume", systemImage: "speaker.wave.2") { model.volume.isPresented = true }
    Button("Equalizer", systemImage: "slider.vertical.3") { model.equalizer.isPresented = true }
    Toggle("Voice Boost", systemImage: "person.wave.2", isOn: $voiceBoost)
    Toggle(isOn: $trimSilence) {
      Label {
        Text("Trim Silence")
        Text(trimLabel)
      } icon: {
        Image(systemName: "waveform.badge.minus")
      }
    }
    Button("Player Settings", systemImage: "gearshape") { model.isSettingsPresented = true }
  }
}

extension SirenPlayback {
  /// Playback state and actions from upstream's player.
  @MainActor init(player model: BookPlayer.Model, preferences: UserPreferences) {
    let progress = model.playbackProgress
    let chapters = model.chapters
    self.init(
      isPlaying: model.isPlaying,
      isLoading: model.isLoading,
      position: progress.progress,
      elapsed: SirenFormat.clock(progress.current),
      remaining: SirenFormat.clock(progress.remaining),
      bookLeft: SirenFormat.span(progress.totalTimeRemaining),
      skipBack: Int(preferences.skipBackwardInterval),
      skipForward: Int(preferences.skipForwardInterval),
      speed: SirenFormat.speed(model.speed.value),
      sleep: Self.sleepLabel(model.timer.current),
      canGoPreviousChapter: chapters?.canGoPreviousChapter ?? false,
      canGoNextChapter: chapters?.canGoNextChapter ?? false,
      onScrub: { value, isDragging in
        progress.isDragging = isDragging
        progress.progress = value
        if !isDragging { progress.onProgressChanged(value) }
      },
      onTogglePlay: model.onTogglePlaybackTapped,
      onSkipBack: { model.onSkipBackwardTapped(seconds: preferences.skipBackwardInterval) },
      onSkipForward: { model.onSkipForwardTapped(seconds: preferences.skipForwardInterval) },
      onPreviousChapter: { chapters?.onPreviousChapterTapped() },
      onNextChapter: { chapters?.onNextChapterTapped() },
      onSpeed: { model.speed.isPresented = true },
      onSleep: { model.timer.isPresented = true },
      onBookmarks: model.onBookmarksTapped,
      onChapters: { chapters?.isPresented = true }
    )
  }

  private static func sleepLabel(_ timer: TimerPickerSheet.Model.Selection) -> String? {
    switch timer {
    case .none: nil
    case .preset(let seconds), .custom(let seconds), .duration(let seconds): SirenFormat.clock(seconds)
    case .chapters(let count): count == 1 ? "End of chapter" : "\(count) chapters"
    case .atTime(let date): date.formatted(date: .omitted, time: .shortened)
    }
  }
}

/// Upstream's player sheets, presented over the Siren player.
private struct SirenPlayerSheets: ViewModifier {
  @Bindable var model: BookPlayer.Model

  func body(content: Content) -> some View {
    content
      .sheet(
        isPresented: Binding(
          get: { model.chapters?.isPresented ?? false },
          set: { model.chapters?.isPresented = $0 }
        )
      ) {
        if let chapters = model.chapters {
          ChapterPickerSheet(model: chapters)
        }
      }
      .adaptiveSheet(isPresented: $model.volume.isPresented) {
        FloatPickerSheet(model: $model.volume)
      }
      .adaptiveSheet(isPresented: $model.equalizer.isPresented) {
        EqualizerSheet(model: model.equalizer)
      }
      .adaptiveSheet(isPresented: $model.speed.isPresented) {
        FloatPickerSheet(model: $model.speed)
      }
      .adaptiveSheet(isPresented: $model.timer.isPresented) {
        TimerPickerSheet(model: $model.timer)
      }
      .sheet(item: $model.timer.completedAlert) { alert in
        TimerCompletedAlertView(model: alert)
      }
      .sheet(
        isPresented: Binding(
          get: { model.bookmarks?.isPresented ?? false },
          set: { model.bookmarks?.isPresented = $0 }
        )
      ) {
        if let bookmarks = model.bookmarks {
          BookmarkViewerSheet(model: bookmarks)
        }
      }
      .sheet(
        isPresented: Binding(
          get: { model.history?.isPresented ?? false },
          set: { model.history?.isPresented = $0 }
        )
      ) {
        if let history = model.history {
          PlaybackHistorySheet(model: history)
        }
      }
      .sheet(isPresented: $model.isQueuePresented) {
        PlayerQueueView(model: PlayerQueueViewModel())
      }
      .sheet(item: $model.pageMatch) { pageMatch in
        PageMatchSheet(model: pageMatch)
      }
      .sheet(item: $model.positionSync) { positionSync in
        PositionSyncSheet(model: positionSync)
      }
      .sheet(isPresented: $model.isSettingsPresented) {
        NavigationStack {
          PlayerPreferencesView()
            .toolbar {
              ToolbarItem(placement: .topBarTrailing) {
                Button("Close", systemImage: "xmark") { model.isSettingsPresented = false }
              }
            }
        }
      }
  }
}

/// The mini player bound to the book that's playing.
struct SirenLiveMiniPlayer: View {
  @Bindable var model: BookPlayer.Model
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    SirenMiniPlayer(
      book: SirenBook(player: model),
      isPlaying: model.isPlaying,
      skipForward: Int(preferences.skipForwardInterval),
      onTogglePlay: model.onTogglePlaybackTapped,
      onSkipForward: { model.onSkipForwardTapped(seconds: preferences.skipForwardInterval) },
      onOpen: { PlayerManager.shared.showFullPlayer() }
    )
  }
}
