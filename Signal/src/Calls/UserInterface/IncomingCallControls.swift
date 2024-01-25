//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

@objc
protocol IncomingCallControlsDelegate: AnyObject {
    /// The sender's `tag` will match one of the cases of `IncomingCallControls.VideoEnabledTag`.
    func didAcceptIncomingCall(sender: UIButton)
    func didDeclineIncomingCall()
}

class IncomingCallControls: UIView {
    enum VideoEnabledTag: Int {
        case disabled = 0
        case enabled = 1
    }

    private lazy var declineButton: CallButton = {
        let accessibilityLabel = OWSLocalizedString(
            "CALL_VIEW_DECLINE_INCOMING_CALL_LABEL",
            comment: "label for declining incoming calls"
        )
        let button = createButton(
            iconName: "phone-down-fill-28",
            label: OWSLocalizedString("CALL_CONTROLS_INCOMING_DECLINE", comment: "label for button shown when an incoming call rings"),
            accessibilityLabel: accessibilityLabel,
            action: #selector(IncomingCallControlsDelegate.didDeclineIncomingCall)
        )
        button.unselectedBackgroundColor = .ows_accentRed
        return button
    }()
    private lazy var answerAudioButton: CallButton = {
        let accessibilityLabel = OWSLocalizedString(
            "CALL_VIEW_ACCEPT_INCOMING_CALL_LABEL",
            comment: "label for accepting incoming calls"
        )
        let button = createButton(
            iconName: "phone-fill-28",
            label: OWSLocalizedString("CALL_CONTROLS_INCOMING_ANSWER", comment: "label for button shown when an incoming call rings"),
            accessibilityLabel: accessibilityLabel,
            action: #selector(IncomingCallControlsDelegate.didAcceptIncomingCall(sender:))
        )
        button.unselectedBackgroundColor = .ows_accentGreen
        button.tag = VideoEnabledTag.disabled.rawValue
        return button
    }()
    private lazy var answerVideoButton: CallButton = {
        let accessibilityLabel = OWSLocalizedString(
            "CALL_VIEW_ACCEPT_INCOMING_CALL_LABEL",
            comment: "label for accepting incoming calls"
        )
        let button = createButton(
            iconName: "video-fill-28",
            label: OWSLocalizedString("CALL_CONTROLS_INCOMING_ANSWER", comment: "label for button shown when an incoming call rings"),
            accessibilityLabel: accessibilityLabel,
            action: #selector(IncomingCallControlsDelegate.didAcceptIncomingCall(sender:))
        )
        button.unselectedBackgroundColor = .ows_accentGreen
        button.tag = VideoEnabledTag.enabled.rawValue
        return button
    }()
    private lazy var answerWithoutVideoButton: CallButton = {
        let accessibilityLabel = OWSLocalizedString(
            "CALL_VIEW_ACCEPT_INCOMING_CALL_AUDIO_ONLY_LABEL",
            comment: "label for accepting incoming video calls as audio only"
        )
        let button = createButton(
            iconName: "video-slash-fill-28",
            // genstrings doesn't expand '\n' in a comment, so we don't need to escape the backslash.
            label: OWSLocalizedString("CALL_CONTROLS_INCOMING_ANSWER_WITHOUT_VIDEO", comment: "Label for button shown when an incoming call rings. This particular label has room for two lines; you may insert a manual linebreak with '\n' as long as both lines are 15 characters or shorter (8 fullwidth characters or shorter), as in the English translation."),
            accessibilityLabel: accessibilityLabel,
            action: #selector(IncomingCallControlsDelegate.didAcceptIncomingCall(sender:))
        )
        button.tag = VideoEnabledTag.disabled.rawValue
        return button
    }()

    private weak var delegate: IncomingCallControlsDelegate!

    init(video: Bool, delegate: IncomingCallControlsDelegate) {
        self.delegate = delegate
        super.init(frame: .zero)

        if video {
            answerAudioButton.isHidden = true
        } else {
            answerVideoButton.isHidden = true
            answerWithoutVideoButton.isHidden = true
        }

        let bottomStack = UIStackView(arrangedSubviews: [declineButton, answerAudioButton, answerVideoButton])
        bottomStack.axis = .horizontal
        bottomStack.alignment = .top
        bottomStack.distribution = .fillEqually

        let vStack = UIStackView(arrangedSubviews: [answerWithoutVideoButton, bottomStack])
        vStack.axis = .vertical
        vStack.spacing = 12

        addSubview(vStack)

        // Keep the buttons in a triangle on iPads by limiting the total width.
        // 430pt is the width of the iPhone 14 Pro Max.
        // Even if Apple makes a larger phone, we can probably still leave this.
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            vStack.autoPinWidthToSuperview()
        }
        vStack.autoSetDimension(.width, toSize: 430, relation: .lessThanOrEqual)
        vStack.autoAlignAxis(toSuperviewAxis: .vertical)

        NSLayoutConstraint.autoSetPriority(.defaultHigh - 1) {
            vStack.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 56)
        }
        vStack.autoPinEdge(toSuperviewEdge: .top)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func createButton(
        iconName: String,
        label: String? = nil,
        accessibilityLabel: String? = nil,
        action: Selector
    ) -> CallButton {
        let button = CallButton(iconName: iconName)
        button.addTarget(delegate, action: action, for: .touchUpInside)
        button.alpha = 0.9
        button.text = label
        button.accessibilityLabel = accessibilityLabel
        return button
    }
}
