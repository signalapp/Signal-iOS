//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public struct PaymentsHistoryItem {
    let paymentModel: TSPaymentModel
    let displayName: String

    var address: SignalServiceAddress? {
        paymentModel.address
    }

    var isIncoming: Bool {
        paymentModel.isIncoming
    }

    var isOutgoing: Bool {
        paymentModel.isOutgoing
    }

    var isOutgoingTransfer: Bool {
        paymentModel.isOutgoingTransfer
    }

    var isUnidentified: Bool {
        paymentModel.isUnidentified
    }

    var isFailed: Bool {
        paymentModel.isFailed
    }

    var isDefragmentation: Bool {
        paymentModel.isDefragmentation
    }

    var receiptData: Data? {
        paymentModel.mobileCoin?.receiptData
    }

    var paymentAmount: TSPaymentAmount? {
        paymentModel.paymentAmount
    }

    var paymentType: TSPaymentType {
        paymentModel.paymentType
    }

    var paymentState: TSPaymentState {
        paymentModel.paymentState
    }

    var sortDate: Date {
        paymentModel.sortDate
    }
}

// MARK: -

protocol PaymentsHistoryDataSourceDelegate: AnyObject {
    var recordType: PaymentsHistoryDataSource.RecordType { get }

    var maxRecordCount: Int? { get }

    func didUpdateContent()
}

// MARK: -

class PaymentsHistoryDataSource: Dependencies {

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
        Self.databaseStorage.appendDatabaseChangeDelegate(self)

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
        Self.databaseStorage.read { transaction in
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
                } else if let address = paymentModel.address {
                    displayName = Self.contactsManager.displayName(for: address, transaction: transaction)
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
                return PaymentsHistoryItem(paymentModel: paymentModel, displayName: displayName)
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
        AssertIsOnMainThread()

        guard databaseChanges.didUpdateModel(collection: TSPaymentModel.collection()) else {
            return
        }

        updateContent()
    }

    public func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()

        updateContent()
    }

    public func databaseChangesDidReset() {
        AssertIsOnMainThread()

        updateContent()
    }
}
