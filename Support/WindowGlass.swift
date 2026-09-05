import AppKit
import SwiftUI

struct WindowGlassConfigurator: NSViewRepresentable {
    final class Coordinator {
        weak var configuredWindow: NSWindow?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window, context.coordinator.configuredWindow !== window else {
            return
        }
        configure(window: window)
        context.coordinator.configuredWindow = window
    }

    private func configure(window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified
        window.backgroundColor = .clear
        window.isOpaque = false
    }
}
