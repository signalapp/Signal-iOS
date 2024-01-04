//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

class UsernameLinkShareSheetViewController: OWSTableSheetViewController {

    private let usernameLink: Usernames.UsernameLink
    private let didCopyUsername: (() -> Void)?

    weak var dismissalDelegate: (any SheetDismissalDelegate)?

    init(
        usernameLink: Usernames.UsernameLink,
        didCopyUsername: (() -> Void)? = nil
    ) {
        self.usernameLink = usernameLink
        self.didCopyUsername = didCopyUsername
    }

    required init() {
        owsFail("Not implemented!")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        dismissalDelegate?.didDismissPresentedSheet()
    }

    // MARK: - Table contents

    override func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()

        let displayLinkSection = OWSTableSection(
            items: [
                .label(
                    withText: usernameLink.url.absoluteString,
                    accessoryType: .none
                )
            ],
            headerView: { () -> UIView in
                let label = UILabel()
                label.numberOfLines = 0
                label.lineBreakMode = .byWordWrapping
                label.font = .dynamicTypeFootnote
                label.textColor = Theme.secondaryTextAndIconColor
                label.textAlignment = .center
                label.layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 0)
                label.text = OWSLocalizedString(
                    "USERNAME_LINK_SHARE_SHEET_HEADER",
                    comment: "Text describing what you can do with a username link, on a sheet for sharing it."
                )

                let wrapper = UIView()
                wrapper.layoutMargins = UIEdgeInsets(hMargin: 24, vMargin: 20)
                wrapper.addSubview(label)

                label.autoPinEdgesToSuperviewMargins()

                return wrapper
            }()
        )

        let actionsSection = OWSTableSection(items: [
            .item(
                icon: .buttonCopy,
                name: OWSLocalizedString(
                    "USERNAME_LINK_SHARE_SHEET_COPY_LINK_ACTION",
                    comment: "Text for a tappable cell that copies the user's username link when selected."
                ),
                actionBlock: { [weak self] in
                    guard let self else { return }

                    UIPasteboard.general.url = self.usernameLink.url
                    self.didCopyUsername?()
                }
            ),
            .item(
                icon: .buttonShare,
                name: CommonStrings.shareButton,
                actionBlock: { [weak self] in
                    guard let self else { return }

                    ShareActivityUtil.present(
                        activityItems: [self.usernameLink.url],
                        from: self,
                        sourceView: self.view
                    )
                }
            )
        ])

        contents.add(sections: [
            displayLinkSection,
            actionsSection
        ])

        self.tableViewController.setContents(contents, shouldReload: shouldReload)
    }
}
