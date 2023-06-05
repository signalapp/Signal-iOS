//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

class DonationReceiptsViewController: OWSTableViewController2 {

    private var donationReceipts = [DonationReceipt]()
    private let profileBadgeLookup: ProfileBadgeLookup

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    init(profileBadgeLookup: ProfileBadgeLookup) {
        self.profileBadgeLookup = profileBadgeLookup
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("DONATION_RECEIPTS", comment: "Title of view where you can see all of your donation receipts, or button to take you there")
        defaultSeparatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing

        donationReceipts = Self.databaseStorage.read { DonationReceiptFinder.fetchAllInReverseDateOrder(transaction: $0) }

        updateTableContents()
    }

    override func themeDidChange() {
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        var sections = [OWSTableSection]()

        for donationReceipt in donationReceipts {
            let year = Calendar.current.component(.year, from: donationReceipt.timestamp)
            let yearString = String(year)

            let sectionForThisYear: OWSTableSection
            if let lastSection = sections.last, lastSection.headerTitle == yearString {
                sectionForThisYear = lastSection
            } else {
                let newSection = OWSTableSection()
                newSection.headerTitle = yearString
                sections.append(newSection)
                sectionForThisYear = newSection
            }

            let profileBadgeImage = profileBadgeLookup.getImage(donationReceipt: donationReceipt, preferDarkTheme: Theme.isDarkThemeEnabled)
            let formattedDate = dateFormatter.string(from: donationReceipt.timestamp)
            let formattedAmount = DonationUtilities.format(money: donationReceipt.amount)

            let tableItem = OWSTableItem(
                customCellBlock: { [weak self] in
                    guard let self = self else {
                        owsFailDebug("Missing self")
                        return OWSTableItem.newCell()
                    }

                    let accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "donation_receipt.\(donationReceipt.uniqueId)")

                    return OWSTableItem.buildImageNameCell(
                        image: profileBadgeImage,
                        itemName: formattedDate,
                        subtitle: donationReceipt.localizedName,
                        accessoryText: formattedAmount,
                        accessoryTextColor: Theme.primaryTextColor,
                        accessoryType: .disclosureIndicator,
                        accessibilityIdentifier: accessibilityIdentifier
                    )
                },
                actionBlock: { [weak self] in
                    let vc = DonationReceiptViewController(model: donationReceipt)
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            )

            sectionForThisYear.add(tableItem)
        }

        let footerSection = OWSTableSection()
        footerSection.footerTitle = OWSLocalizedString(
            "DONATION_RECEIPTS_MIGHT_BE_MISSING_IF_YOU_REINSTALLED",
            comment: "Text at the bottom of the donation receipts list, telling users that receipts might not be available"
        )
        sections.append(footerSection)

        contents.add(sections: sections)
    }
}
