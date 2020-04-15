//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
protocol RecipientPickerDelegate: AnyObject {
    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         canSelectRecipient recipient: PickedRecipient) -> Bool

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         didSelectRecipient recipient: PickedRecipient)

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         willRenderRecipient recipient: PickedRecipient)

    // This delegate method is only used if showUseAsyncSelection is set.
    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         prepareToSelectRecipient recipient: PickedRecipient) -> AnyPromise

    // This delegate method is only used if showUseAsyncSelection is set.
    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         showInvalidRecipientAlert recipient: PickedRecipient)

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         accessoryMessageForRecipient recipient: PickedRecipient) -> String?

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         accessoryViewForRecipient recipient: PickedRecipient) -> UIView?

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController)

    func recipientPickerNewGroupButtonWasPressed()
}

@objc
public class PickedRecipient: NSObject {
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

    public override func isEqual(_ object: Any?) -> Bool {
        guard let otherRecipient = object as? PickedRecipient else { return false }
        return identifier == otherRecipient.identifier
    }

    public override var hash: Int {
        return identifier.hashValue
    }
}

@objc
extension RecipientPickerViewController {

    func tryToSelectRecipient(_ recipient: PickedRecipient) {
        guard let delegate = delegate else { return }
        guard showUseAsyncSelection else {
            guard delegate.recipientPicker(self, canSelectRecipient: recipient) else { return }
            delegate.recipientPicker(self, didSelectRecipient: recipient)
            return
        }
        let fromViewController = self
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { [weak self] modalActivityIndicator in
            guard let self = self else { return }

            firstly {
                delegate.recipientPicker(fromViewController,
                                         prepareToSelectRecipient: recipient)
            }.done { _ in
                AssertIsOnMainThread()
                modalActivityIndicator.dismiss {
                    guard delegate.recipientPicker(self, canSelectRecipient: recipient) else { return }
                    delegate.recipientPicker(self, didSelectRecipient: recipient)
                }
            }.catch { error in
                AssertIsOnMainThread()
                owsFailDebug("Error: \(error)")
                modalActivityIndicator.dismiss {
                    delegate.recipientPicker(self, showInvalidRecipientAlert: recipient)
                }
            }.retainUntilComplete()
        }
    }

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

                        if let accessoryView = delegate.recipientPicker(self, accessoryViewForRecipient: recipient) {
                            cell.ows_setAccessoryView(accessoryView)
                        } else {
                            let accessoryMessage = delegate.recipientPicker(self, accessoryMessageForRecipient: recipient)
                            cell.setAccessoryMessage(accessoryMessage)
                        }
                    }

                    cell.configure(withRecipientAddress: address)

                    self.delegate?.recipientPicker(self, willRenderRecipient: recipient)

                    return cell
                },
                customRowHeight: UITableView.automaticDimension,
                actionBlock: { [weak self] in
                    self?.tryToSelectRecipient(recipient)
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
                    self?.tryToSelectRecipient(recipient)
                }
            )
        }
    }
}
