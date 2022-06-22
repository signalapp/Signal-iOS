//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

class BadgeGiftingChooseRecipientViewController: OWSViewController {
    private let badge: ProfileBadge
    private let price: UInt
    private let currencyCode: Currency.Code

    private let recipientPicker = RecipientPickerViewController()

    private var canReceiveGiftBadgesCache: [SignalServiceAddress: Bool] = [:]

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

    private static func getRecipientAddress(_ recipient: PickedRecipient) -> SignalServiceAddress? {
        guard let address = recipient.address, address.isValid, !address.isLocalAddress else {
            owsFailDebug("Invalid recipient. Did a group make its way in?")
            return nil
        }
        return address
    }

    private func getCachedGiftMode(_ address: SignalServiceAddress) -> RecipientGiftMode? {
        guard let cached = canReceiveGiftBadgesCache[address] else { return nil }
        return cached ? .canReceiveGifts : .cannotReceiveGifts
    }

    private func fetchGiftMode(_ address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> RecipientGiftMode {
        guard let profile = self.profileManager.getUserProfile(for: address, transaction: transaction) else {
            owsFailDebug("Invalid recipient. I can't find a profile for this address")
            return .invalidRecipient
        }
        let canReceiveGiftBadges = profile.canReceiveGiftBadges
        canReceiveGiftBadgesCache[address] = canReceiveGiftBadges
        return canReceiveGiftBadges ? .canReceiveGifts : .cannotReceiveGifts
    }

    private func getRecipientGiftMode(_ recipient: PickedRecipient, transaction: SDSAnyReadTransaction) -> RecipientGiftMode {
        guard let address = Self.getRecipientAddress(recipient) else { return .invalidRecipient }
        return getCachedGiftMode(address) ?? fetchGiftMode(address, transaction: transaction)
    }

    private func getRecipientGiftModeWithSneakyTransaction(_ recipient: PickedRecipient) -> RecipientGiftMode {
        guard let address = Self.getRecipientAddress(recipient) else { return .invalidRecipient }
        return getCachedGiftMode(address) ?? self.databaseStorage.read { fetchGiftMode(address, transaction: $0) }
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         getRecipientState recipient: PickedRecipient) -> RecipientPickerRecipientState {
        switch getRecipientGiftModeWithSneakyTransaction(recipient) {
        case .invalidRecipient:
            return .unknownError
        case .cannotReceiveGifts:
            return .userLacksGiftBadgeCapability
        case .canReceiveGifts:
            return .canBeSelected
        }
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         didSelectRecipient recipient: PickedRecipient) {
        switch getRecipientGiftModeWithSneakyTransaction(recipient) {
        case .invalidRecipient, .cannotReceiveGifts:
            owsFail("Invalid recipient. Can this recipient receive gifts?")
        case .canReceiveGifts:
            guard let address = recipient.address else {
                owsFail("Recipient is missing address, but we expected one")
            }

            let thread = databaseStorage.write { TSContactThread.getOrCreateThread(withContactAddress: address, transaction: $0) }
            let vc = BadgeGiftingConfirmationViewController(badge: badge,
                                                            price: price,
                                                            currencyCode: currencyCode,
                                                            thread: thread)
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
        switch getRecipientGiftMode(recipient, transaction: transaction) {
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
