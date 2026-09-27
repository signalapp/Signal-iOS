//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class SelectContactForSharingViewController: RecipientPickerContainerViewController, RecipientPickerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SELECT_CONTACT_FOR_SHARING_VIEW_TITLE",
            comment: "Title for the 'Select Contact' view",
        )

        recipientPicker.allowsAddByAddress = false
        recipientPicker.groupsToShow = .noGroups
        recipientPicker.searchBarPlaceholderTitle = OWSLocalizedString(
            "SELECT_CONTACT_FOR_SHARING_SEARCH_BAR_PLACEHOLDER",
            comment: "Placeholder text for the search bar on the 'Select Contact' view",
        )
        recipientPicker.delegate = self

        addRecipientPicker()

        navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
    }

    // MARK: - RecipientPickerDelegate

    func recipientPicker(
        _ recipientPickerViewController: SignalUI.RecipientPickerViewController,
        selectionStyleForRecipient recipient: SignalUI.PickedRecipient,
        transaction: SignalServiceKit.DBReadTransaction,
    ) -> UITableViewCell.SelectionStyle {
        .default
    }

    func recipientPicker(_ recipientPickerViewController: SignalUI.RecipientPickerViewController, didSelectRecipient recipient: SignalUI.PickedRecipient) {
    }

    var shouldShowQRCodeButton: Bool {
        false
    }

    func openUsernameQRCodeScanner() {
    }
}
