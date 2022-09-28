//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         willRenderRecipient recipient: PickedRecipient)

    // This delegate method is only used if showUseAsyncSelection is set.
    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         prepareToSelectRecipient recipient: PickedRecipient) -> AnyPromise

    // This delegate method is only used if showUseAsyncSelection is set.
    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         showInvalidRecipientAlert recipient: PickedRecipient)

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

@objc
extension RecipientPickerViewController {

    func tryToSelectRecipient(_ recipient: PickedRecipient) {
        if let address = recipient.address,
            address.isLocalAddress,
            shouldHideLocalRecipient {
            return
        }

        guard let delegate = delegate else { return }
        guard showUseAsyncSelection else {
            AssertIsOnMainThread()

            let recipientPickerRecipientState = delegate.recipientPicker(self, getRecipientState: recipient)
            guard recipientPickerRecipientState == .canBeSelected else {
                showErrorAlert(recipientPickerRecipientState: recipientPickerRecipientState)
                return
            }

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
                    AssertIsOnMainThread()
                    let recipientPickerRecipientState = delegate.recipientPicker(self, getRecipientState: recipient)
                    guard recipientPickerRecipientState == .canBeSelected else {
                        self.showErrorAlert(recipientPickerRecipientState: recipientPickerRecipientState)
                        return
                    }
                    delegate.recipientPicker(self, didSelectRecipient: recipient)
                }
            }.catch { error in
                AssertIsOnMainThread()
                owsFailDebug("Error: \(error)")
                modalActivityIndicator.dismiss {
                    OWSActionSheets.showErrorAlert(message: error.userErrorDescription)
                }
            }
        }
    }

    func showErrorAlert(recipientPickerRecipientState: RecipientPickerRecipientState) {
        let errorMessage: String
        switch recipientPickerRecipientState {
        case .duplicateGroupMember:
            errorMessage = OWSLocalizedString("GROUPS_ERROR_MEMBER_ALREADY_IN_GROUP",
                                              comment: "Error message indicating that a member can't be added to a group because they are already in the group.")
        case .userAlreadyInBlocklist:
            errorMessage = OWSLocalizedString("BLOCK_LIST_ERROR_USER_ALREADY_IN_BLOCKLIST",
                                              comment: "Error message indicating that a user can't be blocked because they are already blocked.")
        case .conversationAlreadyInBlocklist:
            errorMessage = OWSLocalizedString("BLOCK_LIST_ERROR_CONVERSATION_ALREADY_IN_BLOCKLIST",
                                              comment: "Error message indicating that a conversation can't be blocked because they are already blocked.")
        case .canBeSelected, .unknownError:
            owsFailDebug("Unexpected value.")
            errorMessage = OWSLocalizedString("RECIPIENT_PICKER_ERROR_USER_CANNOT_BE_SELECTED",
                                              comment: "Error message indicating that a user can't be selected.")
        }
        OWSActionSheets.showErrorAlert(message: errorMessage)
        return
    }

    func item(forRecipient recipient: PickedRecipient) -> OWSTableItem {

        switch recipient.identifier {
        case .address(let address):
            return OWSTableItem(
                customCellBlock: { [weak self] in
                    guard let self = self else { return UITableViewCell() }
                    let tableView = self.tableView
                    guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                        owsFailDebug("cell was unexpectedly nil")
                        return UITableViewCell()
                    }

                    if let delegate = self.delegate,
                       delegate.recipientPicker(self, getRecipientState: recipient) != .canBeSelected {
                        cell.selectionStyle = .none
                    }

                    Self.databaseStorage.read { transaction in
                        let configuration = ContactCellConfiguration(address: address, localUserDisplayMode: .noteToSelf)
                        if let delegate = self.delegate {
                            if let accessoryView = delegate.recipientPicker?(self,
                                                                             accessoryViewForRecipient: recipient,
                                                                             transaction: transaction) {
                                configuration.accessoryView = accessoryView
                            } else {
                                let accessoryMessage = delegate.recipientPicker(self,
                                                                                accessoryMessageForRecipient: recipient,
                                                                                transaction: transaction)
                                configuration.accessoryMessage = accessoryMessage
                            }

                            if let attributedSubtitle = delegate.recipientPicker?(self,
                                                                                  attributedSubtitleForRecipient: recipient,
                                                                                  transaction: transaction) {
                                configuration.attributedSubtitle = attributedSubtitle
                            }
                        }

                        cell.configure(configuration: configuration, transaction: transaction)
                    }

                    self.delegate?.recipientPicker(self, willRenderRecipient: recipient)

                    return cell
                },
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
                        if delegate.recipientPicker(self, getRecipientState: recipient) != .canBeSelected {
                            cell.selectionStyle = .none
                        }

                        cell.accessoryMessage = Self.databaseStorage.read { transaction in
                            delegate.recipientPicker(self,
                                                     accessoryMessageForRecipient: recipient,
                                                     transaction: transaction)
                        }
                    }

                    cell.configure(thread: groupThread)

                    return cell
                },
                actionBlock: { [weak self] in
                    self?.tryToSelectRecipient(recipient)
                }
            )
        }
    }
}
