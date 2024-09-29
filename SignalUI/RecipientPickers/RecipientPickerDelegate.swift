//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public enum RecipientPickerRecipientState: Int {
    case canBeSelected
    case duplicateGroupMember
    case userAlreadyInBlocklist
    case conversationAlreadyInBlocklist
    case unknownError
}

public protocol RecipientPickerDelegate: RecipientContextMenuHelperDelegate {
    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        getRecipientState recipient: PickedRecipient
    ) -> RecipientPickerRecipientState

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        didSelectRecipient recipient: PickedRecipient
    )

    /// This delegate method is only used if shouldUseAsyncSelection is set.
    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        prepareToSelectRecipient recipient: PickedRecipient
    ) -> Promise<Void>

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryMessageForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> String?

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryViewForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> ContactCellAccessoryView?

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        attributedSubtitleForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> NSAttributedString?

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        shouldAllowUserInteractionForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> Bool

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController)

    func recipientPickerNewGroupButtonWasPressed()

    func recipientPickerCustomHeaderViews() -> [UIView]

    var shouldShowQRCodeButton: Bool { get }
    func openUsernameQRCodeScanner()
}

public extension RecipientPickerDelegate {

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        prepareToSelectRecipient recipient: PickedRecipient
    ) -> Promise<Void> {
        owsFailDebug("Not implemented")
        return Promise.value(())
    }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryMessageForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction) -> String? { nil }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryViewForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> ContactCellAccessoryView? { nil }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        attributedSubtitleForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> NSAttributedString? { nil }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        shouldAllowUserInteractionForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> Bool { false }

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController) {}

    func recipientPickerNewGroupButtonWasPressed() {}

    func recipientPickerCustomHeaderViews() -> [UIView] { [] }
}

public class PickedRecipient: Hashable {

    public let identifier: Identifier
    public enum Identifier: Hashable {
        case address(_ address: SignalServiceAddress)
        case group(_ groupThread: TSGroupThread)
    }

    private init(_ identifier: Identifier) {
        self.identifier = identifier
    }

    public var isGroup: Bool {
        guard case .group = identifier else { return false }
        return true
    }

    public var address: SignalServiceAddress? {
        guard case .address(let address) = identifier else { return nil }
        return address
    }

    public static func `for`(groupThread: TSGroupThread) -> PickedRecipient {
        return .init(.group(groupThread))
    }

    public static func `for`(address: SignalServiceAddress) -> PickedRecipient {
        return .init(.address(address))
    }

    public static func == (lhs: PickedRecipient, rhs: PickedRecipient) -> Bool {
        return lhs.identifier == rhs.identifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}
