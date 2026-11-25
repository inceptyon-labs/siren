import AVFoundation
import SwiftUI

/// Whether car mode is open, the car or Bluetooth output in use, and the devices that open car
/// mode by themselves when they connect.
@MainActor @Observable
final class SirenCarMode {
  static let shared = SirenCarMode()

  var isPresented = false
  /// The Bluetooth or car output in use; nil on the speaker, wired headphones or AirPlay.
  private(set) var deviceName: String?
  private(set) var autoDevices: Set<String>
  /// The device car mode was closed on, so it stays closed until that device reconnects.
  private var closedOn: String?

  private init() {
    autoDevices = Set(UserDefaults.standard.stringArray(forKey: SirenSettings.carDevices) ?? [])
    deviceName = Self.currentDevice()
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.checkRoute() }
    }
  }

  func open() {
    let player = PlayerManager.shared
    guard player.current != nil else { return }
    guard player.isShowingFullPlayer else {
      isPresented = true
      return
    }
    player.hideFullPlayer()
    // The player sheet has to finish closing before another cover can present.
    Task {
      try? await Task.sleep(for: .milliseconds(500))
      if PlayerManager.shared.current != nil { isPresented = true }
    }
  }

  func close() {
    isPresented = false
    closedOn = deviceName
  }

  func opensAutomatically(for name: String) -> Binding<Bool> {
    Binding(
      get: { self.autoDevices.contains(name) },
      set: { isOn in
        if isOn { self.autoDevices.insert(name) } else { self.autoDevices.remove(name) }
        UserDefaults.standard.set(self.autoDevices.sorted(), forKey: SirenSettings.carDevices)
      }
    )
  }

  /// Opens car mode when a chosen device is the output and a book is loaded. Runs on route
  /// changes, when the app comes forward and when a book loads.
  func checkRoute() {
    let name = Self.currentDevice()
    deviceName = name
    if name != closedOn { closedOn = nil }
    guard let name, autoDevices.contains(name), closedOn == nil, !isPresented else { return }
    open()
  }

  private static func currentDevice() -> String? {
    let carPorts: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio]
    return AVAudioSession.sharedInstance().currentRoute.outputs
      .first { carPorts.contains($0.portType) }?
      .portName
  }
}

/// Car mode bound to the book in the player.
struct SirenLiveCarMode: View {
  @Bindable var model: BookPlayer.Model

  @State private var carMode = SirenCarMode.shared
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    SirenCarModeView(
      book: SirenBook(player: model),
      playback: playback,
      deviceName: carMode.deviceName,
      opensAutomatically: carMode.deviceName.map(carMode.opensAutomatically(for:)),
      onClose: carMode.close
    )
    .onAppear {
      model.onAppear()
      UIApplication.shared.isIdleTimerDisabled = true
    }
    .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
  }

  private var playback: SirenPlayback {
    var playback = SirenPlayback(player: model, preferences: preferences)
    playback.onSpeed = nextSpeed
    return playback
  }

  /// The speed tile steps through the speed presets and wraps to the slowest.
  private func nextSpeed() {
    let presets = model.speed.presets.sorted()
    guard let slowest = presets.first else { return }
    let next = presets.first { $0 > model.speed.value + 0.01 } ?? slowest
    model.speed.onValueChanged(next)
  }
}
