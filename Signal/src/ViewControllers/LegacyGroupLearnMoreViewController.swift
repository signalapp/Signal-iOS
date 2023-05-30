//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

/// Presents information about legacy (V1) and new (V2) groups.
public class LegacyGroupLearnMoreViewController: InteractiveSheetViewController {

    public enum Mode {
        case explainUnsupportedLegacyGroups
        case explainNewGroups

        var titleString: String {
            switch self {
            case .explainUnsupportedLegacyGroups:
                return OWSLocalizedString(
                    "LEGACY_GROUP_UNSUPPORTED_LEARN_MORE_TITLE",
                    comment: "Title for a sheet explaining details about 'Legacy Groups'."
                )
            case .explainNewGroups:
                return OWSLocalizedString(
                    "LEGACY_GROUP_WHAT_ARE_NEW_GROUPS_TITLE",
                    comment: "Title for a sheet explaining details about 'New Groups'."
                )
            }
        }

        var bodyString: String {
            switch self {
            case .explainUnsupportedLegacyGroups:
                return OWSLocalizedString(
                    "LEGACY_GROUP_UNSUPPORTED_LEARN_MORE_BODY",
                    comment: "Text in a sheet explaining details about 'Legacy Groups'."
                )
            case .explainNewGroups:
                return OWSLocalizedString(
                    "LEGACY_GROUP_WHAT_ARE_NEW_GROUPS_BODY",
                    comment: "Text in a sheet explaining details about 'New Groups'."
                )
            }
        }
    }

    private let mode: Mode

    init(mode: Mode) {
        self.mode = mode

        super.init()
    }

    override public func viewDidLoad() {
        let textStackView: UIStackView = {
            func buildLabel(
                font: UIFont,
                alignment: NSTextAlignment,
                text: String
            ) -> UILabel {
                let label = UILabel()

                label.textColor = Theme.primaryTextColor
                label.numberOfLines = 0
                label.lineBreakMode = .byWordWrapping
                label.font = font
                label.text = text
                label.textAlignment = alignment

                return label
            }

            let stackView = UIStackView(arrangedSubviews: [
                buildLabel(
                    font: .dynamicTypeTitle2Clamped.semibold(),
                    alignment: .center,
                    text: mode.titleString
                ),
                UIView.spacer(withHeight: 20),
                buildLabel(
                    font: .dynamicTypeBodyClamped,
                    alignment: .left,
                    text: mode.bodyString
                )
            ])
            stackView.axis = .vertical
            stackView.alignment = .fill

            return stackView
        }()

        let textScrollView: UIScrollView = {
            let scrollView = UIScrollView()
            scrollView.addSubview(textStackView)
            textStackView.autoPinWidth(toWidthOf: scrollView)
            textStackView.heightAnchor.constraint(
                greaterThanOrEqualTo: scrollView.contentLayoutGuide.heightAnchor
            ).isActive = true

            return scrollView
        }()

        contentView.addSubview(textScrollView)
        textScrollView.autoPinLeadingToSuperviewMargin(withInset: 24)
        textScrollView.autoPinTrailingToSuperviewMargin(withInset: 24)
        textScrollView.autoPinTopToSuperviewMargin(withInset: 24)

        let okayButton: UIView = {
            let buttonFont = UIFont.dynamicTypeBodyClamped.semibold()
            let buttonHeight = OWSFlatButton.heightForFont(buttonFont)
            let button = OWSFlatButton.button(
                title: CommonStrings.okayButton,
                font: buttonFont,
                titleColor: .white,
                backgroundColor: .ows_accentBlue,
                target: self,
                selector: #selector(dismissAlert)
            )
            button.autoSetDimension(.height, toSize: buttonHeight)

            return button
        }()

        contentView.addSubview(okayButton)
        okayButton.autoPinEdge(.top, to: .bottom, of: textScrollView, withOffset: 24)
        okayButton.autoPinLeadingToSuperviewMargin(withInset: 24)
        okayButton.autoPinTrailingToSuperviewMargin(withInset: 24)
        okayButton.autoPinBottomToSuperviewMargin(withInset: 24)
    }

    override public func viewWillAppear(_ animated: Bool) {
        // Only use in maximized mode.
        maximizeHeight(animated: false) {
            self.minimizedHeight = self.maxHeight
        }
    }

    @objc
    private func dismissAlert() {
        dismiss(animated: true)
    }
}
