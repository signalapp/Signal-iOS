//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class DonationPaymentDetailsFindAccountInfoSheetViewController: HeroSheetViewController {
    init() {
        super.init(
            hero: .image(UIImage(resource: .statement), tintColor: nil, height: nil),
            title: OWSLocalizedString(
                "FIND_ACCOUNT_INFO_SHEET_TITLE",
                comment: "Users can choose to learn more about how to find account info, which will open a sheet with additional information. This is the title of that sheet.",
            ),
            body: Body([.text(.plain(OWSLocalizedString(
                "FIND_ACCOUNT_INFO_SHEET_BODY",
                comment: "Users can choose to learn more about how to find account info, which will open a sheet with additional information. This is the body of that sheet.",
            )))]),
            primary: nil,
            secondary: nil,
        )
    }
}
