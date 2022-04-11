//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

class DonationReceiptViewController: OWSTableViewController2 {
    let model: DonationReceipt

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    init(model: DonationReceipt) {
        self.model = model
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("DONATION_RECEIPT_DETAILS", comment: "Title on the view where you can see a single receipt")

        updateTableContents()
    }

    // MARK: - Rendering table contents

    private func updateTableContents() {
        self.contents = OWSTableContents(sections: [amountSection(), detailsSection()])
    }

    private func amountSection() -> OWSTableSection {
        OWSTableSection(items: [
            OWSTableItem(customCellBlock: {
                let model = self.model

                let amountLabel = UILabel()
                amountLabel.text = DonationUtilities.formatCurrency(NSDecimalNumber(decimal: model.amount), currencyCode: model.currencyCode)
                amountLabel.textColor = Theme.primaryTextColor
                amountLabel.font = .preferredFont(forTextStyle: .largeTitle)
                amountLabel.adjustsFontForContentSizeCategory = true

                let content = UIStackView(arrangedSubviews: [amountLabel])
                content.axis = .vertical
                content.alignment = .center

                let cell = OWSTableItem.newCell()
                cell.contentView.addSubview(content)

                content.autoPinEdgesToSuperviewMargins()

                return cell
            })
        ])
    }

    private func detailsSection() -> OWSTableSection {
        OWSTableSection(items: [
            .item(
                name: NSLocalizedString("DONATION_RECEIPT_TYPE", comment: "Section title for donation type on receipts"),
                subtitle: model.localizedName,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "donation_receipt_details_type")
            ),
            .item(
                name: NSLocalizedString("DONATION_RECEIPT_DATE_PAID", comment: "Section title for donation date on receipts"),
                subtitle: dateFormatter.string(from: model.timestamp),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "donation_receipt_details_date")
            )
        ])
    }
}
