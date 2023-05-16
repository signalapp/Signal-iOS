//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

public class MessageTimerView: ManualLayoutView {

    private static let layoutSize: CGFloat = 12

    private struct Configuration {
        let initialDurationSeconds: UInt32
        let expirationTimestamp: UInt64
        let tintColor: UIColor
    }
    private var configuration: Configuration?

    private let imageView = CVImageView()
    private var animationTimer: Timer?

    // 0 == about to expire, 12 == just started countdown.
    private static let progress12_start: Int = 12
    private var progress12: Int = MessageTimerView.progress12_start {
        didSet {
            if oldValue != progress12 {
                updateIcon()
            }
        }
    }

    public required init() {
        super.init(name: "OWSMessageTimerView")

        addSubviewToFillSuperviewEdges(imageView)
    }

    @available(*, unavailable, message: "use other constructor instead.")
    public required init(name: String) {
        fatalError("init(name:) has not been implemented")
    }

    deinit {
        clearAnimation()
    }

    public func configure(expirationTimestamp: UInt64,
                          initialDurationSeconds: UInt32,
                          tintColor: UIColor) {
        self.configuration = Configuration(initialDurationSeconds: initialDurationSeconds,
                                           expirationTimestamp: expirationTimestamp,
                                           tintColor: tintColor)

        updateProgress12()
        updateIcon()
        startAnimation()
    }

    @objc
    private func updateProgress12() {
        guard let configuration = self.configuration else {
            return
        }
        let initialDurationSeconds = configuration.initialDurationSeconds
        let expirationTimestamp = configuration.expirationTimestamp

        let hasStartedCountdown = expirationTimestamp > 0
        if !hasStartedCountdown {
            self.progress12 = Self.progress12_start
            return
        }

        let nowTimestamp = NSDate.ows_millisecondTimeStamp()
        let msRemaining = (expirationTimestamp > nowTimestamp
                            ? expirationTimestamp - nowTimestamp
                            : 0)
        let secondsRemaining = max(0, Double(msRemaining) / 1000)
        var progress: Double = 0
        if initialDurationSeconds > 0 {
            progress = secondsRemaining / Double(initialDurationSeconds)
        }
        self.progress12 = Int(round(progress.clamp01() * 12))
        owsAssertDebug(progress12 >= 0)
        owsAssertDebug(progress12 <= 12)
    }

    private func updateIcon() {
        guard let configuration = self.configuration else {
            imageView.image = nil
            return
        }
        guard let progressIcon = self.progressIcon else {
            owsFailDebug("Missing icon.")
            imageView.image = nil
            return
        }
        imageView.image = progressIcon.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = configuration.tintColor
    }

    private var progressIcon: UIImage? {
        owsAssertDebug(progress12 >= 0)
        owsAssertDebug(progress12 <= 12)

        let imageName = String(format: "timer-%02ld-12", progress12 * 5)
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Missing icon.")
            return nil
        }
        owsAssertDebug(image.size.width == Self.layoutSize)
        owsAssertDebug(image.size.height == Self.layoutSize)
        return image
    }

    private func startAnimation() {
        AssertIsOnMainThread()

        clearAnimation()

        let animationTimer = Timer.weakTimer(withTimeInterval: 0.1,
                                              target: self,
                                              selector: #selector(updateProgress12),
                                              userInfo: nil,
                                              repeats: true)
        self.animationTimer = animationTimer
        RunLoop.main.add(animationTimer, forMode: .common)
    }

    private func clearAnimation() {
        AssertIsOnMainThread()

        animationTimer?.invalidate()
        animationTimer = nil
    }

    public func prepareForReuse() {
        clearAnimation()
        imageView.image = nil
        configuration = nil
    }

    public static var measureSize: CGSize {
        .square(Self.layoutSize)
    }
}
