import SwiftUI

struct GitGraphPanelView: View {
    @ObservedObject var panel: GitGraphPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            GitGraphWebViewRepresentable(
                panel: panel,
                shouldAttach: isVisibleInUI
            )
            .id(panel.id)
        }
        .modifier(FocusFlashModifier(token: panel.focusFlashToken))
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(panel.repoName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            if let branch = panel.currentBranch {
                Text(branch)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(cmuxAccentColor().opacity(0.15))
                    .clipShape(Capsule())
                    .lineLimit(1)
            }

            Spacer()

            Button {
                panel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh git graph")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Color(nsColor: GhosttyBackgroundTheme.currentColor()))
    }

}

// MARK: - WebView Representable

private struct GitGraphWebViewRepresentable: NSViewRepresentable {
    let panel: GitGraphPanel
    let shouldAttach: Bool

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let webView = panel.webView

        if !shouldAttach {
            if webView.superview === nsView {
                webView.removeFromSuperview()
            }
            return
        }

        if webView.superview !== nsView {
            webView.removeFromSuperview()
            nsView.subviews.forEach { $0.removeFromSuperview() }
            nsView.addSubview(webView)
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.autoresizingMask = [.width, .height]
            webView.frame = nsView.bounds
        }
    }
}
