import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class GitGraphShortcutTests: XCTestCase {

    // MARK: - Action enum

    func testOpenGitGraphActionExists() {
        let action = KeyboardShortcutSettings.Action.openGitGraph
        XCTAssertEqual(action.rawValue, "openGitGraph")
    }

    func testOpenGitGraphLabel() {
        let action = KeyboardShortcutSettings.Action.openGitGraph
        XCTAssertFalse(action.label.isEmpty, "Label should not be empty")
    }

    func testOpenGitGraphDefaultsKey() {
        let action = KeyboardShortcutSettings.Action.openGitGraph
        XCTAssertEqual(action.defaultsKey, "shortcut.openGitGraph")
    }

    func testOpenGitGraphDefaultShortcut() {
        let shortcut = KeyboardShortcutSettings.Action.openGitGraph.defaultShortcut
        XCTAssertEqual(shortcut.key, "g")
        XCTAssertTrue(shortcut.command)
        XCTAssertTrue(shortcut.shift)
        XCTAssertFalse(shortcut.option)
        XCTAssertFalse(shortcut.control)
    }

    func testOpenGitGraphDisplayString() {
        let shortcut = KeyboardShortcutSettings.Action.openGitGraph.defaultShortcut
        XCTAssertEqual(shortcut.displayString, "⇧⌘G")
    }

    func testOpenGitGraphConvenienceGetter() {
        let shortcut = KeyboardShortcutSettings.openGitGraphShortcut()
        // Should return default when no custom value is stored
        XCTAssertEqual(shortcut.key, "g")
        XCTAssertTrue(shortcut.command)
        XCTAssertTrue(shortcut.shift)
    }

    func testOpenGitGraphIncludedInAllCases() {
        XCTAssertTrue(
            KeyboardShortcutSettings.Action.allCases.contains(.openGitGraph),
            "openGitGraph should be in allCases"
        )
    }

    // MARK: - Context key

    func testPanelIsGitGraphContextKeyExists() {
        XCTAssertEqual(CommandPaletteContextKeys.panelIsGitGraph, "panel.isGitGraph")
    }
}

@MainActor
final class GitGraphShortcutRoutingTests: XCTestCase {

    func testOpenGitGraphMethodExists() {
        guard let appDelegate = AppDelegate.shared else {
            XCTFail("Expected AppDelegate.shared")
            return
        }
        // Verify openGitGraph() exists and is callable
        // It may return nil when no workspace is focused, but should not crash
        let result = appDelegate.openGitGraph()
        // No workspace → nil is expected
        XCTAssertNil(result)
    }
}
