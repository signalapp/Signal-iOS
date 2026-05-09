//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class LegacyGroupView: UIView {

    private weak var viewController: UIViewController?

    init(viewController: UIViewController) {
        self.viewController = viewController

        super.init(frame: .zero)
    }

    @available(*, unavailable, message: "use other init() instead.")
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let label = UILabel()

    private func configureLabel(format: String, highlightedSubstring: String) {
        let text = String.nonPluralLocalizedStringWithFormat(format, highlightedSubstring)

        let attributedString = NSMutableAttributedString(string: text)
        attributedString.setAttributes(
            [.foregroundColor: Theme.accentBlueColor],
            forSubstring: highlightedSubstring,
        )

        label.attributedText = attributedString
    }

    private func configureDefaultLabelContents() {
        let format = OWSLocalizedString(
            "LEGACY_GROUP_UNSUPPORTED_MESSAGE",
            comment: "Message explaining that this group can no longer be used because it is unsupported. Embeds a {{ learn more link }}.",
        )
        let learnMoreText = CommonStrings.learnMore

        configureLabel(format: format, highlightedSubstring: learnMoreText)

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(didTapLearnMore),
        ))
    }

    func configure() {
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
        guard let viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        LegacyGroupLearnMoreUI.presentActionSheet(for: .explainUnsupportedLegacyGroups, from: viewController)
    }
}

enum LegacyGroupLearnMoreUI {

    enum Mode {
        case explainUnsupportedLegacyGroups
        case explainNewGroups

        var titleString: String {
            switch self {
            case .explainUnsupportedLegacyGroups:
                return OWSLocalizedString(
                    "LEGACY_GROUP_UNSUPPORTED_LEARN_MORE_TITLE",
                    comment: "Title for a sheet explaining details about 'Legacy Groups'.",
                )
            case .explainNewGroups:
                return OWSLocalizedString(
                    "LEGACY_GROUP_WHAT_ARE_NEW_GROUPS_TITLE",
                    comment: "Title for a sheet explaining details about 'New Groups'.",
                )
            }
        }

        var bodyString: String {
            switch self {
            case .explainUnsupportedLegacyGroups:
                return OWSLocalizedString(
                    "LEGACY_GROUP_UNSUPPORTED_LEARN_MORE_BODY",
                    comment: "Text in a sheet explaining details about 'Legacy Groups'.",
                )
            case .explainNewGroups:
                return OWSLocalizedString(
                    "LEGACY_GROUP_WHAT_ARE_NEW_GROUPS_BODY",
                    comment: "Text in a sheet explaining details about 'New Groups'.",
                )
            }
        }
    }

    static func presentActionSheet(for mode: Mode, from viewController: UIViewController) {
        let actionSheet = ActionSheetController(title: mode.titleString, message: mode.bodyString)
        actionSheet.addAction(
            ActionSheetAction(
                title: CommonStrings.okayButton,
                style: .cancel,
            ),
        )
        viewController.present(actionSheet, animated: true)
    }
}
