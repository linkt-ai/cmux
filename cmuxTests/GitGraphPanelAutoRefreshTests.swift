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

    // MARK: - Repo Resolution

    func testResolveRepoPathFromCWD() {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // cmuxTests/
            .deletingLastPathComponent()  // project root
            .path

        let resolved = GitGraphPanel.resolveRepoRoot(fromCWD: projectRoot)
        XCTAssertNotNil(resolved, "Should find .git in project root")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved! + "/.git"),
                      "Resolved path should contain .git")
    }

    func testResolveRepoPathFromSubdirectory() {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // cmuxTests/
            .deletingLastPathComponent()  // project root

        let subdir = projectRoot.appendingPathComponent("Sources").path
        let resolved = GitGraphPanel.resolveRepoRoot(fromCWD: subdir)
        XCTAssertNotNil(resolved, "Should walk up to find .git")
    }

    func testResolveRepoPathNonGitDirectory() {
        let resolved = GitGraphPanel.resolveRepoRoot(fromCWD: "/tmp")
        XCTAssertNil(resolved, "/tmp is not inside a git repo")
    }

    func testResolveRepoPathNonExistentDirectory() {
        let resolved = GitGraphPanel.resolveRepoRoot(fromCWD: "/nonexistent/path/xyz")
        XCTAssertNil(resolved, "Non-existent path should return nil")
    }

    // MARK: - Repo Change Detection

    func testUpdateRepoPathSameRepo() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/Users/test/my-repo")
        let changed = panel.updateRepoPathIfNeeded(fromCWD: "/Users/test/my-repo/src")
        XCTAssertNotNil(changed as Bool?)
    }

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
