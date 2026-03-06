import Combine
import WebKit
import AppKit

@MainActor
final class GitGraphPanel: Panel, ObservableObject {

    let id: UUID
    let panelType: PanelType = .gitGraph
    let webView: CmuxWebView
    private(set) var repoPath: String
    let workspaceId: UUID
    private(set) var repoName: String

    @Published var displayTitle: String
    @Published private(set) var currentBranch: String?
    @Published private(set) var focusFlashToken: Int = 0

    var displayIcon: String? { "arrow.triangle.branch" }

    private let dataProvider = GitGraphDataProvider()
    private var navigationDelegate: GitGraphNavigationDelegate?
    private var cancellables = Set<AnyCancellable>()

    weak var workspace: Workspace?
    var isVisibleInUI: Bool = true
    private(set) var pendingRefreshWorkItem: DispatchWorkItem?
    var hasScheduledRefresh: Bool { pendingRefreshWorkItem != nil }
    private static let refreshDebounceInterval: TimeInterval = 0.5

    init(workspaceId: UUID, repoPath: String) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.repoPath = repoPath

        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
        self.repoName = repoName
        self.displayTitle = repoName

        let config = WKWebViewConfiguration()
        config.processPool = BrowserPanel.sharedProcessPool
        config.websiteDataStore = .default()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = CmuxWebView(frame: .zero, configuration: config)
        webView.underPageBackgroundColor = GhosttyBackgroundTheme.currentColor()

        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        self.webView = webView

        let navDelegate = GitGraphNavigationDelegate()
        navDelegate.onDidFinish = { [weak self] in
            self?.onPageLoaded()
        }
        webView.navigationDelegate = navDelegate
        self.navigationDelegate = navDelegate

        NotificationCenter.default.publisher(for: .ghosttyDefaultBackgroundDidChange)
            .sink { [weak self] notification in
                guard let self else { return }
                self.webView.underPageBackgroundColor = GhosttyBackgroundTheme.color(from: notification)
                self.applyTheme()
            }
            .store(in: &cancellables)

        loadContent()
    }

    // MARK: - Content Loading

    private func loadContent() {
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let gitGraphDir = resourceURL.appendingPathComponent("git-graph")
        let indexURL = gitGraphDir.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return }
        webView.loadFileURL(indexURL, allowingReadAccessTo: gitGraphDir)
    }

    private func onPageLoaded() {
        applyTheme()
        fetchAndPushData()
    }

    // MARK: - Data

    func refresh() {
        fetchAndPushData()
    }

    func scheduleRefresh() {
        guard isVisibleInUI else { return }
        pendingRefreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRefreshWorkItem = nil
            self.fetchAndPushData()
        }
        pendingRefreshWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.refreshDebounceInterval,
            execute: item
        )
    }

    static func resolveRepoRoot(fromCWD cwd: String) -> String? {
        var url = URL(fileURLWithPath: cwd)
        let fm = FileManager.default
        while url.path != "/" {
            if fm.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return url.path
            }
            url = url.deletingLastPathComponent()
        }
        return nil
    }

    func updateRepoPathIfNeeded(fromCWD cwd: String) -> Bool {
        guard let newRoot = Self.resolveRepoRoot(fromCWD: cwd) else {
            return !repoPath.isEmpty
        }
        if newRoot != repoPath {
            repoPath = newRoot
            repoName = URL(fileURLWithPath: newRoot).lastPathComponent
            displayTitle = repoName
            return true
        }
        return false
    }

    func installWorkspaceSubscriptions() {
        guard let workspace else { return }

        workspace.$panelGitBranches
            .map { [weak self] branches -> String? in
                guard let self,
                      let focusedId = self.workspace?.focusedPanelId,
                      self.workspace?.panels[focusedId] is TerminalPanel else { return nil }
                return branches[focusedId]?.branch
            }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleRefresh()
            }
            .store(in: &cancellables)

        workspace.$panelDirectories
            .compactMap { [weak self] dirs -> String? in
                guard let self,
                      let focusedId = self.workspace?.focusedPanelId else { return nil }
                return dirs[focusedId]
            }
            .removeDuplicates()
            .sink { [weak self] newDir in
                guard let self else { return }
                if self.updateRepoPathIfNeeded(fromCWD: newDir) {
                    self.fetchAndPushData()
                } else {
                    self.scheduleRefresh()
                }
            }
            .store(in: &cancellables)
    }

    private func fetchAndPushData() {
        dataProvider.fetchGraphData(repoPath: repoPath) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let data):
                self.pushDataToJS(data)
                self.currentBranch = data.currentBranch
                if let branch = data.currentBranch {
                    self.displayTitle = "\(self.repoName) (\(branch))"
                } else {
                    self.displayTitle = self.repoName
                }
            case .failure:
                break
            }
        }
    }

    private func pushDataToJS(_ data: GitGraphData) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let jsonData = try? encoder.encode(data),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        webView.callAsyncJavaScript(
            "window.updateGraph(jsonString)",
            arguments: ["jsonString": jsonString],
            in: nil,
            in: .page
        ) { _ in }
    }

    // MARK: - Theme

    private func applyTheme() {
        let bgColor = GhosttyBackgroundTheme.currentColor()
        let hex = bgColor.hexString()
        let isDark: Bool = {
            guard let appearance = NSApp?.effectiveAppearance else { return false }
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }()
        webView.callAsyncJavaScript(
            "window.applyTheme(hex, isDark)",
            arguments: ["hex": hex, "isDark": isDark],
            in: nil,
            in: .page
        ) { _ in }
    }

    // MARK: - Panel Protocol

    func focus() {
        guard let window = webView.window, !webView.isHiddenOrHasHiddenAncestor else { return }
        window.makeFirstResponder(webView)
    }

    func unfocus() {
        guard let window = webView.window else { return }
        var responder: NSResponder? = window.firstResponder
        var hops = 0
        while let current = responder, hops < 64 {
            if current === webView {
                window.makeFirstResponder(nil)
                return
            }
            responder = current.nextResponder
            hops += 1
        }
    }

    func close() {
        unfocus()
        webView.stopLoading()
        webView.navigationDelegate = nil
        navigationDelegate = nil
        pendingRefreshWorkItem?.cancel()
        pendingRefreshWorkItem = nil
        cancellables.removeAll()
    }

    func triggerFlash() {
        focusFlashToken += 1
    }
}

// MARK: - Navigation Delegate

private final class GitGraphNavigationDelegate: NSObject, WKNavigationDelegate {
    var onDidFinish: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onDidFinish?()
    }
}
