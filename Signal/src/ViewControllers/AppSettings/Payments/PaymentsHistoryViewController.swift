//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PaymentsHistoryViewController: OWSTableViewController2, PaymentsHistoryDataSourceDelegate {

    private lazy var modeControl: UISegmentedControl = {
        let control = UISegmentedControl()
        assert(PaymentsHistoryDataSource.RecordType.all.rawValue == 0)
        control.insertSegment(
            withTitle: OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_TYPE_ALL",
                comment: "Label for the 'all payments' mode of the 'all payment records' section of the app settings.",
            ),
            at: PaymentsHistoryDataSource.RecordType.all.rawValue,
            animated: false,
        )
        assert(PaymentsHistoryDataSource.RecordType.incoming.rawValue == 1)
        control.insertSegment(
            withTitle: OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_TYPE_INCOMING",
                comment: "Label for the 'incoming payments' mode of the 'all payment records' section of the app settings.",
            ),
            at: PaymentsHistoryDataSource.RecordType.incoming.rawValue,
            animated: false,
        )
        assert(PaymentsHistoryDataSource.RecordType.outgoing.rawValue == 2)
        control.insertSegment(
            withTitle: OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_TYPE_OUTGOING",
                comment: "Label for the 'outgoing payments' mode of the 'all payment records' section of the app settings.",
            ),
            at: PaymentsHistoryDataSource.RecordType.outgoing.rawValue,
            animated: false,
        )
        control.selectedSegmentIndex = recordType.rawValue
        control.addTarget(
            self,
            action: #selector(modeControlDidChange),
            for: .valueChanged,
        )
        return control
    }()

    var recordType: PaymentsHistoryDataSource.RecordType = .all {
        didSet {
            dataSource.updateContent()
        }
    }

    private let dataSource = PaymentsHistoryDataSource()
    private var notificationObserver: NotificationCenter.Observer?

    override init() {
        super.init()

        topHeader = OWSTableViewController2.buildTopHeader(forView: modeControl, vMargin: 10)
    }

    deinit {
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_ALL_RECORDS",
            comment: "Label for the 'all payment records' section of the app settings.",
        )

        dataSource.delegate = self

        updateTableContents()

        notificationObserver = NotificationCenter.default.addObserver(
            name: PaymentsCurrenciesImpl.paymentConversionRatesDidChange,
        ) { [weak self] _ in
            self?.updateTableContents()
        }
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.customHeaderHeight = 16
        section.separatorInsetLeading = Self.cellHInnerMargin + PaymentModelCell.separatorInsetLeading
        for paymentItem in dataSource.items {
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = PaymentModelCell()
                    cell.configure(paymentItem: paymentItem)
                    return cell
                },
                actionBlock: { [weak self] in
                    self?.didTapPaymentItem(paymentItem: paymentItem)
                },
            ))
        }
        contents.add(section)

        self.contents = contents
    }

    // MARK: -

    private func didTapPaymentItem(paymentItem: PaymentsHistoryItem) {
        let view = PaymentsDetailViewController(paymentItem: paymentItem)
        navigationController?.pushViewController(view, animated: true)
    }

    @objc
    private func modeControlDidChange(_ sender: UISegmentedControl) {
        guard let recordType = PaymentsHistoryDataSource.RecordType(rawValue: sender.selectedSegmentIndex) else {
            owsFailDebug("Couldn't update recordType.")
            return
        }
        self.recordType = recordType
    }

    // MARK: - PaymentsHistoryDataSourceDelegate

    var maxRecordCount: Int? {
        nil
    }

    func didUpdateContent() {
        updateTableContents()
    }
}
