import SwiftUI
import AppKit

/// Window chrome and stacking live here; appearance state stays in SwiftUI.
struct CompactWindowLevel: NSViewRepresentable {
    let isCompact: Bool
    let expand: () -> Void
    func makeNSView(context: Context) -> LevelView { LevelView() }
    func updateNSView(_ view: LevelView, context: Context) {
        view.expand = expand
        view.isCompact = isCompact
        view.apply()
    }

    final class LevelView: NSView {
        var isCompact = false
        var expand: (() -> Void)?
        private let accessory = NSTitlebarAccessoryViewController()
        private weak var attachedWindow: NSWindow?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            let button = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Развернуть окно")!, target: self, action: #selector(expandWindow))
            button.isBordered = false
            button.frame = NSRect(x: 0, y: 0, width: 28, height: 22)
            button.toolTip = "Развернуть настройки (⌘⇧M)"
            accessory.view = button
            accessory.layoutAttribute = .right
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        @objc private func expandWindow() { expand?() }

        private func detachAccessory() {
            guard let attachedWindow else { return }
            if let index = attachedWindow.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessory }) {
                attachedWindow.removeTitlebarAccessoryViewController(at: index)
            }
            attachedWindow.titleVisibility = .visible
            self.attachedWindow = nil
        }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow !== window { detachAccessory() }
            super.viewWillMove(toWindow: newWindow)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }
        func apply() {
            guard let window else { return }
            if isCompact {
                if attachedWindow !== window {
                    detachAccessory()
                    window.addTitlebarAccessoryViewController(accessory)
                    attachedWindow = window
                }
                window.titleVisibility = .hidden
            } else {
                detachAccessory()
            }
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
