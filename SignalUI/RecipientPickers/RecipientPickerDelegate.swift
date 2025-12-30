//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public protocol RecipientPickerDelegate: RecipientContextMenuHelperDelegate {
    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        selectionStyleForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction,
    ) -> UITableViewCell.SelectionStyle

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        didSelectRecipient recipient: PickedRecipient,
    )

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryMessageForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction,
    ) -> String?

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryViewForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction,
    ) -> ContactCellAccessoryView?

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        attributedSubtitleForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction,
    ) -> NSAttributedString?

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        shouldAllowUserInteractionForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction,
    ) -> Bool

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController)

    func recipientPickerNewGroupButtonWasPressed()

    var shouldShowQRCodeButton: Bool { get }
    func openUsernameQRCodeScanner()
}

public extension RecipientPickerDelegate {
    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryMessageForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction,
    ) -> String? { nil }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryViewForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction,
    ) -> ContactCellAccessoryView? { nil }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        attributedSubtitleForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction,
    ) -> NSAttributedString? { nil }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        shouldAllowUserInteractionForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction,
    ) -> Bool { false }

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController) {}

    func recipientPickerNewGroupButtonWasPressed() {}
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

    public static func ==(lhs: PickedRecipient, rhs: PickedRecipient) -> Bool {
        return lhs.identifier == rhs.identifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}
