import Combine
import SwiftUI

extension View {
  func miniPlayerSheets(isEnabled: Bool) -> some View {
    modifier(MiniPlayerSheetsModifier(isEnabled: isEnabled))
  }
}

struct MiniPlayerSheetsModifier: ViewModifier {
  let isEnabled: Bool

  @ObservedObject private var playerManager = PlayerManager.shared

  func body(content: Content) -> some View {
    content
      .adaptivePresentation(isPresented: binding(\.isQueuePresented)) {
        PlayerQueueView(model: PlayerQueueViewModel())
          .displayScaled()
      }
      .adaptiveSheet(isPresented: binding(\.speed.isPresented)) {
        if let currentPlayer = playerManager.current {
          FloatPickerSheet(
            model: Binding(
              get: { currentPlayer.speed },
              set: { currentPlayer.speed = $0 }
            )
          )
        }
      }
      .adaptiveSheet(isPresented: binding(\.timer.isPresented)) {
        if let currentPlayer = playerManager.current {
          TimerPickerSheet(
            model: Binding(
              get: { currentPlayer.timer },
              set: { currentPlayer.timer = $0 }
            )
          )
        }
      }
  }

  private func binding(_ keyPath: ReferenceWritableKeyPath<BookPlayer.Model, Bool>) -> Binding<Bool> {
    Binding(
      get: { isEnabled && playerManager.current?[keyPath: keyPath] == true },
      set: { playerManager.current?[keyPath: keyPath] = $0 }
    )
  }
}
