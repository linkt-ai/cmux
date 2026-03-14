import XCTest
import WebKit

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class GitGraphKeyboardNavJSTests: XCTestCase {

    private var webView: WKWebView!

    override func setUp() async throws {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // Inject test mode flag so test hooks are registered
        let testModeScript = WKUserScript(
            source: "window.__CMUX_TEST_MODE = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(testModeScript)

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)

        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // cmuxTests/
            .deletingLastPathComponent()  // project root
        let gitGraphDir = projectRoot.appendingPathComponent("Resources/git-graph")
        let indexURL = gitGraphDir.appendingPathComponent("index.html")
        webView.loadFileURL(indexURL, allowingReadAccessTo: gitGraphDir)

        try await Task.sleep(nanoseconds: 2_000_000_000)
    }

    private func eval(_ js: String) async throws -> Any? {
        return try await webView.evaluateJavaScript(js)
    }

    /// Push a graph with N simple linear commits (no merges).
    private func pushLinearGraph(count: Int = 5) async throws {
        var commits: [String] = []
        for i in 0..<count {
            let hash = "hash\(i)full"
            let abbrev = "hash\(i)"
            let parent = i > 0 ? "\"hash\(i-1)full\"" : ""
            let parents = parent.isEmpty ? "[]" : "[\(parent)]"
            commits.append("""
            {"hash":"\(hash)","abbreviatedHash":"\(abbrev)","parents":\(parents),"authorName":"Author","authorEmail":"a@a.com","authorDate":"2026-03-01T00:00:00Z","message":"Commit \(i)","fullMessage":"Commit \(i)"}
            """)
        }
        let json = """
        {"commits":[\(commits.joined(separator: ","))],"refs":[],"headHash":"hash0full","currentBranch":"main","isDirty":false,"repoName":"test","repoPath":"/tmp/test"}
        """
        _ = try await eval("window.updateGraph(JSON.stringify(\(json)))")
    }

    /// Push a graph with a merge commit: commit0 is a merge of commit1 (first parent) and commit2 (second parent).
    private func pushMergeGraph() async throws {
        let json = """
        {"commits":[
          {"hash":"merge0","abbreviatedHash":"m0","parents":["parent1","parent2"],"authorName":"A","authorEmail":"a@a.com","authorDate":"2026-03-01T00:00:00Z","message":"Merge","fullMessage":"Merge"},
          {"hash":"parent1","abbreviatedHash":"p1","parents":[],"authorName":"A","authorEmail":"a@a.com","authorDate":"2026-03-01T00:00:00Z","message":"Parent 1","fullMessage":"Parent 1"},
          {"hash":"parent2","abbreviatedHash":"p2","parents":[],"authorName":"A","authorEmail":"a@a.com","authorDate":"2026-03-01T00:00:00Z","message":"Parent 2","fullMessage":"Parent 2"}
        ],"refs":[],"headHash":"merge0","currentBranch":"main","isDirty":false,"repoName":"test","repoPath":"/tmp/test"}
        """
        _ = try await eval("window.updateGraph(JSON.stringify(\(json)))")
    }

    private func pressKey(_ key: String, code: String? = nil) async throws {
        let codeStr = code ?? key
        _ = try await eval("""
            document.dispatchEvent(new KeyboardEvent('keydown', {key: '\(key)', code: '\(codeStr)', bubbles: true}));
            true
        """)
    }

    private func getFocusedIndex() async throws -> Int {
        let result = try await eval("window.__test_getFocusedIndex ? window.__test_getFocusedIndex() : -1")
        return (result as? Int) ?? -1
    }

    private func getFocusedHash() async throws -> String? {
        return try await eval("window.__test_getFocusedHash ? window.__test_getFocusedHash() : null") as? String
    }

    // MARK: - Initial State

    func testInitialFocusIndexIsNegativeOne() async throws {
        try await pushLinearGraph()
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, -1, "No focus until keyboard interaction")
    }

    // MARK: - ArrowDown / j Navigation

    func testArrowDownSetsFocusToFirstCommit() async throws {
        try await pushLinearGraph()
        try await pressKey("ArrowDown")
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, 0)
    }

    func testArrowDownAdvancesFocus() async throws {
        try await pushLinearGraph()
        try await pressKey("ArrowDown")
        try await pressKey("ArrowDown")
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, 1)
    }

    func testJKeyAdvancesFocus() async throws {
        try await pushLinearGraph()
        try await pressKey("j")
        try await pressKey("j")
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, 1)
    }

    func testArrowDownClampsAtEnd() async throws {
        try await pushLinearGraph(count: 3)
        for _ in 0..<10 {
            try await pressKey("ArrowDown")
        }
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, 2, "Should clamp at last commit")
    }

    // MARK: - ArrowUp / k Navigation

    func testArrowUpFromSecondGoesToFirst() async throws {
        try await pushLinearGraph()
        try await pressKey("ArrowDown")
        try await pressKey("ArrowDown")
        try await pressKey("ArrowUp")
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, 0)
    }

    func testKKeyMovesUp() async throws {
        try await pushLinearGraph()
        try await pressKey("ArrowDown")
        try await pressKey("ArrowDown")
        try await pressKey("k")
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, 0)
    }

    func testArrowUpClampsAtStart() async throws {
        try await pushLinearGraph()
        try await pressKey("ArrowDown") // focus index 0
        try await pressKey("ArrowUp")   // should stay at 0
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, 0, "Should clamp at first commit")
    }

    // MARK: - Escape

    func testEscapeClearsFocus() async throws {
        try await pushLinearGraph()
        try await pressKey("ArrowDown")
        try await pressKey("Escape")
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, -1)
    }

    // MARK: - Focus CSS Class

    func testFocusedRowGetsFocusedClass() async throws {
        try await pushLinearGraph()
        try await pressKey("ArrowDown")
        let hasFocused = try await eval(
            "document.querySelector('.commit-row.focused') !== null"
        ) as? Bool
        XCTAssertEqual(hasFocused, true)
    }

    func testOnlyOneRowHasFocusedClass() async throws {
        try await pushLinearGraph()
        try await pressKey("ArrowDown")
        try await pressKey("ArrowDown")
        let count = try await eval(
            "document.querySelectorAll('.commit-row.focused').length"
        ) as? Int
        XCTAssertEqual(count, 1)
    }

    func testEscapeRemovesFocusedClass() async throws {
        try await pushLinearGraph()
        try await pressKey("ArrowDown")
        try await pressKey("Escape")
        let count = try await eval(
            "document.querySelectorAll('.commit-row.focused').length"
        ) as? Int
        XCTAssertEqual(count, 0)
    }

    // MARK: - Merge Parent Following

    func testArrowLeftAtMergeFollowsFirstParent() async throws {
        try await pushMergeGraph()
        try await pressKey("ArrowDown") // focus merge commit (index 0)
        try await pressKey("ArrowLeft")
        let hash = try await getFocusedHash()
        XCTAssertEqual(hash, "parent1", "Left should follow first parent")
    }

    func testArrowRightAtMergeFollowsSecondParent() async throws {
        try await pushMergeGraph()
        try await pressKey("ArrowDown") // focus merge commit (index 0)
        try await pressKey("ArrowRight")
        let hash = try await getFocusedHash()
        XCTAssertEqual(hash, "parent2", "Right should follow second parent")
    }

    func testArrowLeftAtNonMergeIsNoop() async throws {
        try await pushLinearGraph(count: 3)
        try await pressKey("ArrowDown") // index 0
        try await pressKey("ArrowDown") // index 1
        try await pressKey("ArrowLeft") // non-merge, should stay
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, 1, "Left on non-merge commit should be noop")
    }

    func testArrowRightAtNonMergeIsNoop() async throws {
        try await pushLinearGraph(count: 3)
        try await pressKey("ArrowDown") // index 0
        try await pressKey("ArrowDown") // index 1
        try await pressKey("ArrowRight") // non-merge, should stay
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, 1, "Right on non-merge commit should be noop")
    }

    // MARK: - Enter Opens Drawer

    func testEnterPostsCommitSelectedMessage() async throws {
        try await pushLinearGraph()
        // Intercept postMessage
        _ = try await eval("""
            window.__lastPostedAction = null;
            window.__lastPostedHash = null;
            var origHandler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.gitGraph;
            // In test env there's no webkit handler, so we patch postMessage via the internal function
            // We'll check via a test hook instead
            window.__test_onCommitSelected = function(hash) {
                window.__lastPostedHash = hash;
            };
            true
        """)
        try await pressKey("ArrowDown") // focus index 0
        try await pressKey("Enter")

        let hash = try await eval("window.__lastPostedHash") as? String
        XCTAssertEqual(hash, "hash0full")
    }

    // MARK: - setFocusOnGraph

    func testSetFocusOnGraphInitializesFocus() async throws {
        try await pushLinearGraph()
        _ = try await eval("window.setFocusOnGraph()")
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, 0, "setFocusOnGraph should set focus to first commit")
    }

    func testSetFocusOnGraphPreservesExistingFocus() async throws {
        try await pushLinearGraph()
        try await pressKey("ArrowDown") // index 0
        try await pressKey("ArrowDown") // index 1
        _ = try await eval("window.setFocusOnGraph()")
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, 1, "setFocusOnGraph should not reset existing focus")
    }

    // MARK: - Focus Persistence Across Refresh

    func testFocusPreservedAcrossGraphRefresh() async throws {
        try await pushLinearGraph(count: 5)
        try await pressKey("ArrowDown") // index 0
        try await pressKey("ArrowDown") // index 1
        let hashBefore = try await getFocusedHash()

        // Refresh with same data
        try await pushLinearGraph(count: 5)
        let hashAfter = try await getFocusedHash()
        XCTAssertEqual(hashBefore, hashAfter, "Focus should persist on same hash after refresh")
    }

    func testFocusFallsBackToFirstOnRefreshWithNewData() async throws {
        try await pushLinearGraph(count: 3)
        try await pressKey("ArrowDown") // index 0
        try await pressKey("ArrowDown") // index 1 = hash1full

        // Refresh with completely different commits
        let json = """
        {"commits":[
          {"hash":"new0","abbreviatedHash":"n0","parents":[],"authorName":"A","authorEmail":"a@a.com","authorDate":"2026-03-01T00:00:00Z","message":"New","fullMessage":"New"}
        ],"refs":[],"headHash":"new0","currentBranch":"main","isDirty":false,"repoName":"test","repoPath":"/tmp/test"}
        """
        _ = try await eval("window.updateGraph(JSON.stringify(\(json)))")
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, 0, "Should fall back to first commit when focused hash gone")
    }

    // MARK: - Empty Graph

    func testArrowDownOnEmptyGraphIsNoop() async throws {
        let json = """
        {"commits":[],"refs":[],"headHash":"","currentBranch":"main","isDirty":false,"repoName":"test","repoPath":"/tmp/test"}
        """
        _ = try await eval("window.updateGraph(JSON.stringify(\(json)))")
        try await pressKey("ArrowDown")
        let index = try await getFocusedIndex()
        XCTAssertEqual(index, -1)
    }
}
