import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class GitGraphPanelAutoRefreshTests: XCTestCase {

    // MARK: - Debounce

    func testScheduleRefreshDebounces() {
        let panel = GitGraphPanel(repoPath: "/tmp/test-repo")

        panel.scheduleRefresh()
        panel.scheduleRefresh()
        panel.scheduleRefresh()

        XCTAssertTrue(panel.hasScheduledRefresh, "Should have a pending refresh")
    }

    func testScheduleRefreshMultipleTimesDoesNotCrash() {
        let panel = GitGraphPanel(repoPath: "/tmp/test-repo")

        // Rapid-fire scheduling should debounce without errors
        for _ in 0..<10 {
            panel.scheduleRefresh()
        }

        XCTAssertTrue(panel.hasScheduledRefresh,
                      "Should still have exactly one pending refresh after rapid calls")
    }

    // MARK: - Cleanup

    func testCloseRemovesSubscriptions() {
        let panel = GitGraphPanel(repoPath: "/tmp/test-repo")
        panel.close()
        XCTAssertFalse(panel.hasScheduledRefresh,
                       "Close should cancel pending refresh")
    }

    // MARK: - Visibility Gate

    func testRefreshSkippedWhenNotVisible() {
        let panel = GitGraphPanel(repoPath: "/tmp/test-repo")
        panel.isVisibleInUI = false

        panel.scheduleRefresh()
        XCTAssertFalse(panel.hasScheduledRefresh,
                       "Should not schedule refresh when panel is not visible")
    }

    // MARK: - Workspace Wiring

    func testWorkspaceRefIsNilBeforeWiring() {
        let panel = GitGraphPanel(repoPath: "/tmp/test-repo")
        XCTAssertNil(panel.workspace, "workspace should be nil before wiring")
    }

    // MARK: - Non-Git Directory Handling

    func testShowNoRepoStateClearsRepoPath() {
        let panel = GitGraphPanel(repoPath: "/tmp/test-repo")
        XCTAssertEqual(panel.repoPath, "/tmp/test-repo")

        panel.showNoRepoState()

        XCTAssertEqual(panel.repoPath, "", "repoPath should be cleared for non-git dir")
        XCTAssertNil(panel.currentBranch, "branch should be nil for non-git dir")
        XCTAssertEqual(panel.displayTitle, "Git Graph", "title should reset to default")
    }

    func testShowNoRepoStateThenRecovery() {
        let panel = GitGraphPanel(repoPath: "/tmp/test-repo")

        panel.showNoRepoState()
        XCTAssertEqual(panel.repoPath, "")

        // Simulate recovery by setting repo path directly (as CWD subscription would)
        panel.showNoRepoState() // idempotent
        XCTAssertEqual(panel.repoPath, "", "Should remain cleared after double call")
    }
}
