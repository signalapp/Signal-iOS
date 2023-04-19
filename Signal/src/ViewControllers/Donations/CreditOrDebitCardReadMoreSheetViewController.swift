//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

public class CreditOrDebitCardReadMoreSheetViewController: OWSTableSheetViewController {
    override public func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()
        defer { tableViewController.setContents(contents, shouldReload: shouldReload) }

        let section = OWSTableSection()
        section.hasBackground = false

        section.add(.init(customCellBlock: {
            let headerLabel = UILabel()
            headerLabel.font = .dynamicTypeTitle2.semibold()
            headerLabel.textAlignment = .center
            headerLabel.numberOfLines = 0
            headerLabel.text = NSLocalizedString(
                "CARD_DONATION_READ_MORE_SHEET_TITLE",
                comment: "Users can choose to learn more about their credit/debit card donations, which will open a sheet with additional information. This is the title of that sheet."
            )

            let descriptionLabel = UILabel()
            descriptionLabel.font = .dynamicTypeBody
            descriptionLabel.numberOfLines = 0
            descriptionLabel.text = NSLocalizedString(
                "CARD_DONATION_READ_MORE_SHEET_BODY",
                comment: "Users can choose to learn more about their credit/debit card donations, which will open a sheet with additional information. This is the body text of that sheet."
            )

            let stackView = UIStackView(arrangedSubviews: [headerLabel, descriptionLabel])
            stackView.axis = .vertical
            stackView.spacing = 20

            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        contents.addSection(section)
    }
}
