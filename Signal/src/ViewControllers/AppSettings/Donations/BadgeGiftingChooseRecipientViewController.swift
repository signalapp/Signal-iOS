//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

class BadgeGiftingChooseRecipientViewController: OWSViewController {
    private let badge: ProfileBadge
    private let price: UInt
    private let currencyCode: Currency.Code

    private let recipientPicker = RecipientPickerViewController()

    private lazy var threadFinder: AnyThreadFinder = AnyThreadFinder()

    public init(badge: ProfileBadge, price: UInt, currencyCode: Currency.Code) {
        self.badge = badge
        self.price = price
        self.currencyCode = currencyCode
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("BADGE_GIFTING_CHOOSE_RECIPIENT_TITLE",
                                  comment: "Title on the screen where you choose a gift badge's recipient")

        recipientPicker.allowsAddByPhoneNumber = false
        recipientPicker.shouldHideLocalRecipient = true
        recipientPicker.allowsSelectingUnregisteredPhoneNumbers = false
        recipientPicker.shouldShowGroups = false
        recipientPicker.showUseAsyncSelection = false
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)
        recipientPicker.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .trailing)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .bottom)

        rerender()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        recipientPicker.applyTheme(to: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        recipientPicker.removeTheme(from: self)
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
    private enum RecipientGiftMode {
        case invalidRecipient
        case cannotReceiveGifts
        case canReceiveGifts
    }

    private func getRecipientGiftMode(_ recipient: PickedRecipient) -> RecipientGiftMode {
        guard let address = recipient.address, address.isValid, !address.isLocalAddress else {
            owsFailDebug("Invalid recipient. Did a group make its way in?")
            return .invalidRecipient
        }

        // TODO (GB): Properly respect capabilities.
        return .canReceiveGifts
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         canSelectRecipient recipient: PickedRecipient) -> RecipientPickerRecipientState {
        switch getRecipientGiftMode(recipient) {
        case .invalidRecipient:
            return .unknownError
        case .cannotReceiveGifts:
            // TODO (GB): Return a better error here.
            return .unknownError
        case .canReceiveGifts:
            return .canBeSelected
        }
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         didSelectRecipient recipient: PickedRecipient) {
        switch getRecipientGiftMode(recipient) {
        case .invalidRecipient, .cannotReceiveGifts:
            owsFail("Invalid recipient. Can this recipient receive gifts?")
        case .canReceiveGifts:
            guard let address = recipient.address else {
                owsFail("Recipient is missing address, but we expected one")
            }

            let recipientName = databaseStorage.read { transaction -> String in
                contactsManager.displayName(for: address, transaction: transaction)
            }
            let vc = BadgeGiftingConfirmationViewController(badge: badge,
                                                            price: price,
                                                            currencyCode: currencyCode,
                                                            recipientAddress: address,
                                                            recipientName: recipientName)
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         willRenderRecipient recipient: PickedRecipient) {}

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         prepareToSelectRecipient recipient: PickedRecipient) -> AnyPromise {
        return AnyPromise(Promise.value(()))
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         showInvalidRecipientAlert recipient: PickedRecipient) {}

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         accessoryMessageForRecipient recipient: PickedRecipient,
                         transaction: SDSAnyReadTransaction) -> String? { nil }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         attributedSubtitleForRecipient recipient: PickedRecipient,
                         transaction: SDSAnyReadTransaction) -> NSAttributedString? {
        switch getRecipientGiftMode(recipient) {
        case .invalidRecipient, .cannotReceiveGifts:
            return NSLocalizedString("BADGE_GIFTING_CANNOT_SEND_BADGE_SUBTITLE",
                                     comment: "Indicates that a contact cannot receive badges because they need to update Signal").attributedString()
        case .canReceiveGifts:
            return nil
        }
    }

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController) {}

    func recipientPickerNewGroupButtonWasPressed() {}

    func recipientPickerCustomHeaderViews() -> [UIView] { [] }
}
