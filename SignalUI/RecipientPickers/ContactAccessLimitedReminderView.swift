//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SwiftUI

@available(iOS 18, *)
struct ContactAccessLimitedReminderView: View {
    private let completion: () -> Void
    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    @State private var displayPicker = false
    var body: some View {
        HStack {
            Text(
                OWSLocalizedString(
                    "COMPOSE_SCREEN_LIMITED_CONTACTS_PERMISSION",
                    comment: "Multi-line label explaining why compose-screen contact picker is empty."
                )
            )
            .font(.system(.subheadline))
            Spacer()
            VStack {
                Menu {
                    Button {
                        displayPicker.toggle()
                    } label: {
                        Label {
                            Text(
                                OWSLocalizedString(
                                    "COMPOSE_SCREEN_LIMITED_CONTACTS_ACTION_MANAGE",
                                    comment: "Menu action to display limited contact picker."
                                )
                            )
                        } icon: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                    Button {
                        CurrentAppContext().openSystemSettings()
                    } label: {
                        Label {
                            Text(
                                OWSLocalizedString(
                                    "COMPOSE_SCREEN_LIMITED_CONTACTS_ACTION_SETTINGS",
                                    comment: "Menu action visit app contact permission in settings."
                                )
                            )
                        } icon: {
                            Image(systemName: "gear")
                        }
                    }
                } label: {
                    Text(
                        OWSLocalizedString(
                            "COMPOSE_SCREEN_LIMITED_CONTACTS_CTA",
                            comment: "Multi-line label explaining why compose-screen contact picker may be missing contacts."
                        )
                    )
                    .font(.system(.subheadline).weight(.bold))
                }
            }
        }
        .contactAccessPicker(isPresented: $displayPicker) { _ in
            completion()
        }
    }
}
