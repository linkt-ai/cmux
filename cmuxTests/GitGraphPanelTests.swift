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
}
