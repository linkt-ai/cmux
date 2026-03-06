import XCTest
import WebKit

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class GitGraphDrawerJSTests: XCTestCase {

    private var webView: WKWebView!

    override func setUp() async throws {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)

        let resourceURL = Bundle(for: type(of: self)).resourceURL
            ?? Bundle.main.resourceURL!
        let gitGraphDir = resourceURL.appendingPathComponent("git-graph")
        let indexURL = gitGraphDir.appendingPathComponent("index.html")
        webView.loadFileURL(indexURL, allowingReadAccessTo: gitGraphDir)

        // Wait for page load
        try await Task.sleep(nanoseconds: 2_000_000_000)
    }

    // Helper: push graph data so commitsByHash is populated
    private func pushGraphData(hash: String = "abc123full",
                               abbreviatedHash: String = "abc123",
                               authorName: String = "Test Author",
                               authorEmail: String = "test@test.com",
                               message: String = "Test commit",
                               fullMessage: String = "Test commit\n\nFull body here") async throws {
        let graphData = """
        {"commits":[{"hash":"\(hash)","abbreviatedHash":"\(abbreviatedHash)","parents":[],"authorName":"\(authorName)","authorEmail":"\(authorEmail)","authorDate":"2026-03-01T00:00:00Z","message":"\(message)","fullMessage":"\(fullMessage)"}],"refs":[],"headHash":"\(hash)","currentBranch":"main","isDirty":false,"repoName":"test","repoPath":"/tmp/test"}
        """
        _ = try await webView.callAsyncJavaScript(
            "window.updateGraph(data)",
            arguments: ["data": graphData],
            in: nil, in: .page
        )
    }

    // Helper: push commit detail data
    private func pushDetailData(hash: String = "abc123full",
                                files: String = """
                                [{"path":"foo.swift","additions":5,"deletions":2}]
                                """,
                                totalFiles: Int = 1,
                                totalAdditions: Int = 5,
                                totalDeletions: Int = 2) async throws {
        let json = """
        {"hash":"\(hash)","files":\(files),"totalFiles":\(totalFiles),"totalAdditions":\(totalAdditions),"totalDeletions":\(totalDeletions)}
        """
        _ = try await webView.callAsyncJavaScript(
            "window.showCommitDetail(data)",
            arguments: ["data": json],
            in: nil, in: .page
        )
    }

    // --- Drawer lifecycle ---

    func testShowCommitDetailCreatesDrawer() async throws {
        try await pushGraphData()
        try await pushDetailData()

        let exists = try await webView.callAsyncJavaScript(
            "return document.querySelector('.commit-detail-drawer') !== null",
            arguments: [:], in: nil, in: .page
        ) as? Bool
        XCTAssertEqual(exists, true)
    }

    func testDrawerHasOpenClass() async throws {
        try await pushGraphData()
        try await pushDetailData()

        let isOpen = try await webView.callAsyncJavaScript(
            "return document.querySelector('.commit-detail-drawer')?.classList.contains('open') ?? false",
            arguments: [:], in: nil, in: .page
        ) as? Bool
        XCTAssertEqual(isOpen, true)
    }

    func testHideCommitDetailRemovesOpenClass() async throws {
        try await pushGraphData()
        try await pushDetailData()
        _ = try await webView.callAsyncJavaScript(
            "window.hideCommitDetail()", arguments: [:], in: nil, in: .page
        )
        try await Task.sleep(nanoseconds: 300_000_000)

        let isOpen = try await webView.callAsyncJavaScript(
            "var d = document.querySelector('.commit-detail-drawer'); return d ? d.classList.contains('open') : false",
            arguments: [:], in: nil, in: .page
        ) as? Bool
        XCTAssertEqual(isOpen, false)
    }

    // --- Content sections ---

    func testDrawerShowsAbbreviatedHashHeader() async throws {
        try await pushGraphData(abbreviatedHash: "abc123")
        try await pushDetailData()

        let text = try await webView.callAsyncJavaScript(
            "return document.querySelector('.detail-header-hash')?.textContent || ''",
            arguments: [:], in: nil, in: .page
        ) as? String
        XCTAssertTrue(text?.contains("abc123") == true)
    }

    func testDrawerShowsFullHash() async throws {
        try await pushGraphData(hash: "abc123fullhashvalue")
        try await pushDetailData(hash: "abc123fullhashvalue")

        let text = try await webView.callAsyncJavaScript(
            "return document.querySelector('.detail-full-hash')?.textContent || ''",
            arguments: [:], in: nil, in: .page
        ) as? String
        XCTAssertTrue(text?.contains("abc123fullhashvalue") == true)
    }

    func testDrawerShowsAuthor() async throws {
        try await pushGraphData(authorName: "Jane Doe", authorEmail: "jane@example.com")
        try await pushDetailData()

        let text = try await webView.callAsyncJavaScript(
            "return document.querySelector('.detail-author')?.textContent || ''",
            arguments: [:], in: nil, in: .page
        ) as? String
        XCTAssertTrue(text?.contains("Jane Doe") == true)
        XCTAssertTrue(text?.contains("jane@example.com") == true)
    }

    func testDrawerShowsCommitMessage() async throws {
        try await pushGraphData(message: "Fix the bug", fullMessage: "Fix the bug\\n\\nThis fixes issue #42.")
        try await pushDetailData()

        let text = try await webView.callAsyncJavaScript(
            "return document.querySelector('.detail-message')?.textContent || ''",
            arguments: [:], in: nil, in: .page
        ) as? String
        XCTAssertTrue(text?.contains("Fix the bug") == true)
    }

    // --- File stats ---

    func testDrawerShowsFileStats() async throws {
        try await pushGraphData()
        let files = """
        [{"path":"Sources/Foo.swift","additions":10,"deletions":3},{"path":"Tests/Bar.swift","additions":5,"deletions":0}]
        """
        try await pushDetailData(files: files, totalFiles: 2, totalAdditions: 15, totalDeletions: 3)

        let count = try await webView.callAsyncJavaScript(
            "return document.querySelectorAll('.detail-file-item').length",
            arguments: [:], in: nil, in: .page
        ) as? Int
        XCTAssertEqual(count, 2)
    }

    func testDrawerShowsFileSummary() async throws {
        try await pushGraphData()
        let files = """
        [{"path":"a.swift","additions":10,"deletions":3}]
        """
        try await pushDetailData(files: files, totalFiles: 1, totalAdditions: 10, totalDeletions: 3)

        let text = try await webView.callAsyncJavaScript(
            "return document.querySelector('.detail-files-summary')?.textContent || ''",
            arguments: [:], in: nil, in: .page
        ) as? String
        XCTAssertTrue(text?.contains("1") == true, "Should contain file count")
    }

    func testDrawerShowsNoChangesForEmptyFiles() async throws {
        try await pushGraphData()
        try await pushDetailData(files: "[]", totalFiles: 0, totalAdditions: 0, totalDeletions: 0)

        let text = try await webView.callAsyncJavaScript(
            "return document.querySelector('.detail-files-section')?.textContent || ''",
            arguments: [:], in: nil, in: .page
        ) as? String
        XCTAssertTrue(text?.contains("No file changes") == true)
    }

    // --- Graph container shift ---

    func testGraphContainerShiftsWhenDrawerOpens() async throws {
        try await pushGraphData()
        try await pushDetailData()

        let marginRight = try await webView.callAsyncJavaScript(
            "return document.getElementById('graph-container')?.style.marginRight || ''",
            arguments: [:], in: nil, in: .page
        ) as? String
        XCTAssertEqual(marginRight, "320px")
    }

    func testGraphContainerResetsWhenDrawerCloses() async throws {
        try await pushGraphData()
        try await pushDetailData()
        _ = try await webView.callAsyncJavaScript(
            "window.hideCommitDetail()", arguments: [:], in: nil, in: .page
        )
        try await Task.sleep(nanoseconds: 300_000_000)

        let marginRight = try await webView.callAsyncJavaScript(
            "return document.getElementById('graph-container')?.style.marginRight || ''",
            arguments: [:], in: nil, in: .page
        ) as? String
        XCTAssertTrue(marginRight == "" || marginRight == "0px")
    }

    // --- Clicking different commit updates drawer ---

    func testClickingDifferentCommitUpdatesDrawer() async throws {
        // Push graph with two commits
        let graphData = """
        {"commits":[{"hash":"hash1","abbreviatedHash":"h1","parents":[],"authorName":"A","authorEmail":"a@a.com","authorDate":"2026-03-01T00:00:00Z","message":"First","fullMessage":"First"},{"hash":"hash2","abbreviatedHash":"h2","parents":[],"authorName":"B","authorEmail":"b@b.com","authorDate":"2026-03-02T00:00:00Z","message":"Second","fullMessage":"Second"}],"refs":[],"headHash":"hash1","currentBranch":"main","isDirty":false,"repoName":"test","repoPath":"/tmp/test"}
        """
        _ = try await webView.callAsyncJavaScript(
            "window.updateGraph(data)", arguments: ["data": graphData], in: nil, in: .page
        )

        // Show detail for first commit
        try await pushDetailData(hash: "hash1")

        // Show detail for second commit (should update, not create second drawer)
        let json2 = """
        {"hash":"hash2","files":[],"totalFiles":0,"totalAdditions":0,"totalDeletions":0}
        """
        _ = try await webView.callAsyncJavaScript(
            "window.showCommitDetail(data)", arguments: ["data": json2], in: nil, in: .page
        )

        let drawerCount = try await webView.callAsyncJavaScript(
            "return document.querySelectorAll('.commit-detail-drawer').length",
            arguments: [:], in: nil, in: .page
        ) as? Int
        XCTAssertEqual(drawerCount, 1, "Should reuse drawer, not create multiple")
    }

    // --- Escape key dismisses ---

    func testEscapeKeyDismissesDrawer() async throws {
        try await pushGraphData()
        try await pushDetailData()

        _ = try await webView.callAsyncJavaScript("""
            var e = new KeyboardEvent('keydown', {key: 'Escape', bubbles: true});
            document.dispatchEvent(e);
            return true;
        """, arguments: [:], in: nil, in: .page)
        try await Task.sleep(nanoseconds: 300_000_000)

        let isOpen = try await webView.callAsyncJavaScript(
            "var d = document.querySelector('.commit-detail-drawer'); return d ? d.classList.contains('open') : false",
            arguments: [:], in: nil, in: .page
        ) as? Bool
        XCTAssertEqual(isOpen, false)
    }

    // --- updateGraph closes drawer ---

    func testUpdateGraphClosesDrawer() async throws {
        try await pushGraphData()
        try await pushDetailData()

        // Call updateGraph again (simulates refresh)
        try await pushGraphData()
        try await Task.sleep(nanoseconds: 300_000_000)

        let isOpen = try await webView.callAsyncJavaScript(
            "var d = document.querySelector('.commit-detail-drawer'); return d ? d.classList.contains('open') : false",
            arguments: [:], in: nil, in: .page
        ) as? Bool
        XCTAssertNotEqual(isOpen, true, "Drawer should close when graph refreshes")
    }

    // --- Phase 3: Edge cases ---

    func testDrawerShowsActionButtons() async throws {
        try await pushGraphData()
        try await pushDetailData()

        let copyBtn = try await webView.callAsyncJavaScript(
            "return document.querySelector('.detail-action-btn[data-action=\"copyHash\"]') !== null",
            arguments: [:], in: nil, in: .page
        ) as? Bool
        XCTAssertEqual(copyBtn, true)

        let openBtn = try await webView.callAsyncJavaScript(
            "return document.querySelector('.detail-action-btn[data-action=\"openInBrowser\"]') !== null",
            arguments: [:], in: nil, in: .page
        ) as? Bool
        XCTAssertEqual(openBtn, true)
    }

    func testBinaryFilesShowZeroStats() async throws {
        try await pushGraphData()
        let files = """
        [{"path":"image.png","additions":0,"deletions":0}]
        """
        try await pushDetailData(files: files, totalFiles: 1, totalAdditions: 0, totalDeletions: 0)

        let count = try await webView.callAsyncJavaScript(
            "return document.querySelectorAll('.detail-file-item').length",
            arguments: [:], in: nil, in: .page
        ) as? Int
        XCTAssertEqual(count, 1)
    }
}
