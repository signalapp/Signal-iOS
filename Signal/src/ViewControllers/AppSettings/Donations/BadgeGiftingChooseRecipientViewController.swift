//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class BadgeGiftingChooseRecipientViewController: RecipientPickerContainerViewController {
    private let badge: ProfileBadge
    private let price: FiatMoney

    public init(badge: ProfileBadge, price: FiatMoney) {
        self.badge = badge
        self.price = price
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("BADGE_GIFTING_CHOOSE_RECIPIENT_TITLE",
                                  comment: "Title on the screen where you choose a gift badge's recipient")

        recipientPicker.allowsAddByPhoneNumber = false
        recipientPicker.shouldHideLocalRecipient = true
        recipientPicker.groupsToShow = .showNoGroups
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)
        recipientPicker.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .trailing)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .bottom)

        rerender()
    }

    override func themeDidChange() {
        super.themeDidChange()
        rerender()
    }

    private func rerender() {
        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)
    }
}

extension BadgeGiftingChooseRecipientViewController: RecipientPickerDelegate {
    private static func getRecipientAddress(_ recipient: PickedRecipient) -> SignalServiceAddress? {
        guard let address = recipient.address, address.isValid, !address.isLocalAddress else {
            owsFailDebug("Invalid recipient. Did a group make its way in?")
            return nil
        }
        return address
    }

    private static func isRecipientValid(_ recipient: PickedRecipient) -> Bool {
        getRecipientAddress(recipient) != nil
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         getRecipientState recipient: PickedRecipient) -> RecipientPickerRecipientState {
        Self.isRecipientValid(recipient) ? .canBeSelected : .unknownError
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         didSelectRecipient recipient: PickedRecipient) {
        guard let address = Self.getRecipientAddress(recipient) else {
            owsFail("Recipient is missing address, but we expected one")
        }
        let thread = databaseStorage.write { TSContactThread.getOrCreateThread(withContactAddress: address, transaction: $0) }
        let vc = BadgeGiftingConfirmationViewController(badge: badge, price: price, thread: thread)
        self.navigationController?.pushViewController(vc, animated: true)
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         prepareToSelectRecipient recipient: PickedRecipient) -> AnyPromise {
        return AnyPromise(Promise.value(()))
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         accessoryMessageForRecipient recipient: PickedRecipient,
                         transaction: SDSAnyReadTransaction) -> String? { nil }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         attributedSubtitleForRecipient recipient: PickedRecipient,
                         transaction: SDSAnyReadTransaction) -> NSAttributedString? { nil }

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController) {}

    func recipientPickerNewGroupButtonWasPressed() {}

    func recipientPickerCustomHeaderViews() -> [UIView] { [] }
}
