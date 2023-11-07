//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

final class MessageTimerView: ManualLayoutView {

    private enum Constants {
        static let layoutSize: CGFloat = 12
        // 0 == about to expire, 12 == just started countdown.
        static let quantizationLevelCount: UInt64 = 12
    }

    private let imageView = CVImageView()
    private var animationTimer: Timer?

    required init() {
        super.init(name: "OWSMessageTimerView")

        addSubviewToFillSuperviewEdges(imageView)
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init(name: String) {
        fatalError("init(name:) has not been implemented")
    }

    deinit {
        clearAnimation()
    }

    func configure(
        expirationTimestampMs: UInt64,
        disappearingMessageInterval: UInt32,
        tintColor: UIColor
    ) {
        let expirationProgress = self.expirationProgress(
            expirationTimestampMs: expirationTimestampMs,
            disappearingMessageInterval: disappearingMessageInterval,
            nowMs: Date.ows_millisecondTimestamp()
        )
        updateIcon(quantizedValue: expirationProgress.quantizedValue, tintColor: tintColor)
        startAnimation(expirationProgress: expirationProgress, tintColor: tintColor)
    }

    private struct ExpirationProgress {
        var quantizedValue: UInt64
        var timerConfiguration: TimerConfiguration?
    }

    private struct TimerConfiguration {
        let nextRefreshMs: UInt64
        let refreshIntervalMs: UInt64
    }

    private func expirationProgress(
        expirationTimestampMs: UInt64,
        disappearingMessageInterval: UInt32,
        nowMs: UInt64
    ) -> ExpirationProgress {
        // Every N milliseconds we move to the next progress level.
        let refreshIntervalMs = UInt64(disappearingMessageInterval) * 1000 / Constants.quantizationLevelCount

        // It will never expire because the timer hasn't started yet.
        guard expirationTimestampMs > 0, refreshIntervalMs > 0 else {
            return ExpirationProgress(quantizedValue: Constants.quantizationLevelCount)
        }

        let remainingMs = expirationTimestampMs.subtractingReportingOverflow(nowMs)
        // It already expired because the expiration date is in the past.
        guard !remainingMs.overflow else {
            return ExpirationProgress(quantizedValue: 0)
        }

        let intermediateValue = remainingMs.partialValue.addingReportingOverflow(refreshIntervalMs/2)
        // The disappearing interval is way too large -- something is wrong.
        guard !intermediateValue.overflow else {
            return ExpirationProgress(quantizedValue: Constants.quantizationLevelCount)
        }

        let quantizedValue = intermediateValue.partialValue / refreshIntervalMs
        return ExpirationProgress(
            quantizedValue: quantizedValue,
            timerConfiguration: {
                guard quantizedValue > 0 else {
                    return nil
                }
                return TimerConfiguration(
                    nextRefreshMs: expirationTimestampMs - (quantizedValue - 1) * refreshIntervalMs - refreshIntervalMs/2,
                    refreshIntervalMs: refreshIntervalMs
                )
            }()
        )
    }

    private func updateIcon(quantizedValue: UInt64, tintColor: UIColor) {
        let progressIcon = self.progressIcon(quantizedValue: quantizedValue, tintColor: tintColor)
        imageView.image = progressIcon?.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = tintColor
    }

    private func progressIcon(quantizedValue: UInt64, tintColor: UIColor) -> UIImage? {
        owsAssertDebug(quantizedValue <= Constants.quantizationLevelCount)
        let imageName = String(format: "messagetimer-%02ld", quantizedValue * 5)
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Missing icon.")
            return nil
        }
        owsAssertDebug(image.size.width == Constants.layoutSize)
        owsAssertDebug(image.size.height == Constants.layoutSize)
        return image
    }

    private func startAnimation(expirationProgress: ExpirationProgress, tintColor: UIColor) {
        AssertIsOnMainThread()

        clearAnimation()
        guard let timerConfiguration = expirationProgress.timerConfiguration else {
            return
        }

        var quantizedValue = expirationProgress.quantizedValue
        let animationTimer = Timer(
            fire: Date(millisecondsSince1970: timerConfiguration.nextRefreshMs),
            interval: TimeInterval(timerConfiguration.refreshIntervalMs)/1000,
            repeats: true,
            block: { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                quantizedValue -= 1
                self.updateIcon(quantizedValue: quantizedValue, tintColor: tintColor)
                guard quantizedValue > 0 else {
                    timer.invalidate()
                    return
                }
            }
        )
        self.animationTimer = animationTimer
        RunLoop.main.add(animationTimer, forMode: .common)
    }

    private func clearAnimation() {
        AssertIsOnMainThread()

        animationTimer?.invalidate()
        animationTimer = nil
    }

    func prepareForReuse() {
        clearAnimation()
        imageView.image = nil
    }

    static var measureSize: CGSize {
        .square(Constants.layoutSize)
    }
}
