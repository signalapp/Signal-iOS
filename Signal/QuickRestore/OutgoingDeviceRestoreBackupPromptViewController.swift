//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import SwiftUI

class OutgoingDeviceRestoreBackupPromptViewController: HostingController<OutgoingDeviceRestoreBackupPromptView> {
    init(
        lastBackupDetails: BackupSettingsStore.LastBackupDetails,
        makeBackupCallback: @escaping (Bool) -> Void,
    ) {
        super.init(wrappedView: OutgoingDeviceRestoreBackupPromptView(
            lastBackupDetails: lastBackupDetails,
            makeBackupCallback: makeBackupCallback,
        ))
        self.modalPresentationStyle = .overFullScreen
        self.title = OWSLocalizedString(
            "OUTGOING_DEVICE_RESTORE_BACKUP_PROMPT_INITIAL_VIEW_TITLE",
            comment: "Title text describing the outgoing transfer.",
        )
        self.navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
        view.backgroundColor = UIColor.Signal.secondaryBackground
        OWSTableViewController2.removeBackButtonText(viewController: self)
    }
}

struct OutgoingDeviceRestoreBackupPromptView: View {
    private let lastBackupDetails: BackupSettingsStore.LastBackupDetails
    private let makeBackupCallback: (Bool) -> Void
    init(
        lastBackupDetails: BackupSettingsStore.LastBackupDetails,
        makeBackupCallback: @escaping (Bool) -> Void,
    ) {
        self.lastBackupDetails = lastBackupDetails
        self.makeBackupCallback = makeBackupCallback
    }

    var body: some View {
        SignalList {
            SignalSection {
                VStack(alignment: .center, spacing: 24) {
                    Text(OWSLocalizedString(
                        "OUTGOING_DEVICE_RESTORE_BACKUP_PROMPT_INITIAL_VIEW_BODY",
                        comment: "Body text describing the outgoing transfer.",
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                    .tint(Color.Signal.label)

                    Image(.transferAccount)

                    Text(lastBackupDetailsString())
                        .font(.subheadline)
                        .foregroundStyle(Color.Signal.secondaryLabel)
                        .tint(Color.Signal.label)

                    Button(OWSLocalizedString(
                        "OUTGOING_DEVICE_RESTORE_BACKUP_PROMPT_BACKUP_ACTION",
                        comment: "Action button to backup before continuing.",
                    )) {
                        self.makeBackupCallback(true)
                    }
                    .buttonStyle(Registration.UI.LargePrimaryButtonStyle())

                    Button(OWSLocalizedString(
                        "OUTGOING_DEVICE_RESTORE_BACKUP_PROMPT_SKIP_ACTION",
                        comment: "Action button to skip backup and continue.",
                    )) {
                        self.makeBackupCallback(false)
                    }
                    .buttonStyle(Registration.UI.LargeSecondaryButtonStyle())
                }.padding([.top, .bottom], 12)
            }
            footer: {
                let footerString = OWSLocalizedString(
                    "OUTGOING_DEVICE_RESTORE_INITIAL_VIEW_FOOTER",
                    comment: "Body text describing the outgoing transfer.",
                )
                Text("\(SignalSymbol.lock.text(dynamicTypeBaseSize: 14)) \(footerString)")
                    .font(.footnote)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                    .padding([.top, .bottom], 12)
            }
        }
        .scrollBounceBehaviorIfAvailable(.basedOnSize)
        .multilineTextAlignment(.center)
    }

    private func lastBackupDetailsString() -> String {
        let date = lastBackupDetails.date
        return String(
            format: OWSLocalizedString(
                "OUTGOING_DEVICE_RESTORE_BACKUP_RESTORE_DESCRIPTION",
                comment: "Description for form confirming restore from backup without size detail.",
            ),
            DateUtil.dateFormatter.string(for: date) ?? "",
            DateUtil.timeFormatter.string(for: date) ?? "",
        )
    }
}

// MARK: Previews

#if DEBUG
@available(iOS 17, *)
#Preview {
    OWSNavigationController(
        rootViewController: OutgoingDeviceRestoreBackupPromptViewController(
            lastBackupDetails: .init(
                date: Date(),
                backupFileSizeBytes: 1024,
                backupTotalSizeBytes: 4096,
            ),
            makeBackupCallback: {
                print("Should do backup? \($0)")
            },
        ),
    )
}
#endif
