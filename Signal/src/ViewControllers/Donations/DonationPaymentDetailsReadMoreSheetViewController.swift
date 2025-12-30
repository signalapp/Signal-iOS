//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class DonationPaymentDetailsReadMoreSheetViewController: OWSTableSheetViewController {
    override public func tableContents() -> OWSTableContents {
        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.hasBackground = false

        section.add(.init(customCellBlock: {
            let headerLabel = UILabel.title2Label(text: OWSLocalizedString(
                "CARD_DONATION_READ_MORE_SHEET_TITLE",
                comment: "Users can choose to learn more about their credit/debit card donations, which will open a sheet with additional information. This is the title of that sheet.",
            ))

            let descriptionLabel = UILabel.explanationTextLabel(text: OWSLocalizedString(
                "CARD_DONATION_READ_MORE_SHEET_BODY",
                comment: "Users can choose to learn more about their credit/debit card donations, which will open a sheet with additional information. This is the body text of that sheet.",
            ))

            let stackView = UIStackView(arrangedSubviews: [headerLabel, descriptionLabel])
            stackView.axis = .vertical
            stackView.spacing = 12

            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges()

            return cell
        }))

        contents.add(section)

        return contents
    }
}
