import SwiftUI

struct FocusFlashModifier: ViewModifier {
    let token: Int

    @State private var opacity: Double = 0.0
    @State private var generation: Int = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: FocusFlashPattern.ringCornerRadius)
                    .stroke(cmuxAccentColor().opacity(opacity), lineWidth: 3)
                    .shadow(color: cmuxAccentColor().opacity(opacity * 0.35), radius: 10)
                    .padding(FocusFlashPattern.ringInset)
                    .allowsHitTesting(false)
            }
            .onChange(of: token) { _ in
                runAnimation()
            }
    }

    private func runAnimation() {
        generation &+= 1
        let gen = generation
        opacity = FocusFlashPattern.values.first ?? 0

        for segment in FocusFlashPattern.segments {
            DispatchQueue.main.asyncAfter(deadline: .now() + segment.delay) {
                guard generation == gen else { return }
                let anim: Animation = segment.curve == .easeIn
                    ? .easeIn(duration: segment.duration)
                    : .easeOut(duration: segment.duration)
                withAnimation(anim) {
                    opacity = segment.targetOpacity
                }
            }
        }
    }
}
