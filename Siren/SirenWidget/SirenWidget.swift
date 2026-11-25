import SwiftUI
import WidgetKit

@main
struct SirenWidgetBundle: WidgetBundle {
  var body: some Widget {
    SirenWidget()
    SirenLockscreenPlaybackWidget()
    SirenLockscreenBookWidget()
    DailyGoalWidget()
    WeeklyListeningWidget()
    ListeningActivityWidget()
    SleepTimerLiveActivity()
  }
}

struct SirenWidget: Widget {
  let kind: String = "SirenWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: SirenWidgetProvider()) { entry in
      SystemWidgetView(entry: entry)
    }
    .configurationDisplayName("Now Playing")
    .description("Shows your currently playing audiobook or recent books")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

struct SirenLockscreenPlaybackWidget: Widget {
  let kind: String = "SirenLockscreenCircular"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: SirenWidgetProvider()) { entry in
      LockscreenPlaybackWidgetView(entry: entry)
    }
    .configurationDisplayName("Play/Pause")
    .description("Quick play/pause control with progress")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular])
  }
}

struct SirenLockscreenBookWidget: Widget {
  let kind: String = "SirenLockscreenBook"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: SirenWidgetProvider()) { entry in
      LockscreenBookWidgetView(entry: entry)
    }
    .configurationDisplayName("Siren")  // SIREN: Siren name
    .description("Open now playing or recent book")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular])
  }
}

struct LockscreenPlaybackWidgetView: View {
  let entry: SirenWidgetEntry
  @Environment(\.widgetFamily) var widgetFamily

  var body: some View {
    switch widgetFamily {
    case .accessoryCircular:
      CircularPlaybackWidgetView(entry: entry)
    case .accessoryRectangular:
      RectangularBookWidgetView(entry: entry, action: .play)
    default:
      EmptyView()
    }
  }
}

struct LockscreenBookWidgetView: View {
  let entry: SirenWidgetEntry
  @Environment(\.widgetFamily) var widgetFamily

  var body: some View {
    switch widgetFamily {
    case .accessoryCircular:
      CircularBookWidgetView(entry: entry)
    case .accessoryRectangular:
      RectangularBookWidgetView(entry: entry, action: .open)
    default:
      EmptyView()
    }
  }
}
