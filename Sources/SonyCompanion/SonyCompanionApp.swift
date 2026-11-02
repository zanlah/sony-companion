import SwiftUI
import AppKit
import Combine

@main
struct SonyCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = HeadphoneController()
    private var menu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = StatusMenu(controller: controller)
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menu?.close()
        controller.stop()
    }
}

/// Anchor the panel to AppKit's status button in its own coordinate space.
/// NSPopover maintains that anchor as SwiftUI content changes its height.
final class StatusMenu: NSObject, NSPopoverDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let popover = NSPopover()
    private let controller: HeadphoneController
    private var batterySubscription: AnyCancellable?

    init(controller: HeadphoneController) {
        self.controller = controller
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Sony Companion")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(toggle)
            button.toolTip = "Sony Companion"
            button.setAccessibilityLabel("Sony Companion")
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        batterySubscription = controller.$state.map(\.battery).removeDuplicates().sink { [weak self] battery in
            self?.item.button?.title = battery.map { " \($0)%" } ?? ""
        }
    }

    deinit { NSStatusBar.system.removeStatusItem(item) }

    @objc func toggle() {
        guard !popover.isShown else { close(); return }
        guard let button = item.button else { return }
        let screen = button.window?.screen ?? NSScreen.main
        // Keep enough space for the popover arrow and screen edges, including
        // small displays and screens with a different menu bar/notch height.
        let availableHeight = max(1, (screen?.visibleFrame.height ?? 700) - 32)
        let hosting = NSHostingController(rootView: MenuPanel(controller: controller, maximumHeight: availableHeight))
        hosting.preferredContentSize = NSSize(width: 360, height: min(400, availableHeight))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.contentSize = hosting.preferredContentSize
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
    }

    func close() { popover.performClose(nil) }

    func popoverDidClose(_ notification: Notification) {
        item.button?.highlight(false)
        // Recreate the view for the screen containing the button next time.
        popover.contentViewController = nil
    }
}

/// Measure the full contents independently of the viewport. The popover uses
/// the natural height until it reaches the screen limit, then scrolls.
private struct MenuPanel: View {
    @ObservedObject var controller: HeadphoneController
    let maximumHeight: CGFloat
    @State private var contentHeight: CGFloat = 400

    var body: some View {
        ScrollView(.vertical) {
            CompanionView(controller: controller)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: PanelHeight.self, value: geometry.size.height)
                })
        }
        .frame(width: 360, height: min(contentHeight, maximumHeight))
        .onPreferenceChange(PanelHeight.self) { height in
            if height > 0, abs(contentHeight - height) > 0.5 { contentHeight = height }
        }
    }
}

private struct PanelHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
