//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

final class ContactSharingPermissionPromptView: UIView {

    private static let buttonSpacing: CGFloat = 12
    private static let textSpacing: CGFloat = 4
    private static let spacingAfterImage: CGFloat = 24
    private static let spacingBeforeButtons: CGFloat = 16
    private static let buttonContentInsets = NSDirectionalEdgeInsets(hMargin: 16, vMargin: 12)

    init(
        onDismiss: @escaping () -> Void,
        onAllowAccess: @escaping () -> Void,
    ) {
        super.init(frame: .zero)

        let imageView = UIImageView(image: UIImage(named: "contacts"))
        imageView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString(
            "SELECT_CONTACT_FOR_SHARING_PERMISSION_PROMPT_TITLE",
            comment: "Title of the prompt on the 'Select Contact' view that asks the user to allow access to their contacts.",
        )
        titleLabel.font = .dynamicTypeTitle3.semibold()
        titleLabel.textColor = .Signal.label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true

        let bodyLabel = UILabel()
        bodyLabel.text = OWSLocalizedString(
            "SELECT_CONTACT_FOR_SHARING_PERMISSION_PROMPT_BODY",
            comment: "Body of the prompt on the 'Select Contact' view that asks the user to allow access to their contacts.",
        )
        bodyLabel.font = .dynamicTypeSubheadline
        bodyLabel.textColor = .Signal.secondaryLabel
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        bodyLabel.adjustsFontForContentSizeCategory = true

        let dismissButton = Self.button(
            title: OWSLocalizedString(
                "SELECT_CONTACT_FOR_SHARING_PERMISSION_PROMPT_DISMISS_BUTTON",
                comment: "Button on the 'Select Contact' view's contacts permission prompt that hides the prompt.",
            ),
            action: onDismiss,
        )
        let allowAccessButton = Self.button(
            title: OWSLocalizedString(
                "SELECT_CONTACT_FOR_SHARING_PERMISSION_PROMPT_ALLOW_BUTTON",
                comment: "Button on the 'Select Contact' view's contacts permission prompt that asks iOS for access to the user's contacts.",
            ),
            action: onAllowAccess,
        )

        let buttonStack = UIStackView(arrangedSubviews: [dismissButton, allowAccessButton])
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = Self.buttonSpacing

        let stackView = UIStackView(arrangedSubviews: [imageView, titleLabel, bodyLabel, buttonStack])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = Self.textSpacing
        stackView.setCustomSpacing(Self.spacingAfterImage, after: imageView)
        stackView.setCustomSpacing(Self.spacingBeforeButtons, after: bodyLabel)

        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func button(title: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.smallSecondary(title: title)
        configuration.cornerStyle = .capsule
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeHeadlineClamped)
        configuration.contentInsets = Self.buttonContentInsets
        return UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
    }
}
