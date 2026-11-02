import XCTest
import AppKit
@testable import SonyCompanion

final class StatusMenuTests: XCTestCase {
    func testPopoverOpensImmediatelyBelowItsStatusButton() throws {
        XCTAssertTrue(Thread.isMainThread)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        // Do not start the controller: this checks the real native panel without
        // opening Bluetooth, sending headphone commands, or requiring AX access.
        let menu = StatusMenu(controller: HeadphoneController())
        defer { menu.close() }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        let button = try XCTUnwrap(menu.item.button)
        let buttonWindow = try XCTUnwrap(button.window)
        menu.toggle()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))

        XCTAssertTrue(menu.popover.isShown)
        let panel = try XCTUnwrap(menu.popover.contentViewController?.view.window)
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        // The native arrow sits between the icon and panel body. A large empty
        // gap, as in the reported screenshot, fails this check.
        XCTAssertLessThanOrEqual(abs(panel.frame.maxY - anchor.minY), 24)
        XCTAssertLessThan(panel.frame.minX, anchor.maxX)
        XCTAssertGreaterThan(panel.frame.maxX, anchor.minX)
        if let screen = buttonWindow.screen {
            XCTAssertLessThanOrEqual(panel.frame.height, screen.visibleFrame.height)
        }
    }
}
