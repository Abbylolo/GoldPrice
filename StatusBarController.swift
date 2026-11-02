import AppKit
import Combine
import SwiftUI
import GoldPriceCore

@MainActor
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store = AppStore()
    private var cancellable: AnyCancellable?
    private var previewWindow: NSWindow?

    override init() {
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.contentSize = NSSize(width: PanelLayout.width, height: PanelLayout.height)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: GoldPriceView(store: store))
        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateTitle() }
        }
        updateTitle()
        store.start()

        // An ordinary window gives local development and QA the exact same views
        // as the menu-bar popover without relying on a visible macOS menu bar.
        if CommandLine.arguments.contains("--preview") { showPreviewWindow() }
    }

    private func updateTitle() {
        let channel = store.preferences.displayChannel
        if let quote = store.quote(channel) {
            item.button?.title = "✦ \(channel.shortTitle) \(String(format: "%.2f", quote.price.doubleValue))"
            let freshness = quote.isFresh(at: Date()) ? "最新报价" : "最近报价"
            item.button?.toolTip = "\(channel.title) · \(channel.unit)\n\(freshness)：\(quote.timestamp.formatted())"
            item.button?.appearsDisabled = !quote.isFresh(at: Date())
        } else {
            item.button?.title = "✦ \(channel.shortTitle) —"
            item.button?.toolTip = "等待\(channel.title)报价"
        }
    }

    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showPreviewWindow() {
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: PanelLayout.width, height: PanelLayout.height), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "GoldPrice · 定制版预览"
        window.contentView = NSHostingView(rootView: GoldPriceView(store: store))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = window
    }
}
