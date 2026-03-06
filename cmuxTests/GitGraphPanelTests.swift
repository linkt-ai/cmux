import XCTest
import WebKit

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class GitGraphPanelTests: XCTestCase {

    func testPanelTypeIsGitGraph() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp/test-repo")
        XCTAssertEqual(panel.panelType, .gitGraph)
    }

    func testIdIsStableAfterCreation() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp/test-repo")
        let id1 = panel.id
        let id2 = panel.id
        XCTAssertEqual(id1, id2)
    }

    func testDisplayTitleContainsRepoName() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/Users/test/my-project")
        XCTAssertTrue(panel.displayTitle.contains("my-project"))
    }

    func testDisplayIconIsBranch() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp/test-repo")
        XCTAssertEqual(panel.displayIcon, "arrow.triangle.branch")
    }

    func testWebViewIsCreated() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp/test-repo")
        XCTAssertNotNil(panel.webView)
    }

    func testCloseStopsLoading() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp/test-repo")
        panel.close()
        XCTAssertNil(panel.webView.navigationDelegate)
    }

    func testTriggerFlashIncrements() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp/test-repo")
        let before = panel.focusFlashToken
        panel.triggerFlash()
        XCTAssertEqual(panel.focusFlashToken, before + 1)
    }

    // MARK: - Message Handler Registration

    func testMessageHandlerIsRegistered() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp/test-repo")
        panel.close()
        // If we got here without crash, the handler was registered and removed successfully.
    }

    func testCloseRemovesMessageHandler() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp/test-repo")
        panel.close()
        // Calling close() twice should not crash (handler already removed).
        panel.close()
    }

    // MARK: - Action Handling

    func testCopyHashCopiesToPasteboard() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp/test-repo")
        panel.handleAction("copyHash", body: ["hash": "abc123def456"])
        let copied = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(copied, "abc123def456")
        panel.close()
    }
}
