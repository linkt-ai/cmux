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
    private var scriptMessageProxy: ScriptMessageProxy?
    private var messageHandlerRegistered = false
    private var cancellables = Set<AnyCancellable>()

    weak var workspace: Workspace?
    var isVisibleInUI: Bool = true
    private(set) var pendingRefreshWorkItem: DispatchWorkItem?
    private(set) var cachedScrollY: Double?
    var pendingScrollRestoreY: Double?
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

        let proxy = ScriptMessageProxy()
        config.userContentController.add(proxy, name: "gitGraph")

        let webView = CmuxWebView(frame: .zero, configuration: config)
        webView.underPageBackgroundColor = GhosttyBackgroundTheme.currentColor()

        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        self.webView = webView

        proxy.delegate = self
        self.scriptMessageProxy = proxy
        self.messageHandlerRegistered = true

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

    func installWorkspaceSubscriptions() {
        guard let workspace else { return }

        // React to branch changes — fires on BOTH focus switches and same-terminal changes.
        // workspace.gitBranch is updated in applyTabSelectionNow (focus change) and
        // updatePanelGitBranch (same terminal).
        // No removeDuplicates: the shell re-reports branch state after every command
        // (even git branch -d, git reset, etc. where branch/dirty don't change).
        // scheduleRefresh() debounces at 500ms so rapid re-reports are coalesced.
        workspace.$gitBranch
            .dropFirst()
            .sink { [weak self] _ in
                #if DEBUG
                dlog("git-graph: $gitBranch fired → scheduleRefresh")
                #endif
                self?.scheduleRefresh()
            }
            .store(in: &cancellables)

        // React to same-terminal CWD changes (dict value changes).
        workspace.$panelDirectories
            .compactMap { [weak self] dirs -> String? in
                guard let self,
                      let focusedId = self.workspace?.focusedPanelId else { return nil }
                return dirs[focusedId]
            }
            .removeDuplicates()
            .sink { [weak self] newDir in
                guard let self else { return }
                #if DEBUG
                dlog("git-graph: $panelDirectories fired, newDir=\(newDir)")
                #endif
                self.handleCWDChange(newDir)
            }
            .store(in: &cancellables)

        // React to focus switches — always refresh to pick up new commits/state.
        // No removeDuplicates: every focus switch should re-evaluate, even if same
        // terminal/directory. The debounce in scheduleRefresh() coalesces rapid switches.
        NotificationCenter.default.publisher(for: .ghosttyDidFocusSurface)
            .sink { [weak self] notification in
                guard let self,
                      let workspace = self.workspace,
                      let surfaceId = notification.userInfo?[GhosttyNotificationKey.surfaceId] as? UUID,
                      let tabId = notification.userInfo?[GhosttyNotificationKey.tabId] as? UUID,
                      tabId == workspace.id,
                      workspace.panels[surfaceId] is TerminalPanel else { return }

                #if DEBUG
                dlog("git-graph: focusSurface fired, surfaceId=\(surfaceId)")
                #endif

                guard let newDir = workspace.panelDirectories[surfaceId] else {
                    self.showNoRepoState()
                    return
                }
                self.handleCWDChange(newDir)
            }
            .store(in: &cancellables)
    }

    private func handleCWDChange(_ newDir: String) {
        dataProvider.resolveRepoRoot(fromCWD: newDir) { [weak self] newRoot in
            guard let self else { return }
            guard let newRoot else {
                self.showNoRepoState()
                return
            }
            if newRoot != self.repoPath {
                self.repoPath = newRoot
                self.repoName = URL(fileURLWithPath: newRoot).lastPathComponent
                self.displayTitle = self.repoName
                self.fetchAndPushData()
            } else {
                self.scheduleRefresh()
            }
        }
    }

    /// Clear the graph when the focused terminal is not in a git repository.
    func showNoRepoState() {
        repoPath = ""
        repoName = ""
        currentBranch = nil
        displayTitle = "Git Graph"
        let emptyData = GitGraphData(
            commits: [],
            refs: [],
            headHash: "",
            currentBranch: nil,
            isDirty: false,
            repoName: "",
            repoPath: ""
        )
        pushDataToJS(emptyData)
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
            case .failure(let err):
                #if DEBUG
                dlog("git-graph: fetchAndPushData failed: \(err)")
                #endif
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
        ) { [weak self] _ in
            guard let self else { return }
            self.webView.evaluateJavaScript("window.getScrollY()") { result, _ in
                if let y = result as? Double { self.cachedScrollY = y }
            }
            if let restoreY = self.pendingScrollRestoreY {
                self.pendingScrollRestoreY = nil
                self.webView.evaluateJavaScript("window.setScrollY(\(restoreY))", completionHandler: nil)
            }
        }
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
        if messageHandlerRegistered {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "gitGraph")
            messageHandlerRegistered = false
        }
        scriptMessageProxy?.delegate = nil
        scriptMessageProxy = nil
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

    // MARK: - JS→Swift Message Handling

    fileprivate func handleScriptMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        handleAction(action, body: body)
    }

    private func handleAction(_ action: String, body: [String: Any]) {
        switch action {
        case "copyHash":
            guard let hash = body["hash"] as? String else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hash, forType: .string)
        case "openInBrowser":
            guard let hash = body["hash"] as? String else { return }
            openCommitInBrowser(hash: hash)
        case "checkoutBranch":
            guard let branch = body["branch"] as? String else { return }
            showCheckoutConfirmation(branch: branch)
        case "commitSelected":
            guard let hash = body["hash"] as? String else { return }
            fetchAndPushCommitDetail(hash: hash)
        default:
            break
        }
    }

    // MARK: - Open Commit in Browser

    private func openCommitInBrowser(hash: String) {
        dataProvider.getRemoteURL(repoPath: repoPath) { [weak self] result in
            guard let self else { return }
            if case .success(let url) = result {
                let commitURL = url.appendingPathComponent("commit").appendingPathComponent(hash)
                NSWorkspace.shared.open(commitURL)
            }
        }
    }

    // MARK: - Commit Detail

    private func fetchAndPushCommitDetail(hash: String) {
        dataProvider.fetchCommitDetail(repoPath: repoPath, hash: hash) { [weak self] result in
            guard let self else { return }
            if case .success(let detail) = result {
                let encoder = JSONEncoder()
                guard let jsonData = try? encoder.encode(detail),
                      let jsonString = String(data: jsonData, encoding: .utf8) else { return }
                self.webView.callAsyncJavaScript(
                    "window.showCommitDetail(jsonString)",
                    arguments: ["jsonString": jsonString],
                    in: nil,
                    in: .page
                ) { _ in }
            }
        }
    }

    // MARK: - Checkout Branch

    private func showCheckoutConfirmation(branch: String) {
        let alert = NSAlert()
        alert.messageText = "Checkout Branch"
        alert.informativeText = "Switch to branch \"\(branch)\"?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Checkout")
        alert.addButton(withTitle: "Cancel")
        guard let window = webView.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.performCheckout(branch: branch)
        }
    }

    private func performCheckout(branch: String) {
        dataProvider.checkoutBranch(repoPath: repoPath, branch: branch) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.refresh()
            case .failure(let err):
                #if DEBUG
                dlog("git-graph: checkout failed: \(err)")
                #endif
            }
        }
    }
}

// MARK: - Script Message Proxy

private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var delegate: GitGraphPanel?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.handleScriptMessage(message)
    }
}

// MARK: - Navigation Delegate

private final class GitGraphNavigationDelegate: NSObject, WKNavigationDelegate {
    var onDidFinish: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onDidFinish?()
    }
}
