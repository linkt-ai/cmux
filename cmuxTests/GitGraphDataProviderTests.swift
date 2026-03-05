import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

// MARK: - Data Structure Tests

final class GitGraphDataStructureTests: XCTestCase {

    // MARK: GitRefType

    func testGitRefTypeRawValues() {
        XCTAssertEqual(GitRefType.localBranch.rawValue, "localBranch")
        XCTAssertEqual(GitRefType.remoteBranch.rawValue, "remoteBranch")
        XCTAssertEqual(GitRefType.tag.rawValue, "tag")
    }

    // MARK: GitRef

    func testGitRefCodableRoundTrip() throws {
        let ref = GitRef(name: "main", hash: "abc123", type: .localBranch, isHead: true)
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(GitRef.self, from: data)
        XCTAssertEqual(decoded.name, "main")
        XCTAssertEqual(decoded.hash, "abc123")
        XCTAssertEqual(decoded.type, .localBranch)
        XCTAssertTrue(decoded.isHead)
    }

    func testGitRefEquality() {
        let a = GitRef(name: "main", hash: "abc", type: .localBranch, isHead: true)
        let b = GitRef(name: "main", hash: "abc", type: .localBranch, isHead: true)
        let c = GitRef(name: "dev", hash: "def", type: .remoteBranch, isHead: false)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: GitCommit

    func testGitCommitCodableRoundTrip() throws {
        let commit = GitCommit(
            hash: "abc123def456",
            abbreviatedHash: "abc123d",
            parents: ["parent1", "parent2"],
            authorName: "Test User",
            authorEmail: "test@example.com",
            authorDate: ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!,
            message: "Initial commit",
            fullMessage: "Initial commit\n\nDetailed description"
        )
        let data = try JSONEncoder().encode(commit)
        let decoded = try JSONDecoder().decode(GitCommit.self, from: data)
        XCTAssertEqual(decoded.hash, "abc123def456")
        XCTAssertEqual(decoded.abbreviatedHash, "abc123d")
        XCTAssertEqual(decoded.parents, ["parent1", "parent2"])
        XCTAssertEqual(decoded.authorName, "Test User")
        XCTAssertEqual(decoded.authorEmail, "test@example.com")
        XCTAssertEqual(decoded.message, "Initial commit")
        XCTAssertEqual(decoded.fullMessage, "Initial commit\n\nDetailed description")
    }

    func testGitCommitWithNoParents() throws {
        let commit = GitCommit(
            hash: "abc123",
            abbreviatedHash: "abc",
            parents: [],
            authorName: "Test",
            authorEmail: "test@test.com",
            authorDate: Date(),
            message: "root commit",
            fullMessage: "root commit"
        )
        XCTAssertTrue(commit.parents.isEmpty)
        let data = try JSONEncoder().encode(commit)
        let decoded = try JSONDecoder().decode(GitCommit.self, from: data)
        XCTAssertTrue(decoded.parents.isEmpty)
    }

    // MARK: GitGraphData

    func testGitGraphDataCodableRoundTrip() throws {
        let graphData = GitGraphData(
            commits: [],
            refs: [],
            headHash: "abc123",
            currentBranch: "main",
            isDirty: false,
            repoName: "cmux",
            repoPath: "/path/to/cmux"
        )
        let data = try JSONEncoder().encode(graphData)
        let decoded = try JSONDecoder().decode(GitGraphData.self, from: data)
        XCTAssertEqual(decoded.headHash, "abc123")
        XCTAssertEqual(decoded.currentBranch, "main")
        XCTAssertFalse(decoded.isDirty)
        XCTAssertEqual(decoded.repoName, "cmux")
        XCTAssertEqual(decoded.repoPath, "/path/to/cmux")
    }

    func testGitGraphDataWithNilCurrentBranch() throws {
        let graphData = GitGraphData(
            commits: [],
            refs: [],
            headHash: "abc123",
            currentBranch: nil,
            isDirty: false,
            repoName: "cmux",
            repoPath: "/path/to/cmux"
        )
        let data = try JSONEncoder().encode(graphData)
        let decoded = try JSONDecoder().decode(GitGraphData.self, from: data)
        XCTAssertNil(decoded.currentBranch)
    }
}

// MARK: - GitGraphDataProvider Integration Tests

final class GitGraphDataProviderTests: XCTestCase {

    var provider: GitGraphDataProvider!

    override func setUp() {
        super.setUp()
        provider = GitGraphDataProvider()
    }

    // MARK: Happy path — fetch from this repo

    func testFetchGraphDataFromCurrentRepo() {
        let expectation = expectation(description: "fetch completes")
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // cmuxTests/
            .deletingLastPathComponent()  // project root
            .path

        provider.fetchGraphData(repoPath: repoPath) { result in
            switch result {
            case .success(let data):
                XCTAssertFalse(data.commits.isEmpty, "Should have commits")
                XCTAssertFalse(data.refs.isEmpty, "Should have refs")
                XCTAssertFalse(data.headHash.isEmpty, "HEAD hash should exist")
                XCTAssertFalse(data.repoName.isEmpty, "Repo name should exist")
                XCTAssertFalse(data.repoPath.isEmpty, "Repo path should exist")
            case .failure(let error):
                XCTFail("Expected success, got \(error)")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10)
    }

    func testFetchGraphDataDeliversOnMainThread() {
        let expectation = expectation(description: "fetch completes")
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        provider.fetchGraphData(repoPath: repoPath) { _ in
            XCTAssertTrue(Thread.isMainThread, "Completion must be on main thread")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10)
    }

    func testCommitsHaveExpectedFields() {
        let expectation = expectation(description: "fetch completes")
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        provider.fetchGraphData(repoPath: repoPath) { result in
            if case .success(let data) = result, let commit = data.commits.first {
                XCTAssertFalse(commit.hash.isEmpty)
                XCTAssertFalse(commit.abbreviatedHash.isEmpty)
                XCTAssertFalse(commit.authorName.isEmpty)
                XCTAssertFalse(commit.message.isEmpty)
            } else {
                XCTFail("Expected at least one commit")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10)
    }

    func testRefsIncludeLocalBranches() {
        let expectation = expectation(description: "fetch completes")
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        provider.fetchGraphData(repoPath: repoPath) { result in
            if case .success(let data) = result {
                let localBranches = data.refs.filter { $0.type == .localBranch }
                XCTAssertFalse(localBranches.isEmpty, "Should have at least one local branch")
            } else {
                XCTFail("Expected success")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10)
    }

    // MARK: Error cases

    func testFetchFromNonExistentPathReturnsError() {
        let expectation = expectation(description: "fetch completes")

        provider.fetchGraphData(repoPath: "/nonexistent/path/\(UUID())") { result in
            if case .failure = result {
                // Expected
            } else {
                XCTFail("Expected failure for non-existent path")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10)
    }

    func testFetchFromNonRepoPathReturnsError() {
        let expectation = expectation(description: "fetch completes")

        provider.fetchGraphData(repoPath: "/tmp") { result in
            if case .failure = result {
                // Expected
            } else {
                XCTFail("Expected failure for non-repo path")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10)
    }
}
