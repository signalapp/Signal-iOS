//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
public import SignalServiceKit
import SignalUI
import SwiftUI

protocol RegistrationRestoreFromBackupConfirmationPresenter: AnyObject {
    func restoreFromBackupConfirmed(_ backup: RegistrationRestoreFromBackupConfirmationState.AvailableBackup)
    func skipRestoreFromBackup()
    func cancelRestoreFromBackup()
}

public class RegistrationRestoreFromBackupConfirmationState: ObservableObject, Equatable {
    public enum AvailableBackup: Equatable {
        case remote(Date?, UInt64?, RegistrationProvisioningMessage.BackupTier)
        case local(Date)
    }

    enum Mode {
        case manual
        case quickRestore
    }

    public static func ==(
        lhs: RegistrationRestoreFromBackupConfirmationState,
        rhs: RegistrationRestoreFromBackupConfirmationState,
    ) -> Bool {
        lhs.availableBackups == rhs.availableBackups
    }

    let mode: Mode
    let availableBackups: [AvailableBackup]

    @Published var selectedBackup: AvailableBackup?

    init(
        mode: Mode,
        availableBackups: [AvailableBackup],
    ) {
        self.mode = mode
        self.availableBackups = availableBackups.sorted(by: >)
        self.selectedBackup = self.availableBackups.first
    }
}

extension RegistrationRestoreFromBackupConfirmationState.AvailableBackup: Comparable {
    var date: Date? {
        switch self {
        case .remote(let date, _, _): return date
        case .local(let date): return date
        }
    }

    var size: UInt64? {
        switch self {
        case .remote(_, let size, _): return size
        case .local: return nil
        }
    }

    var tier: RegistrationProvisioningMessage.BackupTier? {
        switch self {
        case .remote(_, _, let tier): return tier
        case .local: return nil
        }
    }

    var pickerIcon: UIImage? {
        switch self {
        case .remote: return nil // Not supported
        case .local: return UIImage(resource: .folder)
        }
    }

    public static func <(lhs: Self, rhs: Self) -> Bool {
        (lhs.date ?? .distantPast) < (rhs.date ?? .distantPast)
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
                onChooseOlderBackup: { [weak self] in
                    self?.presentBackupPicker()
                },
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

    private func presentBackupPicker() {
        let backups = state.availableBackups
        guard !backups.isEmpty else { return }

        let rows: [HeroSheetViewController.Body.SelectableRow] = backups.map { backup in
            HeroSheetViewController.Body.SelectableRow(
                icon: backup.pickerIcon,
                title: backup.date.map { DateUtil.formatPastTimestampRelativeToNow($0.ows_millisecondsSince1970) } ?? "",
            )
        }

        let initialSelectedIndex: Int? = backups.firstIndex(where: { $0 == state.selectedBackup })
        var selectedIndex: Int? = initialSelectedIndex

        let sheet = HeroSheetViewController(
            hero: .image(UIImage(resource: .backup)),
            title: OWSLocalizedString(
                "ONBOARDING_CHOOSE_BACKUP_SHEET_TITLE",
                comment: "Title for the sheet that lets users pick from available local backups to restore.",
            ),
            body: HeroSheetViewController.Body([
                .text(.plain(OWSLocalizedString(
                    "ONBOARDING_CHOOSE_BACKUP_SHEET_SUBTITLE",
                    comment: "Subtitle for the sheet that lets users pick from available local backups to restore.",
                ))),
                .selectableList(
                    rows: rows,
                    initialSelectedIndex: initialSelectedIndex,
                    onSelectionChanged: { index in
                        selectedIndex = index
                    },
                ),
            ]),
            primary: .button(HeroSheetViewController.Button(
                title: CommonStrings.continueButton,
                style: .primary,
                action: .custom { [weak self] sheet in
                    if let index = selectedIndex, backups.indices.contains(index) {
                        self?.state.selectedBackup = backups[index]
                    }
                    sheet.dismiss(animated: true)
                },
            )),
            secondary: .button(.dismissing(
                title: CommonStrings.cancelButton,
                style: .secondary,
            )),
        )
        present(sheet, animated: true)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct RegistrationRestoreFromBackupConfirmationView: View {
    @ObservedObject private var state: RegistrationRestoreFromBackupConfirmationState
    weak var presenter: (any RegistrationRestoreFromBackupConfirmationPresenter)?
    private let onChooseOlderBackup: () -> Void

    fileprivate init(
        state: RegistrationRestoreFromBackupConfirmationState,
        presenter: RegistrationRestoreFromBackupConfirmationPresenter,
        onChooseOlderBackup: @escaping () -> Void,
    ) {
        self.state = state
        self.presenter = presenter
        self.onChooseOlderBackup = onChooseOlderBackup
    }

    private var displayedDate: Date? {
        state.selectedBackup?.date
    }

    private var displayedSize: UInt64? {
        state.selectedBackup?.size
    }

    private var tier: RegistrationProvisioningMessage.BackupTier? {
        state.selectedBackup?.tier
    }

    private var canChooseOlderBackup: Bool {
        state.availableBackups.count > 1
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

                if canChooseOlderBackup {
                    chooseOlderBackupButton
                        .padding(.top, 8)
                }

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

                        let backupPeriodString = if tier == .free {
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

                    if canChooseOlderBackup {
                        chooseOlderBackupButton
                    }
                }
                .background(Color.Signal.background)
                .scrollBounceBehaviorIfAvailable(.basedOnSize)
            }

            Button(OWSLocalizedString(
                "ONBOARDING_CONFIRM_BACKUP_RESTORE_CONFIRM_ACTION",
                comment: "Text for action button confirming the restore.",
            )) {
                guard let selectedBackup = state.selectedBackup else {
                    owsFailDebug("No backup selected")
                    return
                }
                presenter?.restoreFromBackupConfirmed(selectedBackup)
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
                let date = displayedDate,
                let formattedDate = DateUtil.dateFormatter.string(for: date),
                let formattedTime = DateUtil.timeFormatter.string(for: date)
            {
                formattedString = String.nonPluralLocalizedStringWithFormat(formattedString, formattedDate, formattedTime)
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
                let date = displayedDate,
                let size = displayedSize,
                let formattedDate = DateUtil.dateFormatter.string(for: date),
                let formattedTime = DateUtil.timeFormatter.string(for: date)
            {
                formattedString = String.nonPluralLocalizedStringWithFormat(formattedString, formattedDate, formattedTime, OWSByteCountFormatStyle().format(size))
                return Text(formattedString)
            } else if
                let date = displayedDate,
                let formattedDate = DateUtil.dateFormatter.string(for: date),
                let formattedTime = DateUtil.timeFormatter.string(for: date)
            {
                var noSizeFormattedString = OWSLocalizedString(
                    "ONBOARDING_CONFIRM_BACKUP_RESTORE_DESCRIPTION_NO_SIZE",
                    comment: "Description for form confirming restore from backup without size detail.",
                )
                noSizeFormattedString = String.nonPluralLocalizedStringWithFormat(noSizeFormattedString, formattedDate, formattedTime)
                return Text(noSizeFormattedString)
            } else {
                return Text("")
            }
        }
    }

    private var chooseOlderBackupButton: some View {
        Button {
            onChooseOlderBackup()
        } label: {
            Text(OWSLocalizedString(
                "ONBOARDING_CONFIRM_BACKUP_RESTORE_CHOOSE_OLDER_ACTION",
                comment: "Text for action button that opens a picker to choose an older local backup.",
            ))
            .font(.footnote)
            .foregroundColor(Color.Signal.label)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                Capsule().fill(Color.Signal.secondaryFill),
            )
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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
    func restoreFromBackupConfirmed(_ backup: RegistrationRestoreFromBackupConfirmationState.AvailableBackup) {
        print("Confirmed (\(backup))")
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
        availableBackups: [.remote(Date(), 1234, .free)],
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
        availableBackups: [.remote(Date(), 1234, .paid)],
    )
    RegistrationRestoreFromBackupConfirmationViewController(
        state: state,
        presenter: presenter,
    )
}

#endif
