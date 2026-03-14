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
        let panel = GitGraphPanel(repoPath: "/tmp/test-repo")
        XCTAssertEqual(panel.panelType, .gitGraph)
    }

    func testIdIsStableAfterCreation() {
        let panel = GitGraphPanel(repoPath: "/tmp/test-repo")
        let id1 = panel.id
        let id2 = panel.id
        XCTAssertEqual(id1, id2)
    }

    func testDisplayTitleContainsRepoName() {
        let panel = GitGraphPanel(repoPath: "/Users/test/my-project")
        XCTAssertTrue(panel.displayTitle.contains("my-project"))
    }

    func testDisplayIconIsBranch() {
        let panel = GitGraphPanel(repoPath: "/tmp/test-repo")
        XCTAssertEqual(panel.displayIcon, "arrow.triangle.branch")
    }

    func testWebViewIsCreated() {
        let panel = GitGraphPanel(repoPath: "/tmp/test-repo")
        XCTAssertNotNil(panel.webView)
    }

    func testTriggerFlashAdvancesToken() {
        let panel = GitGraphPanel(repoPath: "/tmp/test-repo")
        let before = panel.focusFlashToken
        panel.triggerFlash()
        XCTAssertGreaterThan(panel.focusFlashToken, before,
                             "triggerFlash should advance the token so the view re-animates")
    }

    // MARK: - Message Handler Lifecycle

    func testCloseRemovesNavigationDelegate() {
        let panel = GitGraphPanel(repoPath: "/tmp/test-repo")
        XCTAssertNotNil(panel.webView.navigationDelegate,
                        "Navigation delegate should be set after init")
        panel.close()
        XCTAssertNil(panel.webView.navigationDelegate,
                     "close() should remove navigation delegate")
    }

    func testDoubleCloseDoesNotCrash() {
        let panel = GitGraphPanel(repoPath: "/tmp/test-repo")
        panel.close()
        panel.close()
        XCTAssertNil(panel.webView.navigationDelegate,
                     "Navigation delegate should remain nil after double close")
    }

}
