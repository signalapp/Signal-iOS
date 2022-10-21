//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

@objc
class PaymentsHistoryViewController: OWSTableViewController2 {

    private let modeControl = UISegmentedControl()

    public var recordType: PaymentsHistoryDataSource.RecordType = .all {
        didSet {
            dataSource.updateContent()
        }
    }

    private let dataSource = PaymentsHistoryDataSource()

    public override required init() {
        super.init()

        topHeader = OWSTableViewController2.buildTopHeader(forView: modeControl,
                                                           vMargin: 10)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_PAYMENTS_ALL_RECORDS",
                                  comment: "Label for the 'all payment records' section of the app settings.")

        createSubviews()

        dataSource.delegate = self

        updateTableContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: PaymentsCurrenciesImpl.paymentConversionRatesDidChange,
            object: nil
        )
    }

    public override func applyTheme() {
        super.applyTheme()

        updateTableContents()
    }

    private func createSubviews() {
        assert(PaymentsHistoryDataSource.RecordType.all.rawValue == 0)
        modeControl.insertSegment(withTitle: NSLocalizedString("SETTINGS_PAYMENTS_PAYMENTS_TYPE_ALL",
                                                               comment: "Label for the 'all payments' mode of the 'all payment records' section of the app settings."),
                                  at: PaymentsHistoryDataSource.RecordType.all.rawValue,
                                  animated: false)
        assert(PaymentsHistoryDataSource.RecordType.incoming.rawValue == 1)
        modeControl.insertSegment(withTitle: NSLocalizedString("SETTINGS_PAYMENTS_PAYMENTS_TYPE_INCOMING",
                                                               comment: "Label for the 'incoming payments' mode of the 'all payment records' section of the app settings."),
                                  at: PaymentsHistoryDataSource.RecordType.incoming.rawValue,
                                  animated: false)
        assert(PaymentsHistoryDataSource.RecordType.outgoing.rawValue == 2)
        modeControl.insertSegment(withTitle: NSLocalizedString("SETTINGS_PAYMENTS_PAYMENTS_TYPE_OUTGOING",
                                                               comment: "Label for the 'outgoing payments' mode of the 'all payment records' section of the app settings."),
                                  at: PaymentsHistoryDataSource.RecordType.outgoing.rawValue,
                                  animated: false)
        modeControl.selectedSegmentIndex = recordType.rawValue
        modeControl.addTarget(self,
                              action: #selector(modeControlDidChange),
                              for: .valueChanged)
    }

    @objc
    private func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.customHeaderHeight = 16
        section.separatorInsetLeading = NSNumber(value: Double(cellOuterInsets.leading +
                                                                PaymentModelCell.separatorInsetLeading))
        for paymentItem in dataSource.items {
            section.add(OWSTableItem(customCellBlock: {
                let cell = PaymentModelCell()
                cell.configure(paymentItem: paymentItem)
                return cell
            },
            actionBlock: { [weak self] in
                self?.didTapPaymentItem(paymentItem: paymentItem)
            }))
        }
        contents.addSection(section)

        self.contents = contents
    }

    // MARK: -

    private func didTapPaymentItem(paymentItem: PaymentsHistoryItem) {
        let view = PaymentsDetailViewController(paymentItem: paymentItem)
        navigationController?.pushViewController(view, animated: true)
    }

    @objc
    func modeControlDidChange(_ sender: UISegmentedControl) {

        guard let recordType = PaymentsHistoryDataSource.RecordType(rawValue: sender.selectedSegmentIndex) else {
            owsFailDebug("Couldn't update recordType.")
            return
        }
        self.recordType = recordType
    }
}

// MARK: -

extension PaymentsHistoryViewController: PaymentsHistoryDataSourceDelegate {
    var maxRecordCount: Int? {
        nil
    }

    func didUpdateContent() {
        AssertIsOnMainThread()

        updateTableContents()
    }
}
