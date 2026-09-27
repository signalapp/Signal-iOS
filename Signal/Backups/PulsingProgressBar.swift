//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftUI

struct PulsingProgressBar: View {
    struct ClearTrackProgressView: UIViewRepresentable {
        let value: Float
        let tintColor: UIColor

        func makeUIView(context: Context) -> UIProgressView {
            let progressView = UIProgressView()
            progressView.trackTintColor = .clear
            progressView.progressTintColor = tintColor
            return progressView
        }

        func updateUIView(_ uiView: UIProgressView, context: Context) {
            uiView.setProgress(value, animated: false)
        }
    }

    let value: Float
    let animationDuration: TimeInterval = 1
    let stopAfter: TimeInterval = 3

    init(value: Float) {
        self.value = value
    }

    @State private var animationPart1Progress: Float = 0
    @State private var animationPart2Progress: Float = 0
    @State private var animationPart3Progress: Float = 0
    @State private var lastValue: Float?
    @State private var isAnimating = true
    @State private var animationTimer: Timer?
    @State private var animationStopTimer: Timer?

    var body: some View {
        ZStack {
            ProgressView(value: value)
                .progressViewStyle(.linear)
            ClearTrackProgressView(
                value: value * animationPart1Progress,
                tintColor: .tintColor
                    .blended(with: .white, alpha: 0.2),
            )
            ClearTrackProgressView(
                value: value * animationPart2Progress,
                tintColor: .tintColor,
            )
            .onAppear {
                // The animation gets started once and runs forever;
                // it just no-ops on each loop if not animating.
                startLoopingAnimation()
            }
            .onChange(of: value) { newValue in
                if lastValue != newValue {
                    // When the value changes, reset
                    // the stop timer.
                    startStopTimer()
                }
            }
            .onDisappear {
                self.animationTimer?.invalidate()
                self.animationTimer = nil
                self.animationStopTimer?.invalidate()
                self.animationStopTimer = nil
                self.isAnimating = true
            }
        }
    }

    private func startLoopingAnimation() {
        self.animationTimer = Timer.scheduledTimer(
            withTimeInterval: animationDuration / 100,
            repeats: true,
            block: { _ in
                // Don't animate under 20%; it looks ugly
                guard self.isAnimating, (self.lastValue ?? 0) > 0.2 else {
                    animationPart1Progress = 0
                    animationPart2Progress = 0
                    animationPart3Progress = 0
                    return
                }
                if animationPart1Progress < 0.75 {
                    animationPart1Progress += 0.01
                } else if animationPart2Progress < 0.99 {
                    if animationPart1Progress < 0.99 {
                        animationPart1Progress += 0.01
                    }
                    animationPart2Progress += 0.01
                } else if animationPart3Progress < 1 {
                    animationPart3Progress += 0.01
                } else {
                    animationPart1Progress = 0
                    animationPart2Progress = 0
                    animationPart3Progress = 0
                }
            },
        )
        startStopTimer()
    }

    /// We stop the animation after stopAfter seconds of no updates.
    private func startStopTimer() {
        self.animationStopTimer?.invalidate()
        self.isAnimating = true
        self.animationStopTimer = Timer.scheduledTimer(
            withTimeInterval: stopAfter,
            repeats: false,
            block: { [self] _ in
                self.isAnimating = false
            },
        )
        self.lastValue = value
    }
}
