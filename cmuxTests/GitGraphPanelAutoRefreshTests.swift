import XCTest
import Combine

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class GitGraphPanelAutoRefreshTests: XCTestCase {

    // MARK: - Debounce

    func testScheduleRefreshDebounces() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp/test-repo")

        panel.scheduleRefresh()
        panel.scheduleRefresh()
        panel.scheduleRefresh()

        XCTAssertTrue(panel.hasScheduledRefresh, "Should have a pending refresh")
    }

    func testScheduleRefreshCancelsPrevious() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp/test-repo")

        panel.scheduleRefresh()
        let firstItem = panel.pendingRefreshWorkItem
        panel.scheduleRefresh()
        let secondItem = panel.pendingRefreshWorkItem

        XCTAssertTrue(firstItem !== secondItem || firstItem == nil,
                      "New schedule should replace the previous work item")
    }

    // MARK: - Repo Resolution (disabled — resolveRepoRoot moved to GitGraphDataProvider)

    // MARK: - Repo Change Detection (disabled — updateRepoPathIfNeeded API changed)

    // MARK: - Cleanup

    func testCloseRemovesSubscriptions() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp/test-repo")
        panel.close()
        XCTAssertFalse(panel.hasScheduledRefresh,
                       "Close should cancel pending refresh")
    }

    // MARK: - Visibility Gate

    func testRefreshSkippedWhenNotVisible() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp/test-repo")
        panel.isVisibleInUI = false

        panel.scheduleRefresh()
        XCTAssertFalse(panel.hasScheduledRefresh,
                       "Should not schedule refresh when panel is not visible")
    }

    // MARK: - Workspace Wiring

    func testWorkspaceRefIsNilBeforeWiring() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp/test-repo")
        XCTAssertNil(panel.workspace, "workspace should be nil before wiring")
    }
}
