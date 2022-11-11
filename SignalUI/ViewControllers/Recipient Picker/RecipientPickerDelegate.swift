//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public enum RecipientPickerRecipientState: Int {
    case canBeSelected
    case duplicateGroupMember
    case userAlreadyInBlocklist
    case conversationAlreadyInBlocklist
    case unknownError
}

@objc
public protocol RecipientPickerDelegate: AnyObject {
    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         getRecipientState recipient: PickedRecipient) -> RecipientPickerRecipientState

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         didSelectRecipient recipient: PickedRecipient)

    // This delegate method is only used if shouldUseAsyncSelection is set.
    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         prepareToSelectRecipient recipient: PickedRecipient) -> AnyPromise

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         accessoryMessageForRecipient recipient: PickedRecipient,
                         transaction: SDSAnyReadTransaction) -> String?

    @objc
    optional func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                                  accessoryViewForRecipient recipient: PickedRecipient,
                                  transaction: SDSAnyReadTransaction) -> ContactCellAccessoryView?

    @objc
    optional func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                                  attributedSubtitleForRecipient recipient: PickedRecipient,
                                  transaction: SDSAnyReadTransaction) -> NSAttributedString?

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController)

    func recipientPickerNewGroupButtonWasPressed()

    func recipientPickerCustomHeaderViews() -> [UIView]
}

@objc
public class PickedRecipient: NSObject {
    public let identifier: Identifier
    public enum Identifier: Hashable {
        case address(_ address: SignalServiceAddress)
        case group(_ groupThread: TSGroupThread)
    }

    private init(_ identifier: Identifier) {
        self.identifier = identifier
    }

    @objc
    public var isGroup: Bool {
        guard case .group = identifier else { return false }
        return true
    }

    @objc
    public var address: SignalServiceAddress? {
        guard case .address(let address) = identifier else { return nil }
        return address
    }

    @objc
    public static func `for`(groupThread: TSGroupThread) -> PickedRecipient {
        return .init(.group(groupThread))
    }

    @objc
    public static func `for`(address: SignalServiceAddress) -> PickedRecipient {
        return .init(.address(address))
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let otherRecipient = object as? PickedRecipient else { return false }
        return identifier == otherRecipient.identifier
    }

    public override var hash: Int {
        return identifier.hashValue
    }
}
