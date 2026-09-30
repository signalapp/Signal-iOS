//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class DonationPaymentDetailsReadMoreSheetViewController: StackSheetViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        stackView.spacing = 12

        let headerLabel = UILabel.title2Label(text: OWSLocalizedString(
            "CARD_DONATION_READ_MORE_SHEET_TITLE",
            comment: "Users can choose to learn more about their credit/debit card donations, which will open a sheet with additional information. This is the title of that sheet.",
        ))
        stackView.addArrangedSubview(headerLabel)

        let descriptionLabel = UILabel.explanationTextLabel(text: OWSLocalizedString(
            "CARD_DONATION_READ_MORE_SHEET_BODY",
            comment: "Users can choose to learn more about their credit/debit card donations, which will open a sheet with additional information. This is the body text of that sheet.",
        ))
        stackView.addArrangedSubview(descriptionLabel)
    }
}
