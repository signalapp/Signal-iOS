//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

class ContactReminderTableViewCell: UITableViewCell {

    private let learnMoreAction: () -> Void
    private let dismissAction: () -> Void

    init(learnMoreAction: @escaping () -> Void, dismissAction: @escaping () -> Void) {
        self.learnMoreAction = learnMoreAction
        self.dismissAction = dismissAction

        super.init(style: .default, reuseIdentifier: nil)

        contentView.addSubview(contentContainer)
        contentContainer.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var textColor: UIColor {
        Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_gray90
    }

    private lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .dynamicTypeBody2
        label.textColor = textColor
        label.text = OWSLocalizedString(
            "LINKED_DEVICE_MANAGE_CONTACTS_BANNER",
            comment: "Shown in a banner when you tap the 'New Chat' icon at the top of the list of chats."
        )
        return label
    }()

    private lazy var learnMoreButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(
            OWSLocalizedString(
                "LINKED_DEVICE_MANAGE_CONTACTS_LEARN_MORE",
                comment: "A button shown in a banner when you tap the 'New Chat' icon at the top of the list of chats. Tapping it opens a website with more details."),
            for: .normal
        )
        button.setTitleColor(textColor, for: .normal)
        button.titleLabel!.font = .dynamicTypeBody2.semibold()
        button.addTarget(self, action: #selector(didTapLearnMore), for: .touchUpInside)
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 0, bottom: 3, right: 0)
        button.setCompressionResistanceHigh()
        return button
    }()

    private lazy var contactIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.setTemplateImageName("contact-outline-32", tintColor: textColor)
        imageView.autoSetDimensions(to: CGSize(square: 24))
        return imageView
    }()

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTemplateImageName("x-20", tintColor: textColor)
        button.addTarget(self, action: #selector(didTapDismiss), for: .touchUpInside)
        button.setCompressionResistanceHigh()
        return button
    }()

    private lazy var labelContainer: UIView = {
        let stackView = UIStackView(arrangedSubviews: [messageLabel, learnMoreButton])
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6
        return stackView
    }()

    private lazy var contentContainer: UIView = {
        let stackView = UIStackView(arrangedSubviews: [contactIcon, labelContainer, closeButton])
        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.spacing = 12
        return stackView
    }()

    @objc
    private func didTapLearnMore() {
        learnMoreAction()
    }

    @objc
    private func didTapDismiss() {
        dismissAction()
    }
}

extension ContactReminderTableViewCell: CustomBackgroundColorCell {
    func customBackgroundColor(forceDarkMode: Bool) -> UIColor {
        (forceDarkMode || Theme.isDarkThemeEnabled) ? .ows_gray80 : .ows_gray12
    }

    func customSelectedBackgroundColor(forceDarkMode: Bool) -> UIColor {
        customBackgroundColor(forceDarkMode: forceDarkMode)
    }
}
