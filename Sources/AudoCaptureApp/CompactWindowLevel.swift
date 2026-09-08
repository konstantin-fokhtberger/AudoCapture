import SwiftUI
import AppKit

/// Only window stacking crosses into AppKit; appearance state stays in SwiftUI.
struct CompactWindowLevel: NSViewRepresentable {
    let isCompact: Bool
    func makeNSView(context: Context) -> LevelView { LevelView() }
    func updateNSView(_ view: LevelView, context: Context) {
        view.isCompact = isCompact
        view.apply()
    }

    final class LevelView: NSView {
        var isCompact = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }
        func apply() {
            guard let window else { return }
            window.level = isCompact ? .floating : .normal
            window.hidesOnDeactivate = false
            if isCompact {
                window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            } else {
                window.collectionBehavior.remove([.canJoinAllSpaces, .fullScreenAuxiliary])
            }
        }
    }
}
