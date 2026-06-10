//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SwiftUI

struct BackupPlanTermsAndConditionsView: View {
    var body: some View {
        let label = OWSLocalizedString(
            "BACKUP_PLAN_TERM_AND_PRIVACY_POLICY_TEXT",
            comment: "Title for a label allowing users to view Signal's Terms & Conditions.",
        )
        return Text("[\(label)](https://support.signal.org/)")
            .font(.subheadline.weight(.bold))
            .environment(\.openURL, OpenURLAction { _ in
                CurrentAppContext().open(
                    TSConstants.legalTermsUrl,
                    completion: nil,
                )
                return .handled
            })
            .foregroundStyle(Color.Signal.secondaryLabel)
            .tint(Color.Signal.secondaryLabel)
    }
}
