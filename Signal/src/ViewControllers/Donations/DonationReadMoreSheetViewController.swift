//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class DonationReadMoreSheetViewController: HeroSheetViewController {
    init() {
        super.init(
            hero: .image(.sustainerHeart),
            title: nil,
            body: HeroSheetViewController.Body(
                textContent: .plain(OWSLocalizedString(
                    "DONATION_READ_MORE_SHEET_BODY",
                    comment: "Body text for a sheet discussing donating to Signal.",
                )),
                textAlignment: .left,
                textColor: .Signal.label,
                bulletPoints: [
                    HeroSheetViewController.Body.BulletPoint(
                        icon: .badgeMulti,
                        text: OWSLocalizedString(
                            "DONATION_READ_MORE_SHEET_BULLET_1",
                            comment: "Bullet point for a sheet discussing donating to Signal.",
                        ),
                    ),
                    HeroSheetViewController.Body.BulletPoint(
                        icon: .lock,
                        text: OWSLocalizedString(
                            "DONATION_READ_MORE_SHEET_BULLET_2",
                            comment: "Bullet point for a sheet discussing donating to Signal.",
                        ),
                    ),
                    HeroSheetViewController.Body.BulletPoint(
                        icon: .heart,
                        text: OWSLocalizedString(
                            "DONATION_READ_MORE_SHEET_BULLET_3",
                            comment: "Bullet point for a sheet discussing donating to Signal. For non-English languages, skip the word 501c3, and skip the language about US donations being tax deductible.",
                        ),
                    ),
                ],
            ),
            primary: nil,
            secondary: nil,
        )
    }
}

#if DEBUG

@available(iOS 17, *)
#Preview {
    SheetPreviewViewController(sheet: DonationReadMoreSheetViewController())
}

#endif
