import SwiftUI
import AppKit

@main
struct SonyCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra {
            CompanionView(controller: delegate.controller)
        } label: {
            MenuLabel(controller: delegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = HeadphoneController()
    func applicationDidFinishLaunching(_ notification: Notification) { controller.start() }
    func applicationWillTerminate(_ notification: Notification) { controller.stop() }
}

private struct MenuLabel: View {
    @ObservedObject var controller: HeadphoneController
    var body: some View {
        Image(systemName: "headphones")
        if let battery = controller.state.battery { Text("\(battery)%") }
    }
}
