//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import SwiftUI

protocol RegistrationRestoreFromBackupConfirmationPresenter: AnyObject {
    func restoreFromBackupConfirmed()
}

class RegistrationRestoreFromBackupConfirmationState: ObservableObject {
    let tier: RegistrationProvisioningMessage.BackupTier
    let backupTimestamp: UInt64

    init(tier: RegistrationProvisioningMessage.BackupTier, backupTimestamp: UInt64) {
        self.tier = tier
        self.backupTimestamp = backupTimestamp
    }
}

class RegistrationRestoreFromBackupConfirmationViewController: HostingController<RegistrationRestoreFromBackupConfirmationView> {
    fileprivate init(
        presenter: RegistrationRestoreFromBackupConfirmationPresenter,
        state: RegistrationRestoreFromBackupConfirmationState
    ) {
        super.init(
            wrappedView: RegistrationRestoreFromBackupConfirmationView(
                presenter: presenter,
                state: state
            )
        )
    }
}

struct RegistrationRestoreFromBackupConfirmationView: View {
    @ObservedObject private var state: RegistrationRestoreFromBackupConfirmationState
    weak var presenter: (any RegistrationRestoreFromBackupConfirmationPresenter)?

    fileprivate init(
        presenter: RegistrationRestoreFromBackupConfirmationPresenter,
        state: RegistrationRestoreFromBackupConfirmationState
    ) {
        self.presenter = presenter
        self.state = state
    }

    var body: some View {
        VStack {
            Text(OWSLocalizedString(
                "ONBOARDING_CONFIRM_BACKUP_RESTORE_TITLE",
                comment: "Title for form confirming restore from backup."
            ))
            .multilineTextAlignment(.center)
            .font(.title.weight(.semibold))
            .foregroundStyle(Color.Signal.label)
            .padding(.horizontal, 20)

            bodyText()
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.Signal.secondaryLabel)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(OWSLocalizedString(
                        "ONBOARDING_CONFIRM_BACKUP_RESTORE_BODY_1",
                        comment: "Header text describing what the backup includes."
                    ))
                    .font(.headline.weight(.semibold))

                    BulletPoint(
                        image: .thread,
                        text: OWSLocalizedString(
                            "ONBOARDING_CONFIRM_BACKUP_RESTORE_BODY_2",
                            comment: "Backup content list item describing all messages."
                        )
                    )

                    let backupPeriodString = if state.tier == .free {
                        OWSLocalizedString(
                            "ONBOARDING_CONFIRM_BACKUP_RESTORE_BODY_3_FREE",
                            comment: "Backup content list item describing paid media."
                        )
                    } else {
                        OWSLocalizedString(
                            "ONBOARDING_CONFIRM_BACKUP_RESTORE_BODY_3_PAID",
                            comment: "Backup content list item describing free media."
                        )
                    }
                    BulletPoint(image: .albumTilt, text: backupPeriodString)
                }
                .padding(20) // add padding before applying the background
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.Signal.secondaryBackground)
                .cornerRadius(10)
                .padding(.vertical, 12) // add padding after applying the background
                .padding(.horizontal, 20) // add padding after applying the background
            }
            .background(Color.Signal.background)
            .scrollBounceBehaviorIfAvailable(.basedOnSize)

            Button(OWSLocalizedString(
                "ONBOARDING_CONFIRM_BACKUP_RESTORE_CONFIRM_ACTION",
                comment: "Text for action button confirming the restore."
            )) {
                presenter?.restoreFromBackupConfirmed()
            }
            .buttonStyle(Registration.UI.FilledButtonStyle())
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .frame(maxWidth: 300)

            Button(OWSLocalizedString(
                "ONBOARDING_CONFIRM_BACKUP_RESTORE_MORE_OPTIONS_ACTION",
                comment: "Text for action button to explore other options."
            )) {
                // TODO: Show more options dialog
                print("More options")
            }
            .buttonStyle(Registration.UI.BorderlessButtonStyle())
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .frame(maxWidth: 300)
            .padding(20)
        }
        .padding(.top, 44)
    }

    private func bodyText() -> Text {
        var formattedString = OWSLocalizedString(
            "ONBOARDING_CONFIRM_BACKUP_RESTORE_DESCRIPTION",
            comment: "Description for form confirming restore from backup."
        )
        if
            case let date = Date(millisecondsSince1970: state.backupTimestamp),
            let formattedDate = DateUtil.dateFormatter.string(for: date),
            let formattedTime = DateUtil.timeFormatter.string(for: date)
        {
            formattedString = String(format: formattedString, formattedDate, formattedTime)
        }

        return Text(try! AttributedString(markdown: formattedString))
    }

    private struct BulletPoint: View {
        let image: ImageResource
        let text: String

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                Image(image)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color.Signal.accent)
                Text(text)
            }
        }
    }
}

#if DEBUG
private class PreviewRegistrationRestoreFromBackupConfirmationPresenter: RegistrationRestoreFromBackupConfirmationPresenter {
    func restoreFromBackupConfirmed() {
        print("Confirmed")
    }
}

private let presenter = PreviewRegistrationRestoreFromBackupConfirmationPresenter()
@available(iOS 17, *)
#Preview("Free") {
    let state = RegistrationRestoreFromBackupConfirmationState(
        tier: .free,
        backupTimestamp: Date().ows_millisecondsSince1970
    )
    RegistrationRestoreFromBackupConfirmationViewController(
        presenter: presenter,
        state: state
    )
}

@available(iOS 17, *)
#Preview("Paid") {
    let state = RegistrationRestoreFromBackupConfirmationState(
        tier: .paid,
        backupTimestamp: Date().ows_millisecondsSince1970
    )
    RegistrationRestoreFromBackupConfirmationViewController(
        presenter: presenter,
        state: state
    )
}

#endif
