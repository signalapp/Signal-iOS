//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

/// Indicates that given chat has been configured with disappearing messages timer.
public class DisappearingMessagesChatIndicatorView: UIView {

    private let imageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "timer-compact"))
        imageView.contentMode = .center
        return imageView
    }()

    private let label: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeSubheadlineClamped
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.setCompressionResistanceHigh()
        label.setContentHuggingHigh()
        return label
    }()

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public init(durationSeconds: UInt32) {
        super.init(frame: CGRect.zero)

        tintColor = .Signal.secondaryLabel

        label.text = DateUtil.formatDuration(seconds: durationSeconds, useShortFormat: true)

        // Layout
        addSubview(imageView)
        addSubview(label)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),

            label.topAnchor.constraint(equalTo: topAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Accessibility
        accessibilityLabel = OWSLocalizedString("DISAPPEARING_MESSAGES_LABEL", comment: "Accessibility label for disappearing messages")
        let hintFormatString = OWSLocalizedString("DISAPPEARING_MESSAGES_HINT", comment: "Accessibility hint that contains current timeout information")
        let durationString = String.formatDurationLossless(durationSeconds: durationSeconds)
        accessibilityHint = String.nonPluralLocalizedStringWithFormat(hintFormatString, durationString)
    }

    override public var tintColor: UIColor! {
        didSet {
            applyTintColor()
        }
    }

    private func applyTintColor() {
        imageView.tintColor = tintColor
        label.textColor = tintColor
    }
}
