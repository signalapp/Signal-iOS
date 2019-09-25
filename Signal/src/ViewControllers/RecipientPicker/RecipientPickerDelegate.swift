//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
protocol RecipientPickerDelegate: class {
    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        canSelectRecipient recipient: PickedRecipient
    ) -> Bool

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        didSelectRecipient recipient: PickedRecipient
    )

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryMessageForRecipient recipient: PickedRecipient
    ) -> String?

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController)
}

@objc
class PickedRecipient: NSObject {
    let identifier: Identifier
    enum Identifier: Hashable {
        case address(_ address: SignalServiceAddress)
        case group(_ groupThread: TSGroupThread)
    }

    private init(_ identifier: Identifier) {
        self.identifier = identifier
    }

    @objc
    var isGroup: Bool {
        guard case .group = identifier else { return false }
        return true
    }

    @objc
    var address: SignalServiceAddress? {
        guard case .address(let address) = identifier else { return nil }
        return address
    }

    @objc
    static func `for`(groupThread: TSGroupThread) -> PickedRecipient {
        return .init(.group(groupThread))
    }

    @objc
    static func `for`(address: SignalServiceAddress) -> PickedRecipient {
        return .init(.address(address))
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let otherRecipient = object as? PickedRecipient else { return false }
        return identifier == otherRecipient.identifier
    }

    override var hash: Int {
        return identifier.hashValue
    }
}

@objc
extension RecipientPickerViewController {
    func item(forRecipient recipient: PickedRecipient) -> OWSTableItem {
        switch recipient.identifier {
        case .address(let address):
            return OWSTableItem(
                customCellBlock: { [weak self] in
                    let cell = ContactTableViewCell()
                    guard let self = self else { return cell }

                    if let delegate = self.delegate {
                        if !delegate.recipientPicker(self, canSelectRecipient: recipient) {
                            cell.selectionStyle = .none
                        }

                        cell.setAccessoryMessage(delegate.recipientPicker(self, accessoryMessageForRecipient: recipient))
                    }

                    cell.configure(withRecipientAddress: address)

                    return cell
                },
                customRowHeight: UITableView.automaticDimension,
                actionBlock: { [weak self] in
                    guard let self = self, let delegate = self.delegate else { return }
                    guard delegate.recipientPicker(self, canSelectRecipient: recipient) else { return }
                    delegate.recipientPicker(self, didSelectRecipient: recipient)
                }
            )
        case .group(let groupThread):
            return OWSTableItem(
                customCellBlock: { [weak self] in
                    let cell = GroupTableViewCell()
                    guard let self = self else { return cell }

                    if let delegate = self.delegate {
                        if !delegate.recipientPicker(self, canSelectRecipient: recipient) {
                            cell.selectionStyle = .none
                        }

                        cell.accessoryMessage = delegate.recipientPicker(self, accessoryMessageForRecipient: recipient)
                    }

                    cell.configure(thread: groupThread)

                    return cell
                },
                customRowHeight: UITableView.automaticDimension,
                actionBlock: { [weak self] in
                    guard let self = self, let delegate = self.delegate else { return }
                    guard delegate.recipientPicker(self, canSelectRecipient: recipient) else { return }
                    delegate.recipientPicker(self, didSelectRecipient: recipient)
                }
            )
        }
    }
}
