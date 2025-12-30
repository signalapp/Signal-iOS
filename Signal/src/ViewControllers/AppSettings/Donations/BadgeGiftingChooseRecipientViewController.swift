//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class BadgeGiftingChooseRecipientViewController: RecipientPickerContainerViewController {
    typealias PaymentMethodsConfiguration = DonationSubscriptionConfiguration.PaymentMethodsConfiguration

    private let badge: ProfileBadge
    private let price: FiatMoney
    private let paymentMethodsConfiguration: PaymentMethodsConfiguration

    init(
        badge: ProfileBadge,
        price: FiatMoney,
        paymentMethodsConfiguration: PaymentMethodsConfiguration,
    ) {
        self.badge = badge
        self.price = price
        self.paymentMethodsConfiguration = paymentMethodsConfiguration
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.groupedBackground

        title = OWSLocalizedString(
            "DONATION_ON_BEHALF_OF_A_FRIEND_CHOOSE_RECIPIENT_TITLE",
            comment: "Title on the screen where you choose who you're going to donate on behalf of.",
        )

        recipientPicker.allowsAddByAddress = false
        recipientPicker.shouldHideLocalRecipient = true
        recipientPicker.groupsToShow = .noGroups
        recipientPicker.delegate = self

        addRecipientPicker()
    }
}

extension BadgeGiftingChooseRecipientViewController: RecipientPickerDelegate, UsernameLinkScanDelegate {

    private static func getRecipientAddress(_ recipient: PickedRecipient) -> SignalServiceAddress? {
        guard let address = recipient.address, address.isValid, !address.isLocalAddress else {
            owsFailBeta("Invalid recipient. Did a group make its way in?")
            return nil
        }
        return address
    }

    private static func isRecipientValid(_ recipient: PickedRecipient) -> Bool {
        getRecipientAddress(recipient) != nil
    }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        selectionStyleForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction,
    ) -> UITableViewCell.SelectionStyle {
        return Self.isRecipientValid(recipient) ? .default : .none
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController, didSelectRecipient recipient: PickedRecipient) {
        guard let address = Self.getRecipientAddress(recipient) else {
            let errorMessage = OWSLocalizedString(
                "RECIPIENT_PICKER_ERROR_USER_CANNOT_BE_SELECTED",
                comment: "Error message indicating that a user can't be selected.",
            )
            OWSActionSheets.showErrorAlert(message: errorMessage)
            return
        }
        let thread = SSKEnvironment.shared.databaseStorageRef.write { TSContactThread.getOrCreateThread(withContactAddress: address, transaction: $0) }
        let vc = BadgeGiftingConfirmationViewController(
            badge: badge,
            price: price,
            paymentMethodsConfiguration: paymentMethodsConfiguration,
            thread: thread,
        )
        self.navigationController?.pushViewController(vc, animated: true)
    }
}
