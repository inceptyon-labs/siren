import SwiftUI

/// The Siren player bound to upstream's `BookPlayer.Model`. Speed, sleep, chapters, bookmarks and
/// the other sheets are upstream's.
struct SirenLivePlayer: View {
  @Bindable var model: BookPlayer.Model
  var onGoToBook: (String) -> Void

  @ObservedObject private var preferences = UserPreferences.shared
  @State private var art: PlayerArt = .cover

  var body: some View {
    SirenPlayerView(book: SirenBook(player: model), playback: playback, pages: [.cover], art: $art) {
      moreMenu
    }
    .onAppear {
      model.onAppear()
      UIApplication.shared.isIdleTimerDisabled = preferences.keepScreenAwakeInPlayer
    }
    .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    .onChange(of: preferences.keepScreenAwakeInPlayer) { _, newValue in
      UIApplication.shared.isIdleTimerDisabled = newValue
    }
    .modifier(SirenPlayerSheets(model: model))
  }

  private var playback: SirenPlayback {
    let progress = model.playbackProgress
    let chapters = model.chapters
    return SirenPlayback(
      isPlaying: model.isPlaying,
      isLoading: model.isLoading,
      position: progress.progress,
      elapsed: SirenFormat.clock(progress.current),
      remaining: SirenFormat.clock(progress.remaining),
      bookLeft: SirenFormat.span(progress.totalTimeRemaining),
      skipBack: Int(preferences.skipBackwardInterval),
      skipForward: Int(preferences.skipForwardInterval),
      speed: SirenFormat.speed(model.speed.value),
      sleep: sleepLabel,
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

  private var sleepLabel: String? {
    switch model.timer.current {
    case .none: nil
    case .preset(let seconds), .custom(let seconds), .duration(let seconds): SirenFormat.clock(seconds)
    case .chapters(let count): count == 1 ? "End of chapter" : "\(count) chapters"
    case .atTime(let date): date.formatted(date: .omitted, time: .shortened)
    }
  }

  @ViewBuilder private var moreMenu: some View {
    if model.podcastID == nil {
      Button("Go to Book", systemImage: "book") { onGoToBook(model.id) }
    }
    Button("Queue", systemImage: "list.number") { model.isQueuePresented = true }
    if model.history != nil {
      Button("History", systemImage: "clock.arrow.circlepath", action: model.onHistoryTapped)
    }
    Button("Volume", systemImage: "speaker.wave.2") { model.volume.isPresented = true }
    Button("Equalizer", systemImage: "slider.vertical.3") { model.equalizer.isPresented = true }
    Button("Player Settings", systemImage: "gearshape") { model.isSettingsPresented = true }
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
