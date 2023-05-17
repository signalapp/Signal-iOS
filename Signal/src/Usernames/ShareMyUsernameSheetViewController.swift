//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

class ShareMyUsernameSheetViewController: OWSTableSheetViewController {

    private enum CopyableValue {
        case string(value: String)
        case url(value: URL)

        var displayValue: String {
            switch self {
            case let .string(value):
                return value
            case let .url(value):
                return value.absoluteString
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .string:
                return "copy_item_string"
            case .url:
                return "copy_item_url"
            }
        }
    }

    // MARK: - Init

    private let username: String
    private let usernameLink: Usernames.UsernameLink

    init(
        username: String,
        usernameLink: Usernames.UsernameLink
    ) {
        self.username = username
        self.usernameLink = usernameLink
    }

    required init() {
        fatalError("Use other constructor!")
    }

    // MARK: - Table contents

    override func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()

        // Holds cells for copying the username as a string or URL.
        let copySection: OWSTableSection = {
            let section = OWSTableSection()

            section.add(self.buildCopyAndDismissTableItem(
                forCopyableValue: .string(value: username)
            ))

            section.add(self.buildCopyAndDismissTableItem(
                forCopyableValue: .url(value: usernameLink.asUrl)
            ))

            return section
        }()

        // Show some text explaining this view.
        copySection.customHeaderView = {
            let headerLabel: UILabel = {
                let label = UILabel()

                label.font = .dynamicTypeSubheadlineClamped
                label.textAlignment = .center
                label.textColor = Theme.secondaryTextAndIconColor
                label.numberOfLines = 0
                label.text = OWSLocalizedString(
                    "USERNAME_SHARE_SHEET_HEADER_TITLE",
                    value: "Copy or share a username link",
                    comment: "A header describing buttons that allow the user to copy or share their username."
                )

                return label
            }()

            let wrapperView: UIView = {
                let view = UIView()

                // Mimic the default cell insets, with special vertical margin
                // to work with the sheet.
                view.layoutMargins = self.tableViewController.cellOuterInsetsWithMargin(
                    top: 7,
                    bottom: 24
                )

                return view
            }()

            wrapperView.addSubview(headerLabel)
            headerLabel.autoPinEdgesToSuperviewMargins()

            return wrapperView
        }()

        // Holds a cell for opening the share sheet.
        let shareSection: OWSTableSection = {
            let section = OWSTableSection()

            section.add(.item(
                icon: .settingsShareUsername,
                name: CommonStrings.shareButton,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "share_button"),
                actionBlock: { [weak self] in
                    guard let self else { return }

                    AttachmentSharing.showShareUI(
                        for: self.usernameLink.asUrl,
                        sender: self.view,
                        completion: { [weak self] in
                            guard let self else { return }

                            self.dismiss(animated: true)
                        }
                    )
                }
            ))

            return section
        }()

        contents.addSections([
            copySection,
            shareSection
        ])

        self.tableViewController.setContents(contents, shouldReload: shouldReload)
    }

    /// Construct a table item that displays the given copyable value, and
    /// when tapped copies the value to the clipboard and dismisses this
    /// controller.
    private func buildCopyAndDismissTableItem(
        forCopyableValue copyable: CopyableValue
    ) -> OWSTableItem {
        .item(
            icon: .copy24,
            name: copyable.displayValue,
            maxNameLines: 2,
            accessibilityIdentifier: copyable.accessibilityIdentifier,
            actionBlock: { [weak self] in
                guard let self else { return }

                switch copyable {
                case let .string(value):
                    UIPasteboard.general.string = value
                case let .url(value):
                    UIPasteboard.general.url = value
                }

                self.dismiss(animated: true)
            }
        )
    }
}
