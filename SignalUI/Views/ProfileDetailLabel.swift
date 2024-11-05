//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
public import SignalServiceKit

// MARK: - ProfileDetailLabel

public class ProfileDetailLabel: UIStackView {
    private let tapAction: (() -> Void)?
    private let longPressAction: (() -> Void)?

    public convenience init(
        title: String,
        icon: ThemeIcon,
        font: UIFont = .dynamicTypeBody,
        showDetailDisclosure: Bool = false,
        shouldLineWrap: Bool = true,
        tapAction: (() -> Void)? = nil,
        longPressAction: (() -> Void)? = nil
    ) {
        self.init(
            attributedTitle: NSMutableAttributedString(
                string: title,
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.Signal.label,
                ]
            ),
            icon: icon,
            font: font,
            showDetailDisclosure: showDetailDisclosure,
            shouldLineWrap: shouldLineWrap,
            tapAction: tapAction,
            longPressAction: longPressAction
        )
    }

    public init(
        attributedTitle: NSAttributedString,
        icon: ThemeIcon,
        font: UIFont = .dynamicTypeBody,
        showDetailDisclosure: Bool = false,
        shouldLineWrap: Bool = true,
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

        // Make the icon an attributed string attachment so that it
        //  1. scales with Dynamic Type.
        //  2. is vertically centered with the first line of text
        //     when the stack view is horizontally aligned.
        let imageString = NSAttributedString.with(
            image: Theme.iconImage(icon),
            font: font,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.Signal.label,
            ]
        )
        let imageLabel = UILabel()
        self.addArrangedSubview(imageLabel)
        imageLabel.attributedText = imageString
        imageLabel.setCompressionResistanceHigh()

        let textLabel = UILabel()
        self.addArrangedSubview(textLabel)
        let titleString = NSMutableAttributedString(attributedString: attributedTitle)

        if
            showDetailDisclosure,
            let chevron = UIImage(named: "chevron-right-20")
        {
            let attachmentString = NSAttributedString.with(
                image: chevron,
                font: font,
                attributes: [.foregroundColor: UIColor.Signal.secondaryLabel]
            )
            if shouldLineWrap {
                // Add the chevron at the end of the last line of text
                titleString.append(attachmentString)
            } else {
                // Add the chevron at the end of the truncated line
                let chevronLabel = UILabel()
                chevronLabel.attributedText = attachmentString
                chevronLabel.setCompressionResistanceHigh()
                self.addArrangedSubview(chevronLabel)
                self.addArrangedSubview(.hStretchingSpacer())
                self.setCustomSpacing(0, after: textLabel)
                self.setCustomSpacing(0, after: chevronLabel)
            }
        }
        textLabel.attributedText = titleString
        textLabel.textAlignment = .natural
        textLabel.numberOfLines = shouldLineWrap ? 0 : 1

        if tapAction != nil {
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
        }
        if longPressAction != nil {
            addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(didLongPress(sender:))))
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
    private func didLongPress(sender: UIGestureRecognizer) {
        guard sender.state == .began else { return }
        longPressAction?()
    }
}

// MARK: Convenience

public extension ProfileDetailLabel {
    static func profile(
        displayName: String,
        secondaryName: String? = nil,
        font: UIFont = .dynamicTypeBody,
        tapAction: (() -> Void)? = nil
    ) -> ProfileDetailLabel {
        .init(
            attributedTitle: {
                if let secondaryName {
                    return NSAttributedString.composed(of: [
                        displayName,
                        " ",
                        "(\(secondaryName))"
                            .styled(with: .color(UIColor.Signal.secondaryLabel))
                    ])
                } else {
                    return NSAttributedString.composed(of: [displayName])
                }
            }().styled(with: .font(font)),
            icon: .profileName,
            font: font,
            tapAction: tapAction
        )
    }

    static func verified(
        font: UIFont = .dynamicTypeBody
    ) -> ProfileDetailLabel {
        .init(title: SafetyNumberStrings.verified, icon: .contactInfoSafetyNumber, font: font)
    }

    static func profileAbout(
        bio: String,
        font: UIFont = .dynamicTypeBody
    ) -> ProfileDetailLabel {
        .init(title: bio, icon: .profileAbout, font: font)
    }

    static func signalConnectionLink(
        font: UIFont = .dynamicTypeBody,
        shouldDismissOnNavigation: Bool,
        presentEducationFrom viewController: UIViewController?,
        dismissalDelegate: (any SheetDismissalDelegate)? = nil
    ) -> ProfileDetailLabel {
        .init(
            title: OWSLocalizedString(
                "CONTACT_ABOUT_SHEET_SIGNAL_CONNECTION_LABEL",
                comment: "A label indicating a user is a signal connection."
            ),
            icon: .contactInfoSignalConnection,
            font: font,
            showDetailDisclosure: true,
            tapAction: { [weak viewController] in
                guard let viewController else { return }
                func action() {
                    let sheet = ConnectionsEducationSheetViewController()
                    sheet.overrideUserInterfaceStyle = viewController.overrideUserInterfaceStyle
                    sheet.dismissalDelegate = dismissalDelegate
                    viewController.present(sheet, animated: true)
                }
                if shouldDismissOnNavigation {
                    viewController.dismiss(animated: true, completion: action)
                } else {
                    action()
                }
            }
        )
    }

    static func noDirectChat(
        name: String,
        font: UIFont = .dynamicTypeBody
    ) -> ProfileDetailLabel {
        .init(
            title: String(
                format: OWSLocalizedString(
                    "CONTACT_ABOUT_SHEET_NO_DIRECT_MESSAGES",
                    comment: "Indicates that the user has no messages with the other account. Embeds {{name}}"
                ),
                name
            ),
            icon: .contactInfoNoDirectChat,
            font: font
        )
    }

    static func blocked(
        name: String,
        font: UIFont = .dynamicTypeBody
    ) -> ProfileDetailLabel {
        .init(
            title: String(
                format: OWSLocalizedString(
                    "CONTACT_ABOUT_SHEET_BLOCKED_USER_FORMAT",
                    comment: "Indicates that the user has blocked the other account. Embeds {{name}}"
                ),
                name
            ),
            icon: .chatSettingsBlock,
            font: font
        )
    }

    static func pendingRequest(
        name: String,
        font: UIFont = .dynamicTypeBody
    ) -> ProfileDetailLabel {
        .init(
            title: OWSLocalizedString(
                "CONTACT_ABOUT_SHEET_PENDING_REQUEST",
                comment: "Indicates that the user has a pending request with the other account. Embeds {{name}}"
            ),
            icon: .contactInfoPendingRequest,
            font: font
        )
    }

    static func inSystemContacts(
        name: String,
        font: UIFont = .dynamicTypeBody
    ) -> ProfileDetailLabel {
        .init(
            title: String(
                format: OWSLocalizedString(
                    "CONTACT_ABOUT_SHEET_CONNECTION_IN_SYSTEM_CONTACTS",
                    comment: "Indicates that another account is in the user's system contacts. Embeds {{name}}"
                ),
                name
            ),
            icon: .contactInfoUserInContacts,
            font: font
        )
    }

    static func phoneNumber(
        _ phoneNumber: String,
        font: UIFont = .dynamicTypeBody,
        presentSuccessToastFrom viewController: UIViewController?
    ) -> ProfileDetailLabel {
        let copyPhoneNumber: () -> Void = { [weak viewController] in
            UIPasteboard.general.string = phoneNumber
            viewController?.presentToast(text: OWSLocalizedString(
                "COPIED_TO_CLIPBOARD",
                comment: "Indicator that a value has been copied to the clipboard."
            ))
        }
        let formattedPhoneNumber = PhoneNumber.bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(phoneNumber)

        return .init(
            title: formattedPhoneNumber,
            icon: .contactInfoPhone,
            font: font,
            tapAction: copyPhoneNumber,
            longPressAction: copyPhoneNumber
        )
    }

    static func mutualGroups(
        for thread: TSThread,
        mutualGroups: [TSGroupThread],
        font: UIFont = .dynamicTypeBody
    ) -> ProfileDetailLabel {
        .init(
            title: mutualGroupsString(for: thread, mutualGroups: mutualGroups),
            icon: .contactInfoGroups,
            font: font
        )
    }

    static func note(
        _ noteText: String,
        font: UIFont = .dynamicTypeBody,
        onTap: () -> Void
    ) -> ProfileDetailLabel {
        .init(
            title: noteText,
            icon: .contactInfoNote
        )
    }

    static func mutualGroupsString(
        for thread: TSThread,
        mutualGroups: [TSGroupThread]
    ) -> String {
        mutualGroupsString(isInGroupContext: thread is TSGroupThread, mutualGroups: mutualGroups)
    }

    static func mutualGroupsString(
        isInGroupContext: Bool,
        mutualGroups: [TSGroupThread]
    ) -> String {
        switch (isInGroupContext, mutualGroups.count) {
        case (_, 2...):
            let formatString = OWSLocalizedString(
                "MANY_GROUPS_IN_COMMON_%d", tableName: "PluralAware",
                comment: "A string describing that the user has many groups in common with another user. Embeds {{common group count}}")
            return String.localizedStringWithFormat(formatString, mutualGroups.count)

        case (false, 1):
            let formatString = OWSLocalizedString(
                "THREAD_DETAILS_ONE_MUTUAL_GROUP",
                comment: "A string indicating a mutual group the user shares with this contact. Embeds {{mutual group name}}")
            return String(format: formatString, mutualGroups[0].groupNameOrDefault)

        case (true, 1):
            return OWSLocalizedString(
                "NO_OTHER_GROUPS_IN_COMMON",
                comment: "A string describing that the user has no groups in common other than the group implied by the current UI context")

        case (false, 0):
            return OWSLocalizedString(
                "NO_GROUPS_IN_COMMON",
                comment: "A string describing that the user has no groups in common with another user")

        default:
            owsFailDebug("Unexpected common group count")
            return ""
        }
    }
}
