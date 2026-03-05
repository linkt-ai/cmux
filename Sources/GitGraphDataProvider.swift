import Foundation

// MARK: - Data Structures

/// Type of git reference.
enum GitRefType: String, Codable, Equatable {
    case localBranch
    case remoteBranch
    case tag
}

/// A git reference (branch, tag, etc.) pointing at a commit.
struct GitRef: Codable, Equatable {
    let name: String
    let hash: String
    let type: GitRefType
    let isHead: Bool
}

/// A single git commit with metadata.
struct GitCommit: Codable, Equatable {
    let hash: String
    let abbreviatedHash: String
    let parents: [String]
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let message: String
    let fullMessage: String
}

/// Aggregate git graph data for a repository.
struct GitGraphData: Codable, Equatable {
    let commits: [GitCommit]
    let refs: [GitRef]
    let headHash: String
    let currentBranch: String?
    let isDirty: Bool
    let repoName: String
    let repoPath: String
}

/// Errors from git graph data fetching.
enum GitGraphError: Error {
    case gitNotFound
    case notARepository
    case processError(String)
}

// MARK: - Provider

/// Fetches and parses git graph data from a repository path.
///
/// Follows the `PortScanner` pattern: runs `Process()` + `Pipe()` on a
/// dedicated background queue and delivers results via completion handler
/// on the main thread.
final class GitGraphDataProvider: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.cmux.git-graph", qos: .utility)

    /// Path to the git binary. Resolved once on first use.
    private lazy var gitPath: String? = {
        // macOS ships git at /usr/bin/git (Xcode CLT shim).
        if FileManager.default.fileExists(atPath: "/usr/bin/git") {
            return "/usr/bin/git"
        }
        // Fallback: ask the shell.
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["git"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (path?.isEmpty == false) ? path : nil
        } catch {
            return nil
        }
    }()

    // MARK: - Public API

    /// Fetch git graph data for the repository at `repoPath`.
    /// Completion is always called on the main thread.
    func fetchGraphData(repoPath: String, completion: @escaping (Result<GitGraphData, GitGraphError>) -> Void) {
        queue.async { [self] in
            let result = self.fetchSync(repoPath: repoPath)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    // MARK: - Synchronous fetch (runs on background queue)

    private func fetchSync(repoPath: String) -> Result<GitGraphData, GitGraphError> {
        guard let git = gitPath else {
            return .failure(.gitNotFound)
        }

        // Verify this is a git repo.
        let revParseResult = runGit(git, args: ["rev-parse", "--git-dir"], cwd: repoPath)
        switch revParseResult {
        case .failure:
            return .failure(.notARepository)
        case .success:
            break
        }

        // --- HEAD hash ---
        let headHashResult = runGit(git, args: ["rev-parse", "HEAD"], cwd: repoPath)
        let headHash: String
        switch headHashResult {
        case .success(let output):
            headHash = output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .failure(let err):
            return .failure(err)
        }

        // --- Current branch (nil if detached HEAD) ---
        let currentBranch: String?
        switch runGit(git, args: ["symbolic-ref", "--short", "HEAD"], cwd: repoPath) {
        case .success(let output):
            let name = output.trimmingCharacters(in: .whitespacesAndNewlines)
            currentBranch = name.isEmpty ? nil : name
        case .failure:
            currentBranch = nil // detached HEAD is not an error
        }

        // --- Dirty status ---
        let isDirty: Bool
        switch runGit(git, args: ["status", "--porcelain"], cwd: repoPath) {
        case .success(let output):
            isDirty = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .failure:
            isDirty = false
        }

        // --- Commits (last 100) ---
        // Format: %H \x1E %h \x1E %P \x1E %an \x1E %ae \x1E %aI \x1E %s \x1E %B \x00
        // Fields separated by \x1E (record separator), records separated by \x00 (null).
        let logFormat = "%H\u{1E}%h\u{1E}%P\u{1E}%an\u{1E}%ae\u{1E}%aI\u{1E}%s\u{1E}%B%x00"
        let commits: [GitCommit]
        switch runGit(git, args: ["log", "-n", "100", "--format=\(logFormat)"], cwd: repoPath) {
        case .success(let output):
            commits = parseCommits(output)
        case .failure:
            commits = []
        }

        // --- Refs ---
        // Format: %(refname) \x1E %(objectname) \x1E %(HEAD)
        let refFormat = "%(refname)\u{1E}%(objectname)\u{1E}%(HEAD)"
        let refs: [GitRef]
        switch runGit(git, args: ["for-each-ref", "--format=\(refFormat)", "refs/heads", "refs/remotes", "refs/tags"], cwd: repoPath) {
        case .success(let output):
            refs = parseRefs(output)
        case .failure:
            refs = []
        }

        // --- Repo name (last path component) ---
        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent

        return .success(GitGraphData(
            commits: commits,
            refs: refs,
            headHash: headHash,
            currentBranch: currentBranch,
            isDirty: isDirty,
            repoName: repoName,
            repoPath: repoPath
        ))
    }

    // MARK: - Git process runner

    /// Run a git command and return stdout, or a typed error.
    private func runGit(_ gitPath: String, args: [String], cwd: String) -> Result<String, GitGraphError> {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(.processError(error.localizedDescription))
        }

        guard process.terminationStatus == 0 else {
            return .failure(.processError("git \(args.first ?? "") exited with status \(process.terminationStatus)"))
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return .success(output)
    }

    // MARK: - Parsers

    /// Parse `git log` output using null-byte record separators and \x1E field separators.
    private func parseCommits(_ output: String) -> [GitCommit] {
        let isoFormatter = ISO8601DateFormatter()
        // Also support the extended format git sometimes emits (with timezone offset like +0100).
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")

        let records = output.components(separatedBy: "\0")
        var commits: [GitCommit] = []

        for record in records {
            let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let fields = trimmed.components(separatedBy: "\u{1E}")
            // Expect at least 8 fields: hash, abbrev, parents, authorName, authorEmail, date, subject, body
            guard fields.count >= 8 else { continue }

            let hash = fields[0]
            let abbreviatedHash = fields[1]
            let parents = fields[2].isEmpty ? [] : fields[2].components(separatedBy: " ")
            let authorName = fields[3]
            let authorEmail = fields[4]
            let dateStr = fields[5]
            let message = fields[6]
            // Body may contain field separators if commit message has \x1E; rejoin remaining fields.
            let fullMessage = fields[7...].joined(separator: "\u{1E}").trimmingCharacters(in: .whitespacesAndNewlines)

            let authorDate = isoFormatter.date(from: dateStr)
                ?? fallbackFormatter.date(from: dateStr)
                ?? Date.distantPast

            commits.append(GitCommit(
                hash: hash,
                abbreviatedHash: abbreviatedHash,
                parents: parents,
                authorName: authorName,
                authorEmail: authorEmail,
                authorDate: authorDate,
                message: message,
                fullMessage: fullMessage
            ))
        }

        return commits
    }

    /// Parse `git for-each-ref` output into `GitRef` values.
    /// Each line: `refname \x1E objectname \x1E HEAD-marker`
    private func parseRefs(_ output: String) -> [GitRef] {
        var refs: [GitRef] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let fields = trimmed.components(separatedBy: "\u{1E}")
            guard fields.count >= 3 else { continue }

            let fullRefName = fields[0]
            let hash = fields[1]
            let isHead = fields[2].trimmingCharacters(in: .whitespaces) == "*"

            // Determine ref type and extract short name.
            let name: String
            let type: GitRefType
            if fullRefName.hasPrefix("refs/heads/") {
                name = String(fullRefName.dropFirst("refs/heads/".count))
                type = .localBranch
            } else if fullRefName.hasPrefix("refs/remotes/") {
                name = String(fullRefName.dropFirst("refs/remotes/".count))
                type = .remoteBranch
            } else if fullRefName.hasPrefix("refs/tags/") {
                name = String(fullRefName.dropFirst("refs/tags/".count))
                type = .tag
            } else {
                continue
            }

            refs.append(GitRef(name: name, hash: hash, type: type, isHead: isHead))
        }

        return refs
    }
}
