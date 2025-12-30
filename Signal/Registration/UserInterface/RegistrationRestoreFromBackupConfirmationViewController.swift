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
    func skipRestoreFromBackup()
    func cancelRestoreFromBackup()
}

public class RegistrationRestoreFromBackupConfirmationState: ObservableObject, Equatable {
    enum Mode {
        case manual
        case quickRestore
    }

    public static func ==(
        lhs: RegistrationRestoreFromBackupConfirmationState,
        rhs: RegistrationRestoreFromBackupConfirmationState,
    ) -> Bool {
        lhs.tier == rhs.tier &&
            lhs.lastBackupDate == rhs.lastBackupDate &&
            lhs.lastBackupSizeBytes == rhs.lastBackupSizeBytes
    }

    let mode: Mode
    let tier: RegistrationProvisioningMessage.BackupTier
    let lastBackupDate: Date?
    let lastBackupSizeBytes: UInt?

    init(mode: Mode, tier: RegistrationProvisioningMessage.BackupTier, lastBackupDate: Date?, lastBackupSizeBytes: UInt?) {
        self.mode = mode
        self.tier = tier
        self.lastBackupDate = lastBackupDate
        self.lastBackupSizeBytes = lastBackupSizeBytes
    }
}

class RegistrationRestoreFromBackupConfirmationViewController: OWSViewController, OWSNavigationChildController {
    private var state: RegistrationRestoreFromBackupConfirmationState
    private weak var presenter: (any RegistrationRestoreFromBackupConfirmationPresenter)?

    init(
        state: RegistrationRestoreFromBackupConfirmationState,
        presenter: RegistrationRestoreFromBackupConfirmationPresenter,
    ) {
        self.state = state
        self.presenter = presenter
        super.init()
        self.navigationItem.hidesBackButton = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.Signal.background

        let hostingController = HostingController(
            wrappedView: RegistrationRestoreFromBackupConfirmationView(
                state: state,
                presenter: presenter!,
            ),
        )
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct RegistrationRestoreFromBackupConfirmationView: View {
    @ObservedObject private var state: RegistrationRestoreFromBackupConfirmationState
    weak var presenter: (any RegistrationRestoreFromBackupConfirmationPresenter)?

    fileprivate init(
        state: RegistrationRestoreFromBackupConfirmationState,
        presenter: RegistrationRestoreFromBackupConfirmationPresenter,
    ) {
        self.state = state
        self.presenter = presenter
    }

    var body: some View {
        VStack(spacing: 12) {
            if state.mode == .manual {
                Image(.backupsLogo)
                    .resizable()
                    .frame(width: 48, height: 48)
            }

            Text(OWSLocalizedString(
                "ONBOARDING_CONFIRM_BACKUP_RESTORE_TITLE",
                comment: "Title for form confirming restore from backup.",
            ))
            .multilineTextAlignment(.center)
            .font(.title.weight(.semibold))
            .foregroundStyle(Color.Signal.label)

            bodyText()
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.Signal.secondaryLabel)

            if state.mode == .manual {
                Text(OWSLocalizedString(
                    "ONBOARDING_CONFIRM_BACKUP_RESTORE_DESCRIPTION_NO_SIZE_DETAIL",
                    comment: "Details confirming manual restore from backup.",
                ))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.Signal.secondaryLabel)

                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(OWSLocalizedString(
                            "ONBOARDING_CONFIRM_BACKUP_RESTORE_BODY_1",
                            comment: "Header text describing what the backup includes.",
                        ))
                        .font(.headline.weight(.semibold))

                        BulletPoint(
                            image: .thread,
                            text: OWSLocalizedString(
                                "ONBOARDING_CONFIRM_BACKUP_RESTORE_BODY_2",
                                comment: "Backup content list item describing all messages.",
                            ),
                        )

                        let backupPeriodString = if state.tier == .free {
                            OWSLocalizedString(
                                "ONBOARDING_CONFIRM_BACKUP_RESTORE_BODY_3_FREE",
                                comment: "Backup content list item describing paid media.",
                            )
                        } else {
                            OWSLocalizedString(
                                "ONBOARDING_CONFIRM_BACKUP_RESTORE_BODY_3_PAID",
                                comment: "Backup content list item describing free media.",
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
            }

            Button(OWSLocalizedString(
                "ONBOARDING_CONFIRM_BACKUP_RESTORE_CONFIRM_ACTION",
                comment: "Text for action button confirming the restore.",
            )) {
                presenter?.restoreFromBackupConfirmed()
            }
            .buttonStyle(Registration.UI.LargePrimaryButtonStyle())
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .padding(.horizontal, NSDirectionalEdgeInsets.buttonContainerLayoutMargins.leading)

            Button(secondaryOptionLabel()) {
                switch state.mode {
                case .manual:
                    presenter?.skipRestoreFromBackup()
                case .quickRestore:
                    presenter?.cancelRestoreFromBackup()
                }

            }
            .buttonStyle(Registration.UI.LargeSecondaryButtonStyle())
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .padding(EdgeInsets(NSDirectionalEdgeInsets.buttonContainerLayoutMargins))
        }
    }

    private func bodyText() -> Text {
        switch state.mode {
        case .manual:
            var formattedString = OWSLocalizedString(
                "ONBOARDING_CONFIRM_BACKUP_RESTORE_DESCRIPTION_NO_SIZE",
                comment: "Description for form confirming restore from backup without size detail.",
            )
            if
                let date = state.lastBackupDate,
                let formattedDate = DateUtil.dateFormatter.string(for: date),
                let formattedTime = DateUtil.timeFormatter.string(for: date)
            {
                formattedString = String(format: formattedString, formattedDate, formattedTime)
                return Text(formattedString)
            } else {
                return Text("")
            }
        case .quickRestore:
            var formattedString = OWSLocalizedString(
                "ONBOARDING_CONFIRM_BACKUP_RESTORE_DESCRIPTION",
                comment: "Description for form confirming restore from backup.",
            )
            if
                let date = state.lastBackupDate,
                let size = state.lastBackupSizeBytes,
                let formattedDate = DateUtil.dateFormatter.string(for: date),
                let formattedTime = DateUtil.timeFormatter.string(for: date)
            {
                formattedString = String(format: formattedString, formattedDate, formattedTime, OWSFormat.formatFileSize(size))
                return Text(formattedString)
            } else {
                return Text("")
            }
        }
    }

    private func secondaryOptionLabel() -> String {
        switch state.mode {
        case .manual:
            return OWSLocalizedString(
                "ONBOARDING_CONFIRM_BACKUP_RESTORE_SKIP_ACTION",
                comment: "Text for action button to skip the restore.",
            )
        case .quickRestore:
            return CommonStrings.cancelButton
        }
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

    func skipRestoreFromBackup() {
        print("Skip Restore")
    }

    func cancelRestoreFromBackup() {
        print("Cancel")
    }
}

private let presenter = PreviewRegistrationRestoreFromBackupConfirmationPresenter()
@available(iOS 17, *)
#Preview("Free") {
    let state = RegistrationRestoreFromBackupConfirmationState(
        mode: .manual,
        tier: .free,
        lastBackupDate: Date(),
        lastBackupSizeBytes: 1234,
    )
    RegistrationRestoreFromBackupConfirmationViewController(
        state: state,
        presenter: presenter,
    )
}

@available(iOS 17, *)
#Preview("Paid") {
    let state = RegistrationRestoreFromBackupConfirmationState(
        mode: .quickRestore,
        tier: .paid,
        lastBackupDate: Date(),
        lastBackupSizeBytes: 1234,
    )
    RegistrationRestoreFromBackupConfirmationViewController(
        state: state,
        presenter: presenter,
    )
}

#endif
