//
//  ShakeDetector.swift
//  LanguageFlow
//
//  Debug-only shake detector to toggle environments.
//

#if DEBUG
import SwiftUI

struct ShakeDetector: UIViewRepresentable {
    let onShake: () -> Void

    func makeUIView(context: Context) -> ShakeView {
        let view = ShakeView()
        view.onShake = onShake
        return view
    }

    func updateUIView(_ uiView: ShakeView, context: Context) {}

    final class ShakeView: UIView {
        var onShake: (() -> Void)?

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            becomeFirstResponder()
        }

        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            guard motion == .motionShake else { return }
            onShake?()
        }
    }
}
#endif
