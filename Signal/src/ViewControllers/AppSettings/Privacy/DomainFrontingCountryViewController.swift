//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class DomainFrontingCountryViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "CENSORSHIP_CIRCUMVENTION_COUNTRY_VIEW_TITLE",
            comment: "Title for the 'censorship circumvention country' view."
        )

        updateTableContents()
    }

    private func updateTableContents() {
        let currentCountryCode = signalService.manualCensorshipCircumventionCountryCode

        let section = OWSTableSection()
        section.headerTitle = OWSLocalizedString(
            "DOMAIN_FRONTING_COUNTRY_VIEW_SECTION_HEADER",
            comment: "Section title for the 'domain fronting country' view."
        )
        for countryMetadata in OWSCountryMetadata.allCountryMetadatas() {
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    cell.textLabel?.text = countryMetadata.localizedCountryName
                    if countryMetadata.countryCode == currentCountryCode {
                        cell.accessoryType = .checkmark
                    }
                    return cell
                },
                actionBlock: { [weak self] in
                    self?.selectCountry(countryMetadata)
                }
            ))
        }

        self.contents = OWSTableContents(sections: [section])
    }

    private func selectCountry(_ countryMetadata: OWSCountryMetadata) {
        signalService.manualCensorshipCircumventionCountryCode = countryMetadata.countryCode
        navigationController?.popViewController(animated: true)
    }

}
