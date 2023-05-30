//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

class BlockingGroupMigrationView: UIStackView {

    private weak var fromViewController: UIViewController?

    init(fromViewController: UIViewController) {
        self.fromViewController = fromViewController

        super.init(frame: .zero)

        createContents()
    }

    private func createContents() {
        // We want the background to extend to the bottom of the screen
        // behind the safe area, so we add that inset to our bottom inset
        // instead of pinning this view to the safe area
        let safeAreaInset = safeAreaInsets.bottom

        autoresizingMask = .flexibleHeight

        axis = .vertical
        spacing = 11
        layoutMargins = UIEdgeInsets(top: 16, leading: 16, bottom: 20 + safeAreaInset, trailing: 16)
        isLayoutMarginsRelativeArrangement = true
        alignment = .fill

        let backgroundView = UIView()
        backgroundView.backgroundColor = Theme.backgroundColor
        addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()

        let format = OWSLocalizedString(
            "LEGACY_GROUP_UNSUPPORTED_MESSAGE",
            comment: "Message explaining that this group can no longer be used because it is unsupported. Embeds a {{ learn more link }}."
        )
        let learnMoreText = CommonStrings.learnMore

        let attributedString = NSMutableAttributedString(string: String(format: format, learnMoreText))
        attributedString.setAttributes(
            [.foregroundColor: Theme.accentBlueColor],
            forSubstring: learnMoreText
        )

        let label = UILabel()
        label.font = .dynamicTypeSubheadlineClamped
        label.textColor = Theme.secondaryTextAndIconColor
        label.attributedText = attributedString
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .center
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapLearnMore)))
        addArrangedSubview(label)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return .zero
    }

    @objc
    public func didTapLearnMore() {
        guard let fromViewController = self.fromViewController else {
            owsFailDebug("Missing fromViewController.")
            return
        }

        fromViewController.presentFormSheet(
            LegacyGroupLearnMoreViewController(mode: .explainUnsupportedLegacyGroups),
            animated: true
        )
    }
}
