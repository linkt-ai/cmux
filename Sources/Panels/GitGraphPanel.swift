import Foundation
import Combine
import WebKit
import AppKit

@MainActor
final class GitGraphPanel: Panel, ObservableObject {

    let id: UUID
    let panelType: PanelType = .gitGraph
    let webView: CmuxWebView
    let repoPath: String

    @Published var displayTitle: String
    @Published private(set) var focusFlashToken: Int = 0

    var displayIcon: String? { "arrow.triangle.branch" }

    private let dataProvider = GitGraphDataProvider()
    private var navigationDelegate: GitGraphNavigationDelegate?
    private var cancellables = Set<AnyCancellable>()

    init(workspaceId: UUID, repoPath: String) {
        self.id = UUID()
        self.repoPath = repoPath

        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
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

    private func fetchAndPushData() {
        dataProvider.fetchGraphData(repoPath: repoPath) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let data):
                self.pushDataToJS(data)
                if let branch = data.currentBranch {
                    self.displayTitle = "\(data.repoName) (\(branch))"
                } else {
                    self.displayTitle = data.repoName
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
        let escaped = jsonString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.updateGraph('\(escaped)')") { _, _ in }
    }

    // MARK: - Theme

    private func applyTheme() {
        let bgColor = GhosttyBackgroundTheme.currentColor()
        let hex = bgColor.hexString()
        let isDark: Bool = {
            guard let appearance = NSApp?.effectiveAppearance else { return false }
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }()
        webView.evaluateJavaScript("window.applyTheme('\(hex)', \(isDark))") { _, _ in }
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
