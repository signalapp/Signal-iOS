//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// MARK: - ProfileDetailLabel

public class ProfileDetailLabel: UIStackView {
    private let tapAction: (() -> Void)?
    private let longPressAction: (() -> Void)?

    public init(
        title: String,
        icon: ThemeIcon,
        showDetailDisclosure: Bool = false,
        tapAction: (() -> Void)? = nil,
        longPressAction: (() -> Void)? = nil
    ) {
        self.tapAction = tapAction
        self.longPressAction = longPressAction

        super.init(frame: .zero)
        self.axis = .horizontal
        self.spacing = 12
        self.alignment = .top
        self.layoutMargins = .zero

        let font = UIFont.dynamicTypeBody
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Theme.primaryTextColor,
        ]

        // Make the icon an attributed string attachment so that it
        //  1. scales with Dynamic Type.
        //  2. is vertically centered with the first line of text
        //     when the stack view is horizontally aligned.
        let imageString = NSAttributedString.with(
            image: Theme.iconImage(icon),
            font: font,
            attributes: textAttributes
        )
        let imageLabel = UILabel()
        self.addArrangedSubview(imageLabel)
        imageLabel.attributedText = imageString
        imageLabel.setCompressionResistanceHigh()

        let textLabel = UILabel()
        self.addArrangedSubview(textLabel)
        let titleString = NSMutableAttributedString(
            string: title,
            attributes: textAttributes
        )

        if
            showDetailDisclosure,
            let chevron = UIImage(named: "chevron-right-20")
        {
            let attachmentString = NSAttributedString.with(
                image: chevron,
                font: font,
                attributes: textAttributes
            )
            titleString.append(attachmentString)
        }
        textLabel.attributedText = titleString
        textLabel.textAlignment = .natural
        textLabel.numberOfLines = 0

        if tapAction != nil {
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
        }
        if longPressAction != nil {
            addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(didLongPress)))
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func didTap() {
        tapAction?()
    }

    @objc
    private func didLongPress() {
        longPressAction?()
    }
}

// MARK: Convenience

public extension ProfileDetailLabel {
    static func profile(title: String) -> ProfileDetailLabel {
        .init(title: title, icon: .profileName)
    }

    static func profileAbout(bio: String) -> ProfileDetailLabel {
        .init(title: bio, icon: .profileAbout)
    }

    static func signalConnectionLink(
        shouldDismissOnNavigation: Bool,
        presentEducationFrom viewController: UIViewController?
    ) -> ProfileDetailLabel {
        .init(
            title: OWSLocalizedString(
                "CONTACT_ABOUT_SHEET_SIGNAL_CONNECTION_LABEL",
                comment: "A label indicating a user is a signal connection."
            ),
            icon: .contactInfoSignalConnection,
            showDetailDisclosure: true,
            tapAction: { [weak viewController] in
                func action() {
                    viewController?.present(ConnectionsEducationSheetViewController(), animated: true)
                }
                if shouldDismissOnNavigation {
                    viewController?.dismiss(animated: true, completion: action)
                } else {
                    action()
                }
            }
        )
    }

    static func inSystemContacts(name: String) -> ProfileDetailLabel {
        .init(
            title: String(
                format: OWSLocalizedString(
                    "CONTACT_ABOUT_SHEET_CONNECTION_IN_SYSTEM_CONTACTS",
                    comment: "Indicates that another account is in the user's system contacts. Embeds {{name}}"
                ),
                name
            ),
            icon: .contactInfoUserInContacts
        )
    }

    static func phoneNumber(
        _ phoneNumber: String,
        presentSuccessToastFrom viewController: UIViewController
    ) -> ProfileDetailLabel {
        let copyPhoneNumber: () -> Void = { [weak viewController] in
            UIPasteboard.general.string = phoneNumber
            viewController?.presentToast(text: OWSLocalizedString(
                "COPIED_TO_CLIPBOARD",
                comment: "Indicator that a value has been copied to the clipboard."
            ))
        }
        let formattedPhoneNumber = PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)

        return .init(
            title: formattedPhoneNumber,
            icon: .contactInfoPhone,
            tapAction: copyPhoneNumber,
            longPressAction: copyPhoneNumber
        )
    }

    static func mutualGroups(
        for thread: TSThread,
        mutualGroups: [TSGroupThread]
    ) -> ProfileDetailLabel {
        .init(
            title: mutualGroupsString(for: thread, mutualGroups: mutualGroups),
            icon: .contactInfoGroups
        )
    }

    static func mutualGroupsString(
        for thread: TSThread,
        mutualGroups: [TSGroupThread]
    ) -> String {
        switch (thread, mutualGroups.count) {
        case (_, 2...):
            let formatString = OWSLocalizedString(
                "MANY_GROUPS_IN_COMMON_%d", tableName: "PluralAware",
                comment: "A string describing that the user has many groups in common with another user. Embeds {{common group count}}")
            return String.localizedStringWithFormat(formatString, mutualGroups.count)

        case (is TSContactThread, 1):
            let formatString = OWSLocalizedString(
                "THREAD_DETAILS_ONE_MUTUAL_GROUP",
                comment: "A string indicating a mutual group the user shares with this contact. Embeds {{mutual group name}}")
            return String(format: formatString, mutualGroups[0].groupNameOrDefault)

        case (is TSGroupThread, 1):
            return OWSLocalizedString(
                "NO_OTHER_GROUPS_IN_COMMON",
                comment: "A string describing that the user has no groups in common other than the group implied by the current UI context")

        case (is TSContactThread, 0):
            return OWSLocalizedString(
                "NO_GROUPS_IN_COMMON",
                comment: "A string describing that the user has no groups in common with another user")

        default:
            owsFailDebug("Unexpected common group count")
            return ""
        }
    }
}
