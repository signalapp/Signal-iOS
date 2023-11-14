//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

public class DonationPaymentDetailsFindAccountInfoSheetViewController: OWSTableSheetViewController {
    override public func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()
        defer { tableViewController.setContents(contents, shouldReload: shouldReload) }

        let section = OWSTableSection()
        section.hasBackground = false

        let imageView = UIImageView(image: .init(named: "statement"))
        imageView.contentMode = .scaleAspectFit
        section.customHeaderView = imageView

        section.add(.init(customCellBlock: {
            let headerLabel = UILabel()
            headerLabel.font = .dynamicTypeTitle3.semibold()
            headerLabel.textAlignment = .center
            headerLabel.numberOfLines = 0
            headerLabel.text = OWSLocalizedString(
                "FIND_ACCOUNT_INFO_SHEET_TITLE",
                comment: "Users can choose to learn more about how to find account info, which will open a sheet with additional information. This is the title of that sheet."
            )

            let descriptionLabel = UILabel()
            descriptionLabel.font = .dynamicTypeSubheadlineClamped
            descriptionLabel.textColor = .secondaryLabel
            descriptionLabel.textAlignment = .center
            descriptionLabel.numberOfLines = 0
            descriptionLabel.text = OWSLocalizedString(
                "FIND_ACCOUNT_INFO_SHEET_BODY",
                comment: "Users can choose to learn more about how to find account info, which will open a sheet with additional information. This is the body of that sheet."
            )

            let stackView = UIStackView(arrangedSubviews: [headerLabel, descriptionLabel])
            stackView.axis = .vertical
            stackView.spacing = 20

            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges(with: .init(top: 12, leading: 45, bottom: 24, trailing: 45))

            return cell
        }))

        contents.add(section)
    }
}
