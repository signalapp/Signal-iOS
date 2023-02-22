//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

@objc
public protocol DisappearingTimerConfigurationViewDelegate: AnyObject {
    func disappearingTimerConfigurationViewWasTapped(_ disappearingTimerView: DisappearingTimerConfigurationView)
}

// DisappearingTimerConfigurationView shows a timer icon and a short label showing the duration
// of disappearing messages for a thread.
//
// If you assign a delegate, it behaves like a button.
@objc
public class DisappearingTimerConfigurationView: UIView {

    @objc
    public weak var delegate: DisappearingTimerConfigurationViewDelegate? {
        didSet {
            // gesture recognizer is only enabled when a delegate is assigned.
            // This lets us use this view as either an interactive button
            // or as a non-interactive status indicator
            pressGesture.isEnabled = delegate != nil
        }
    }

    private let imageView: UIImageView
    private let label: UILabel
    private var pressGesture: UILongPressGestureRecognizer!

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public init(durationSeconds: UInt32) {
        self.imageView = UIImageView(image: Theme.iconImage(.settingsTimer))
        imageView.contentMode = .scaleAspectFit

        self.label = UILabel()
        label.text = DateUtil.formatDuration(seconds: durationSeconds, useShortFormat: true)
        label.font = UIFont.systemFont(ofSize: 10)
        label.textAlignment = .center
        label.minimumScaleFactor = 0.5

        super.init(frame: CGRect.zero)

        applyTintColor(self.tintColor)

        // Gesture, simulating button touch up inside
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(pressHandler))
        gesture.minimumPressDuration = 0
        self.pressGesture = gesture
        self.addGestureRecognizer(pressGesture)

        // disable gesture recognizer until a delegate is assigned
        // this lets us use the UI as either an interactive button
        // or as a non-interactive status indicator
        pressGesture.isEnabled = false

        // Accessibility
        self.accessibilityLabel = OWSLocalizedString("DISAPPEARING_MESSAGES_LABEL", comment: "Accessibility label for disappearing messages")
        let hintFormatString = OWSLocalizedString("DISAPPEARING_MESSAGES_HINT", comment: "Accessibility hint that contains current timeout information")
        let durationString = String.formatDurationLossless(durationSeconds: durationSeconds)
        self.accessibilityHint = String(format: hintFormatString, durationString)

        // Layout
        self.addSubview(imageView)
        self.addSubview(label)

        let kHorizontalPadding: CGFloat = 4
        let kVerticalPadding: CGFloat = 6
        imageView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: kVerticalPadding, left: kHorizontalPadding, bottom: 0, right: kHorizontalPadding), excludingEdge: .bottom)
        label.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 0, left: kHorizontalPadding, bottom: kVerticalPadding, right: kHorizontalPadding), excludingEdge: .top)
        label.autoPinEdge(.top, to: .bottom, of: imageView)
    }

    @objc
    func pressHandler(_ gestureRecognizer: UILongPressGestureRecognizer) {
        Logger.verbose("")

        // handle touch down and touch up events separately
        if gestureRecognizer.state == .began {
            applyTintColor(UIColor.gray)
        } else if gestureRecognizer.state == .ended {
            applyTintColor(self.tintColor)

            let location = gestureRecognizer.location(in: self)
            let isTouchUpInside = self.bounds.contains(location)

            if isTouchUpInside {
                // Similar to a UIButton's touch-up-inside
                self.delegate?.disappearingTimerConfigurationViewWasTapped(self)
            } else {
                // Similar to a UIButton's touch-up-outside

                // cancel gesture
                gestureRecognizer.isEnabled = false
                gestureRecognizer.isEnabled = true
            }
        }
    }

    override public var tintColor: UIColor! {
        didSet {
            applyTintColor(tintColor)
        }
    }

    private func applyTintColor(_ color: UIColor) {
        imageView.tintColor = color
        label.textColor = color
    }
}
