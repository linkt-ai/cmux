import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class GitGraphCommitDetailTests: XCTestCase {

    // MARK: - CommitDetailData Model

    func testCommitDetailDataCodable() throws {
        let file = CommitFileChange(path: "Sources/Foo.swift", additions: 10, deletions: 3)
        let detail = CommitDetailData(
            hash: "abc123",
            files: [file],
            totalFiles: 1,
            totalAdditions: 10,
            totalDeletions: 3
        )

        let data = try JSONEncoder().encode(detail)
        let decoded = try JSONDecoder().decode(CommitDetailData.self, from: data)
        XCTAssertEqual(decoded.hash, "abc123")
        XCTAssertEqual(decoded.files.count, 1)
        XCTAssertEqual(decoded.files[0].path, "Sources/Foo.swift")
        XCTAssertEqual(decoded.files[0].additions, 10)
        XCTAssertEqual(decoded.files[0].deletions, 3)
        XCTAssertEqual(decoded.totalFiles, 1)
        XCTAssertEqual(decoded.totalAdditions, 10)
        XCTAssertEqual(decoded.totalDeletions, 3)
    }

    // MARK: - Data Provider: fetchCommitDetail

    func testFetchCommitDetailReturnsFileChanges() throws {
        let provider = GitGraphDataProvider()
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        let expectation = expectation(description: "fetch detail")
        var result: Result<CommitDetailData, Error>?

        provider.fetchCommitDetail(repoPath: repoPath, hash: "HEAD") { r in
            result = r
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)

        let detail = try result!.get()
        XCTAssertFalse(detail.files.isEmpty, "HEAD commit should have changed files")
    }

    func testFetchCommitDetailFileHasPath() throws {
        let provider = GitGraphDataProvider()
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        let expectation = expectation(description: "fetch detail")
        var result: Result<CommitDetailData, Error>?

        provider.fetchCommitDetail(repoPath: repoPath, hash: "HEAD") { r in
            result = r
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)

        let detail = try result!.get()
        let file = detail.files[0]
        XCTAssertFalse(file.path.isEmpty, "File path should not be empty")
    }

    func testFetchCommitDetailHasSummary() throws {
        let provider = GitGraphDataProvider()
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        let expectation = expectation(description: "fetch detail")
        var result: Result<CommitDetailData, Error>?

        provider.fetchCommitDetail(repoPath: repoPath, hash: "HEAD") { r in
            result = r
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)

        let detail = try result!.get()
        XCTAssertGreaterThan(detail.totalFiles, 0)
    }

    func testFetchCommitDetailDeliversOnMainThread() {
        let provider = GitGraphDataProvider()
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        let expectation = expectation(description: "main thread")

        provider.fetchCommitDetail(repoPath: repoPath, hash: "HEAD") { _ in
            XCTAssertTrue(Thread.isMainThread)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
    }

    func testFetchCommitDetailInvalidHashFails() {
        let provider = GitGraphDataProvider()
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        let expectation = expectation(description: "invalid hash")
        var didFail = false

        provider.fetchCommitDetail(repoPath: repoPath, hash: "0000000000000000000000000000000000000000") { result in
            if case .failure = result { didFail = true }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
        XCTAssertTrue(didFail)
    }

    // MARK: - Panel: commitSelected action

    @MainActor
    func testHandleCommitSelectedAction() {
        let panel = GitGraphPanel(workspaceId: UUID(), repoPath: "/tmp")
        panel.handleAction("commitSelected", body: ["hash": "abc123"])
        panel.close()
    }
}
