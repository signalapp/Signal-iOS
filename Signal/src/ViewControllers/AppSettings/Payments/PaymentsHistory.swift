//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
import SignalUI

// MARK: -

protocol PaymentsHistoryDataSourceDelegate: AnyObject {
    var recordType: PaymentsHistoryDataSource.RecordType { get }

    var maxRecordCount: Int? { get }

    func didUpdateContent()
}

// MARK: -

@MainActor
final class PaymentsHistoryDataSource {

    public enum RecordType: Int, CustomStringConvertible {
        case all = 0
        case incoming
        case outgoing

        public var description: String {
            switch self {
            case .all:
                return ".all"
            case .incoming:
                return ".incoming"
            case .outgoing:
                return ".outgoing"
            }
        }
    }

    // MARK: -

    weak var delegate: PaymentsHistoryDataSourceDelegate? {
        didSet {
            updateContent()
        }
    }

    public private(set) var items = [PaymentsHistoryItem]()

    public var hasItems: Bool {
        !items.isEmpty
    }

    public var count: Int {
        items.count
    }

    public init() {
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)

        updateContent()
    }

    func updateContent() {
        guard let delegate = delegate else {
            return
        }
        items = loadAllPaymentsHistoryItems(delegate: delegate)
        delegate.didUpdateContent()
    }

    private func loadAllPaymentsHistoryItems(delegate: PaymentsHistoryDataSourceDelegate) -> [PaymentsHistoryItem] {
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            // PAYMENTS TODO: Should we using paging, etc?
            // PAYMENTS TODO: Sort in query?
            var paymentModels: [TSPaymentModel] = TSPaymentModel.anyFetchAll(transaction: transaction)
            paymentModels.sortBySortDate(descending: true)
            paymentModels = paymentModels.filter { paymentModel in
                switch delegate.recordType {
                case .all:
                    return true
                case .incoming:
                    return paymentModel.isIncoming
                case .outgoing:
                    return paymentModel.isOutgoing
                }
            }
            if let maxRecordCount = delegate.maxRecordCount,
               maxRecordCount < paymentModels.count {
                paymentModels = Array(paymentModels.prefix(maxRecordCount))
            }

            return paymentModels.map { paymentModel in
                var displayName: String
                if paymentModel.isUnidentified {
                    displayName = PaymentsViewUtils.buildUnidentifiedTransactionString(paymentModel: paymentModel)
                } else if let senderOrRecipientAci = paymentModel.senderOrRecipientAci?.wrappedAciValue {
                    displayName = SSKEnvironment.shared.contactManagerRef.displayName(for: SignalServiceAddress(senderOrRecipientAci), tx: transaction).resolvedValue()
                } else if paymentModel.isOutgoingTransfer {
                    displayName = OWSLocalizedString("PAYMENTS_TRANSFER_OUT_PAYMENT",
                                                    comment: "Label for 'transfer out' payments.")
                } else if paymentModel.isDefragmentation {
                    displayName = OWSLocalizedString("PAYMENTS_DEFRAGMENTATION_PAYMENT",
                                                    comment: "Label for 'defragmentation' payments.")
                } else {
                    displayName = OWSLocalizedString("PAYMENTS_UNKNOWN_PAYMENT",
                                                    comment: "Label for unknown payments.")
                }
                return PaymentsHistoryModelItem(paymentModel: paymentModel, displayName: displayName)
            }
        }
    }

    func cell(forIndexPath indexPath: IndexPath, tableView: UITableView) -> UITableViewCell {
        guard let paymentItem = items[safe: indexPath.row] else {
            owsFailDebug("Invalid index path.")
            return UITableViewCell()
        }
        return Self.cell(forPaymentItem: paymentItem, tableView: tableView, indexPath: indexPath)
    }

    public static func cell(forPaymentItem paymentItem: PaymentsHistoryItem,
                            tableView: UITableView,
                            indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: PaymentModelCell.reuseIdentifier,
                                                       for: indexPath) as? PaymentModelCell else {
            owsFailDebug("Cell had unexpected type.")
            return UITableViewCell()
        }
        cell.configure(paymentItem: paymentItem)
        return cell
    }
}

// MARK: -

extension PaymentsHistoryDataSource: DatabaseChangeDelegate {

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard databaseChanges.didUpdate(tableName: TSPaymentModel.table.tableName) else {
            return
        }

        updateContent()
    }

    public func databaseChangesDidUpdateExternally() {
        updateContent()
    }

    public func databaseChangesDidReset() {
        updateContent()
    }
}

extension ArchivedPayment {
    public func statusDescription(isOutgoing: Bool) -> String? {
        if status.isFailure {
            switch (failureReason, isOutgoing) {
            case (.insufficientFundsFailure, true):
                return OWSLocalizedString(
                    "PAYMENTS_FAILURE_OUTGOING_INSUFFICIENT_FUNDS",
                    comment: "Status indicator for outgoing payments which failed due to insufficient funds."
                )
            case (.networkFailure, true):
                return OWSLocalizedString(
                    "PAYMENTS_FAILURE_OUTGOING_NOTIFICATION_SEND_FAILED",
                    comment: "Status indicator for outgoing payments for which the notification could not be sent."
                )
            case (_, true):
                return OWSLocalizedString(
                    "PAYMENTS_FAILURE_OUTGOING_FAILED",
                    comment: "Status indicator for outgoing payments which failed."
                )
            case (_, false):
                return OWSLocalizedString(
                    "PAYMENTS_FAILURE_INCOMING_FAILED",
                    comment: "Status indicator for incoming payments which failed."
                )
            }
        } else {
            switch (status, isOutgoing) {
            case (.initial, true):
                return OWSLocalizedString(
                    "PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_UNSUBMITTED",
                    comment: "Status indicator for outgoing payments which have not yet been submitted."
                )
            case (.submitted, true):
                return OWSLocalizedString(
                    "PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_SENDING",
                    comment: "Status indicator for outgoing payments which are being sent."
                )
            case (_, true):
                return OWSLocalizedString(
                    "PAYMENTS_PAYMENT_STATUS_SHORT_OUTGOING_SENT",
                    comment: "Status indicator for outgoing payments which have been sent."
                )
            case (_, false):
                return OWSLocalizedString(
                    "PAYMENTS_PAYMENT_STATUS_SHORT_INCOMING_COMPLETE",
                    comment: "Status indicator for incoming payments which are complete."
                )
            }
        }
    }
}
