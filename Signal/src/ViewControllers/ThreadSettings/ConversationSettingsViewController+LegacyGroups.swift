//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import UIKit

class LegacyGroupView: UIView {

    private weak var viewController: UIViewController?

    required init(viewController: UIViewController) {
        self.viewController = viewController

        super.init(frame: .zero)
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let label = UILabel()

    private func configureLabel(format: String, highlightedSubstring: String) {
        let text = String(format: format, highlightedSubstring)

        let attributedString = NSMutableAttributedString(string: text)
        attributedString.setAttributes(
            [.foregroundColor: Theme.accentBlueColor],
            forSubstring: highlightedSubstring
        )

        label.attributedText = attributedString
    }

    private func configureDefaultLabelContents() {
        let format = OWSLocalizedString(
            "LEGACY_GROUP_UNSUPPORTED_MESSAGE",
            comment: "Message explaining that this group can no longer be used because it is unsupported. Embeds a {{ learn more link }}."
        )
        let learnMoreText = CommonStrings.learnMore

        configureLabel(format: format, highlightedSubstring: learnMoreText)

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                    action: #selector(didTapLearnMore)))
    }

    public func configure() {
        backgroundColor = Theme.secondaryBackgroundColor
        layer.cornerRadius = 4
        layoutMargins = UIEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)

        label.textColor = Theme.secondaryTextAndIconColor
        label.font = .dynamicTypeFootnote
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        addSubview(label)
        label.autoPinEdgesToSuperviewMargins()

        configureDefaultLabelContents()
    }

    // MARK: - Events

    @objc
    private func didTapLearnMore() {
        guard let viewController = viewController else {
            owsFailDebug("Missing viewController.")
            return
        }

        viewController.presentFormSheet(
            LegacyGroupLearnMoreViewController(mode: .explainUnsupportedLegacyGroups),
            animated: true
        )
    }
}
