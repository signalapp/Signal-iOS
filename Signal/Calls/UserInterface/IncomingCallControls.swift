//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

class IncomingCallControls: UIView {
    private func createDeclineButton() -> CallButton {
        let accessibilityLabel = OWSLocalizedString(
            "CALL_VIEW_DECLINE_INCOMING_CALL_LABEL",
            comment: "label for declining incoming calls"
        )
        return createButton(
            iconName: "phone-down-fill-28",
            label: OWSLocalizedString("CALL_CONTROLS_INCOMING_DECLINE", comment: "label for button shown when an incoming call rings"),
            unselectedBackgroundColor: .ows_accentRed,
            accessibilityLabel: accessibilityLabel,
            action: self.didDeclineCall
        )
    }

    private func createAnswerAudioButton() -> CallButton {
        let accessibilityLabel = OWSLocalizedString(
            "CALL_VIEW_ACCEPT_INCOMING_CALL_LABEL",
            comment: "label for accepting incoming calls"
        )
        return createButton(
            iconName: "phone-fill-28",
            label: OWSLocalizedString("CALL_CONTROLS_INCOMING_ANSWER", comment: "label for button shown when an incoming call rings"),
            unselectedBackgroundColor: .ows_accentGreen,
            accessibilityLabel: accessibilityLabel,
            action: { self.didAcceptCall(false) }
        )
    }

    private func createAnswerVideoButton() -> CallButton {
        let accessibilityLabel = OWSLocalizedString(
            "CALL_VIEW_ACCEPT_INCOMING_CALL_LABEL",
            comment: "label for accepting incoming calls"
        )
        return createButton(
            iconName: "video-fill-28",
            label: OWSLocalizedString("CALL_CONTROLS_INCOMING_ANSWER", comment: "label for button shown when an incoming call rings"),
            unselectedBackgroundColor: .ows_accentGreen,
            accessibilityLabel: accessibilityLabel,
            action: { self.didAcceptCall(true) }
        )
    }

    private func createAnswerWithoutVideoButton() -> CallButton {
        let accessibilityLabel = OWSLocalizedString(
            "CALL_VIEW_ACCEPT_INCOMING_CALL_AUDIO_ONLY_LABEL",
            comment: "label for accepting incoming video calls as audio only"
        )
        return createButton(
            iconName: "video-slash-fill-28",
            // genstrings doesn't expand '\n' in a comment, so we don't need to escape the backslash.
            label: OWSLocalizedString("CALL_CONTROLS_INCOMING_ANSWER_WITHOUT_VIDEO", comment: "Label for button shown when an incoming call rings. This particular label has room for two lines; you may insert a manual linebreak with '\n' as long as both lines are 15 characters or shorter (8 fullwidth characters or shorter), as in the English translation."),
            accessibilityLabel: accessibilityLabel,
            action: { self.didAcceptCall(false) }
        )
    }

    private let didDeclineCall: () -> Void
    private let didAcceptCall: (_ hasVideo: Bool) -> Void

    init(isVideoCall: Bool, didDeclineCall: @escaping () -> Void, didAcceptCall: @escaping (_ hasVideo: Bool) -> Void) {
        self.didDeclineCall = didDeclineCall
        self.didAcceptCall = didAcceptCall

        super.init(frame: .zero)

        let primarySubviews: [UIView]
        let secondarySubview: UIView?
        if isVideoCall {
            secondarySubview = createAnswerWithoutVideoButton()
            primarySubviews = [createDeclineButton(), createAnswerVideoButton()]
        } else {
            secondarySubview = nil
            primarySubviews = [createDeclineButton(), createAnswerAudioButton()]
        }

        let bottomStack = UIStackView(arrangedSubviews: primarySubviews)
        bottomStack.axis = .horizontal
        bottomStack.alignment = .top
        bottomStack.distribution = .fillEqually

        let vStack = UIStackView(arrangedSubviews: [secondarySubview, bottomStack].compacted())
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
        unselectedBackgroundColor: UIColor? = nil, // default if nil
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) -> CallButton {
        let button = CallButton(iconName: iconName)
        button.addAction(UIAction(handler: { _ in action() }), for: .touchUpInside)
        button.alpha = 0.9
        button.text = label
        button.accessibilityLabel = accessibilityLabel
        if let unselectedBackgroundColor {
            button.unselectedBackgroundColor = unselectedBackgroundColor
        }
        return button
    }
}
