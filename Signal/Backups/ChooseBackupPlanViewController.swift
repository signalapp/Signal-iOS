//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import StoreKit
import SwiftUI

class ChooseBackupPlanViewController:
    HostingController<ChooseBackupPlanView>,
    ChooseBackupPlanViewModel.ActionsDelegate
{
    typealias OnConfirmPlanSelectionBlock = (ChooseBackupPlanViewController, PlanSelection) -> Void
    typealias PlanSelection = BackupEnablingManager.PlanSelection
    typealias StoreKitAvailability = BackupPlanUpsellConfiguration.StoreKitAvailability

    // MARK: -

    private let backupKeyService: BackupKeyService
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let tsAccountManager: TSAccountManager

    private let freeMediaTierDays: UInt64
    private let initialPlanSelection: PlanSelection?
    private let onConfirmPlanSelectionBlock: OnConfirmPlanSelectionBlock
    private let viewModel: ChooseBackupPlanViewModel

    init(
        freeMediaTierDays: UInt64,
        initialPlanSelection: PlanSelection?,
        storeKitAvailability: StoreKitAvailability,
        storageAllowanceBytes: UInt64,
        backupKeyService: BackupKeyService,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
        tsAccountManager: TSAccountManager,
        onConfirmPlanSelectionBlock: @escaping OnConfirmPlanSelectionBlock,
    ) {
        self.backupKeyService = backupKeyService
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.tsAccountManager = tsAccountManager

        self.initialPlanSelection = initialPlanSelection
        self.freeMediaTierDays = freeMediaTierDays
        self.onConfirmPlanSelectionBlock = onConfirmPlanSelectionBlock
        self.viewModel = ChooseBackupPlanViewModel(
            initialPlanSelection: initialPlanSelection,
            freeMediaTierDays: freeMediaTierDays,
            storageAllowanceBytes: storageAllowanceBytes,
            storeKitAvailability: storeKitAvailability,
        )

        super.init(wrappedView: ChooseBackupPlanView(viewModel: viewModel))

        viewModel.actionsDelegate = self
    }

    static func load(
        fromViewController: UIViewController,
        initialPlanSelection: PlanSelection?,
        onConfirmPlanSelectionBlock: @escaping OnConfirmPlanSelectionBlock,
    ) async throws(SheetDisplayableError) -> ChooseBackupPlanViewController {
        let backupKeyService = DependenciesBridge.shared.backupKeyService
        let backupSettingsStore = BackupSettingsStore()
        let backupSubscriptionManager = DependenciesBridge.shared.backupSubscriptionManager
        let db = DependenciesBridge.shared.db
        let subscriptionConfigManager = DependenciesBridge.shared.subscriptionConfigManager
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        let upsellConfig = try await ModalActivityIndicatorViewController.presentAndPropagateResult(
            from: fromViewController,
        ) { () throws(SheetDisplayableError) in
            try await BackupPlanUpsellConfiguration.load(
                backupSubscriptionManager: backupSubscriptionManager,
                db: db,
                subscriptionConfigManager: subscriptionConfigManager,
            )
        }

        return ChooseBackupPlanViewController(
            freeMediaTierDays: upsellConfig.backupSubscriptionConfiguration.freeTierMediaDays,
            initialPlanSelection: initialPlanSelection,
            storeKitAvailability: upsellConfig.storeKitAvailability,
            storageAllowanceBytes: upsellConfig.backupSubscriptionConfiguration.storageAllowanceBytes,
            backupKeyService: backupKeyService,
            backupSettingsStore: backupSettingsStore,
            db: db,
            tsAccountManager: tsAccountManager,
            onConfirmPlanSelectionBlock: onConfirmPlanSelectionBlock,
        )
    }

    // MARK: - ChooseBackupPlanViewModel.ActionsDelegate

    fileprivate func confirmSelection(_ planSelection: PlanSelection) {
        switch (initialPlanSelection, planSelection) {
        case (.free, .free), (.paid, .paid):
            owsFail("Unexpectedly confirmed selection of initial plan! This should've been disallowed.")
        case (nil, _), (.free, .paid):
            onConfirmPlanSelectionBlock(self, planSelection)
        case (.paid, .free):
            OWSActionSheets.showConfirmationAlert(
                title: OWSLocalizedString(
                    "CHOOSE_BACKUP_PLAN_DOWNGRADE_CONFIRMATION_ACTION_SHEET_TITLE",
                    comment: "Title for an action sheet confirming the user wants to downgrade their Backup plan.",
                ),
                message: String.localizedStringWithFormat(
                    OWSLocalizedString(
                        "CHOOSE_BACKUP_PLAN_DOWNGRADE_CONFIRMATION_ACTION_SHEET_MESSAGE_%d",
                        tableName: "PluralAware",
                        comment: "Message for an action sheet confirming the user wants to downgrade their Backup plan. Embeds {{ the number of days that files are available, e.g. '45' }}.",
                    ),
                    freeMediaTierDays,
                ),
                proceedTitle: OWSLocalizedString(
                    "CHOOSE_BACKUP_PLAN_DOWNGRADE_CONFIRMATION_ACTION_SHEET_PROCEED_BUTTON",
                    comment: "Button for an action sheet confirming the user wants to downgrade their Backup plan.",
                ),
                proceedAction: { [self] _ in
                    onConfirmPlanSelectionBlock(self, planSelection)
                },
            )
        }
    }
}

// MARK: -

private class ChooseBackupPlanViewModel: ObservableObject {
    typealias StoreKitAvailability = BackupPlanUpsellConfiguration.StoreKitAvailability
    typealias PlanSelection = BackupEnablingManager.PlanSelection

    protocol ActionsDelegate: AnyObject {
        func confirmSelection(_ planSelection: PlanSelection)
    }

    @Published var planSelection: PlanSelection

    let initialPlanSelection: PlanSelection?
    let freeMediaTierDays: UInt64
    let storageAllowanceBytes: UInt64
    let storeKitAvailability: StoreKitAvailability

    weak var actionsDelegate: ActionsDelegate?

    init(
        initialPlanSelection: PlanSelection?,
        freeMediaTierDays: UInt64,
        storageAllowanceBytes: UInt64,
        storeKitAvailability: StoreKitAvailability,
    ) {
        self.planSelection = initialPlanSelection ?? .free

        self.initialPlanSelection = initialPlanSelection
        self.freeMediaTierDays = freeMediaTierDays
        self.storageAllowanceBytes = storageAllowanceBytes
        self.storeKitAvailability = storeKitAvailability
    }

    // MARK: Actions

    func confirmSelection() {
        actionsDelegate?.confirmSelection(planSelection)
    }
}

struct ChooseBackupPlanView: View {
    @ObservedObject private var viewModel: ChooseBackupPlanViewModel

    fileprivate init(viewModel: ChooseBackupPlanViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollableContentPinnedFooterView {
            VStack {
                Image("backups-choose-plan")
                    .frame(width: 80, height: 80)

                Spacer().frame(height: 8)

                Text(OWSLocalizedString(
                    "CHOOSE_BACKUP_PLAN_TITLE",
                    comment: "Title for a view allowing users to choose a Backup plan.",
                ))
                .font(.title.weight(.semibold))
                .foregroundStyle(Color.Signal.label)

                Spacer().frame(height: 12)

                Text(OWSLocalizedString(
                    "CHOOSE_BACKUP_PLAN_SUBTITLE",
                    comment: "Subtitle for a view allowing users to choose a Backup plan.",
                ))
                .appendLink(CommonStrings.learnMore) {
                    CurrentAppContext().open(
                        URL.Support.backups,
                        completion: nil,
                    )
                }
                .foregroundStyle(Color.Signal.secondaryLabel)

                Spacer().frame(height: 20)

                Button {
                    viewModel.planSelection = .free
                } label: {
                    BackupPlanFreeOptionView(
                        freeMediaTierDays: viewModel.freeMediaTierDays,
                        bulletIconTintColor: viewModel.planSelection == .free ? .Signal.ultramarine : .Signal.label,
                        isCurrentPlan: viewModel.initialPlanSelection == .free,
                        isSelected: viewModel.planSelection == .free,
                        showSelectionCircle: true,
                    )
                }
                .buttonStyle(.plain)

                Spacer().frame(height: 16)

                Button {
                    viewModel.planSelection = .paid
                } label: {
                    BackupPlanPaidOptionView(
                        storeKitAvailability: viewModel.storeKitAvailability,
                        storageAllowanceBytes: viewModel.storageAllowanceBytes,
                        bulletIconTintColor: viewModel.planSelection == .paid ? .Signal.ultramarine : .Signal.label,
                        isCurrentPlan: viewModel.initialPlanSelection == .paid,
                        isSelected: viewModel.planSelection == .paid,
                        showSelectionCircle: true,
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            BackupPlanTermsAndConditionsView()
                .padding(.vertical, 16)
        } pinnedFooter: {
            Button {
                viewModel.confirmSelection()
            } label: {
                let text = switch viewModel.planSelection {
                case .free:
                    switch viewModel.initialPlanSelection {
                    case nil, .free:
                        CommonStrings.continueButton
                    case .paid:
                        OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_DOWNGRADE_BUTTON_TEXT",
                            comment: "Text for a button that will downgrade the user from the paid Backup plan to the free one.",
                        )
                    }
                case .paid:
                    switch viewModel.storeKitAvailability {
                    case .available(let paidPlanDisplayPrice):
                        String.nonPluralLocalizedStringWithFormat(
                            OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_SUBSCRIBE_PAID_BUTTON_TEXT",
                                comment: "Text for a button that will subscribe the user to the paid Backup plan. Embeds {{ the formatted monthly cost, as currency, of the paid plan }}.",
                            ),
                            paidPlanDisplayPrice,
                        )
                    case .unavailableForTesters:
                        CommonStrings.continueButton
                    }
                }

                Text(text)
            }
            .disabled(viewModel.planSelection == viewModel.initialPlanSelection)
            .buttonStyle(Registration.UI.LargePrimaryButtonStyle())
            .padding(.horizontal, 24)
        }
        .padding(.horizontal)
        .multilineTextAlignment(.center)
        .background(Color.Signal.groupedBackground)
    }
}

// MARK: -

#if DEBUG

private extension ChooseBackupPlanViewModel {
    static func forPreview(
        storeKitAvailability: StoreKitAvailability,
    ) -> ChooseBackupPlanViewModel {
        class ChoosePlanActionsDelegate: ChooseBackupPlanViewModel.ActionsDelegate {
            func confirmSelection(_ planSelection: ChooseBackupPlanViewModel.PlanSelection) {
                print("Confirming \(planSelection)")
            }
        }

        let viewModel = ChooseBackupPlanViewModel(
            initialPlanSelection: .free,
            freeMediaTierDays: 45,
            storageAllowanceBytes: 100_000_000_000,
            storeKitAvailability: storeKitAvailability,
        )
        let actionsDelegate = ChoosePlanActionsDelegate()
        ObjectRetainer.retainObject(actionsDelegate, forLifetimeOf: viewModel)
        viewModel.actionsDelegate = actionsDelegate

        return viewModel
    }
}

#Preview("Purchases") {
    ChooseBackupPlanView(viewModel: .forPreview(
        storeKitAvailability: .available(paidPlanDisplayPrice: "$1.99"),
    ))
}

#Preview("No Purchases") {
    ChooseBackupPlanView(viewModel: .forPreview(
        storeKitAvailability: .unavailableForTesters,
    ))
}

#endif
