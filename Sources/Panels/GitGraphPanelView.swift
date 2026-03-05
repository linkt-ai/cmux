import SwiftUI
import WebKit

struct GitGraphPanelView: View {
    @ObservedObject var panel: GitGraphPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int

    @State private var focusFlashOpacity: Double = 0.0
    @State private var focusFlashAnimationGeneration: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            GitGraphWebViewRepresentable(
                panel: panel,
                shouldAttach: isVisibleInUI
            )
            .id(panel.id)
        }
        .overlay {
            RoundedRectangle(cornerRadius: FocusFlashPattern.ringCornerRadius)
                .stroke(cmuxAccentColor().opacity(focusFlashOpacity), lineWidth: 3)
                .shadow(color: cmuxAccentColor().opacity(focusFlashOpacity * 0.35), radius: 10)
                .padding(FocusFlashPattern.ringInset)
                .allowsHitTesting(false)
        }
        .onChange(of: panel.focusFlashToken) { _ in
            runFocusFlashAnimation()
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(repoName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            if let branch = currentBranch {
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

    // MARK: - Helpers

    private var repoName: String {
        URL(fileURLWithPath: panel.repoPath).lastPathComponent
    }

    private var currentBranch: String? {
        let title = panel.displayTitle
        guard let openParen = title.firstIndex(of: "("),
              let closeParen = title.lastIndex(of: ")") else { return nil }
        let start = title.index(after: openParen)
        guard start < closeParen else { return nil }
        return String(title[start..<closeParen])
    }

    // MARK: - Focus Flash

    private func runFocusFlashAnimation() {
        focusFlashAnimationGeneration += 1
        let generation = focusFlashAnimationGeneration
        focusFlashOpacity = 0

        for segment in FocusFlashPattern.segments {
            let animation: Animation = segment.curve == .easeIn
                ? .easeIn(duration: segment.duration)
                : .easeOut(duration: segment.duration)

            DispatchQueue.main.asyncAfter(deadline: .now() + segment.delay) {
                guard focusFlashAnimationGeneration == generation else { return }
                withAnimation(animation) {
                    focusFlashOpacity = segment.targetOpacity
                }
            }
        }
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
