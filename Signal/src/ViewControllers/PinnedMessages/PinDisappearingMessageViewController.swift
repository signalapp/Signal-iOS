//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import SignalServiceKit

class PinDisappearingMessageViewController: HeroSheetViewController {
    init(pinnedMessageManager: PinnedMessageManager) {
        super.init(
            hero: .image(.timer),
            title: OWSLocalizedString(
                "PINNING_DISAPPEARING_MESSAGE_WARNING_TITLE",
                comment: "Title for a sheet warning users they are pinning a disappearing message."
            ),
            body: OWSLocalizedString(
                "PINNING_DISAPPEARING_MESSAGE_WARNING_BODY",
                comment: "Body for a sheet warning users they are pinning a disappearing message."
            ),
            primary: .button(HeroSheetViewController.Button(
                title: CommonStrings.okButton,
                action: { sheet in
                    sheet.dismiss(animated: true)
                }
            )),
            secondary: .button(HeroSheetViewController.Button(
                title: CommonStrings.dontShowAgainButton,
                style: .secondary,
                action: .custom({ sheet in
                    sheet.dismiss(animated: true)
                    // TODO: retention?
                    pinnedMessageManager.stopShowingDisappearingMessageWarning()
                }),
            )),
        )
    }
}
