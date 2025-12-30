//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class BlockingLegacyGroupView: ConversationBottomPanelView {

    private weak var fromViewController: UIViewController?

    init(fromViewController: UIViewController) {
        self.fromViewController = fromViewController

        super.init(frame: .zero)

        let format = OWSLocalizedString(
            "LEGACY_GROUP_UNSUPPORTED_MESSAGE",
            comment: "Message explaining that this group can no longer be used because it is unsupported. Embeds a {{ learn more link }}.",
        )
        let learnMoreText = CommonStrings.learnMore

        let attributedString = NSMutableAttributedString(string: String(format: format, learnMoreText))
        attributedString.setAttributes(
            [.foregroundColor: UIColor.Signal.link],
            forSubstring: learnMoreText,
        )

        let label = UILabel()
        label.font = .dynamicTypeSubheadlineClamped
        label.textColor = .Signal.secondaryLabel
        label.attributedText = attributedString
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .center
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapLearnMore)))
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        addConstraints([
            label.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            label.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    func didTapLearnMore() {
        guard let fromViewController = self.fromViewController else {
            owsFailDebug("Missing fromViewController.")
            return
        }

        fromViewController.presentFormSheet(
            LegacyGroupLearnMoreViewController(mode: .explainUnsupportedLegacyGroups),
            animated: true,
        )
    }
}
