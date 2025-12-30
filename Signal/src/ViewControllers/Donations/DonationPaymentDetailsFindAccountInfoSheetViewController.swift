//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class DonationPaymentDetailsFindAccountInfoSheetViewController: OWSTableSheetViewController {
    override public func tableContents() -> OWSTableContents {
        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.hasBackground = false

        let imageView = UIImageView(image: .init(named: "statement"))
        imageView.contentMode = .scaleAspectFit
        section.customHeaderView = imageView

        section.add(.init(customCellBlock: {
            let headerLabel = UILabel.title2Label(text: OWSLocalizedString(
                "FIND_ACCOUNT_INFO_SHEET_TITLE",
                comment: "Users can choose to learn more about how to find account info, which will open a sheet with additional information. This is the title of that sheet.",
            ))

            let descriptionLabel = UILabel.explanationTextLabel(text: OWSLocalizedString(
                "FIND_ACCOUNT_INFO_SHEET_BODY",
                comment: "Users can choose to learn more about how to find account info, which will open a sheet with additional information. This is the body of that sheet.",
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
