//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import StoreKit
import SwiftUI

class ChooseBackupPlanViewController: HostingController<ChooseBackupPlanView> {
    typealias OnConfirmPlanSelectionBlock = (ChooseBackupPlanViewController, PlanSelection) -> Void

    enum StoreKitAvailability {
        case available(paidPlanDisplayPrice: String)
        case unavailableForTesters
    }

    enum PlanSelection {
        case free
        case paid
    }

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
        let backupSubscriptionManager = DependenciesBridge.shared.backupSubscriptionManager
        let subscriptionConfigManager = DependenciesBridge.shared.subscriptionConfigManager

        let (
            storeKitAvailability,
            backupSubscriptionConfiguration,
        ) = try await ModalActivityIndicatorViewController.presentAndPropagateResult(
            from: fromViewController,
        ) { () throws(SheetDisplayableError) in
            let storeKitAvailability: StoreKitAvailability
            if BuildFlags.Backups.avoidStoreKitForTesters {
                storeKitAvailability = .unavailableForTesters
            } else {
                do {
                    storeKitAvailability = .available(
                        paidPlanDisplayPrice: try await backupSubscriptionManager.subscriptionDisplayPrice(),
                    )
                } catch StoreKitError.networkError {
                    throw .networkError
                } catch {
                    owsFailDebug("Failed to get paidPlanDisplayPrice!")
                    throw .genericError
                }
            }

            let backupSubscriptionConfig: BackupSubscriptionConfiguration
            do {
                backupSubscriptionConfig = try await subscriptionConfigManager.backupConfiguration()
            } catch where error.isNetworkFailureOrTimeout || error.is5xxServiceResponse {
                throw .networkError
            } catch {
                throw .genericError
            }

            return (storeKitAvailability, backupSubscriptionConfig)
        }

        return ChooseBackupPlanViewController(
            freeMediaTierDays: backupSubscriptionConfiguration.freeTierMediaDays,
            initialPlanSelection: initialPlanSelection,
            storeKitAvailability: storeKitAvailability,
            storageAllowanceBytes: backupSubscriptionConfiguration.storageAllowanceBytes,
            backupKeyService: DependenciesBridge.shared.backupKeyService,
            backupSettingsStore: BackupSettingsStore(),
            db: DependenciesBridge.shared.db,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
            onConfirmPlanSelectionBlock: onConfirmPlanSelectionBlock,
        )
    }
}

// MARK: - ChooseBackupPlanViewModel.ActionsDelegate

extension ChooseBackupPlanViewController: ChooseBackupPlanViewModel.ActionsDelegate {
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
    typealias StoreKitAvailability = ChooseBackupPlanViewController.StoreKitAvailability
    typealias PlanSelection = ChooseBackupPlanViewController.PlanSelection

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

                PlanOptionView(
                    title: OWSLocalizedString(
                        "CHOOSE_BACKUP_PLAN_FREE_PLAN_TITLE",
                        comment: "Title for the free plan option, when choosing a Backup plan.",
                    ),
                    subtitle: String.localizedStringWithFormat(
                        OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_FREE_PLAN_SUBTITLE_%d",
                            tableName: "PluralAware",
                            comment: "Subtitle for the free plan option, when choosing a Backup plan. Embeds {{ the number of days that files are available, e.g. '45' }}.",
                        ),
                        viewModel.freeMediaTierDays,
                    ),
                    bullets: [
                        PlanOptionView.BulletPoint(iconKey: "thread", text: OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_BULLET_FULL_TEXT_BACKUP",
                            comment: "Text for a bullet point in a list of Backup features, describing that all text messages are included.",
                        )),
                        PlanOptionView.BulletPoint(iconKey: "album-tilt", text: String.localizedStringWithFormat(
                            OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_BULLET_RECENT_MEDIA_BACKUP_%d",
                                tableName: "PluralAware",
                                comment: "Text for a bullet point in a list of Backup features, describing that recent media is included. Embeds {{ the number of days that files are available, e.g. '45' }}.",
                            ),
                            viewModel.freeMediaTierDays,
                        )),
                    ],
                    isCurrentPlan: viewModel.initialPlanSelection == .free,
                    isSelected: viewModel.planSelection == .free,
                    onTap: {
                        viewModel.planSelection = .free
                    },
                )

                Spacer().frame(height: 16)

                PlanOptionView(
                    title: {
                        switch viewModel.storeKitAvailability {
                        case .available(let paidPlanDisplayPrice):
                            String(
                                format: OWSLocalizedString(
                                    "CHOOSE_BACKUP_PLAN_PAID_PLAN_TITLE",
                                    comment: "Title for the paid plan option, when choosing a Backup plan. Embeds {{ the formatted monthly cost, as currency, of the paid plan }}.",
                                ),
                                paidPlanDisplayPrice,
                            )
                        case .unavailableForTesters:
                            OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_PAID_PLAN_NO_PURCHASES_TITLE",
                                comment: "Title for the paid plan option, when choosing a Backup plan as a tester.",
                            )
                        }
                    }(),
                    subtitle: OWSLocalizedString(
                        "CHOOSE_BACKUP_PLAN_PAID_PLAN_SUBTITLE",
                        comment: "Subtitle for the paid plan option, when choosing a Backup plan.",
                    ),
                    bullets: [
                        PlanOptionView.BulletPoint(iconKey: "thread", text: OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_BULLET_FULL_TEXT_BACKUP",
                            comment: "Text for a bullet point in a list of Backup features, describing that all text messages are included.",
                        )),
                        PlanOptionView.BulletPoint(iconKey: "album-tilt", text: OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_BULLET_FULL_MEDIA_BACKUP",
                            comment: "Text for a bullet point in a list of Backup features, describing that all media is included.",
                        )),
                        PlanOptionView.BulletPoint(iconKey: "data", text: String(
                            format: OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_BULLET_STORAGE_AMOUNT",
                                comment: "Text for a bullet point in a list of Backup features, describing the amount of included storage. Embeds {{ the amount of storage preformatted as a localized byte count, e.g. '100 GB' }}.",
                            ),
                            viewModel.storageAllowanceBytes.formatted(.owsByteCount(
                                fudgeBase2ToBase10: true,
                                zeroPadFractionDigits: false,
                            )),
                        )),
                    ],
                    isCurrentPlan: viewModel.initialPlanSelection == .paid,
                    isSelected: viewModel.planSelection == .paid,
                    onTap: {
                        viewModel.planSelection = .paid
                    },
                )
            }
            .padding(.horizontal, 16)
            termsAndConditionsLink()
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
                        String(
                            format: OWSLocalizedString(
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

    private func termsAndConditionsLink() -> some View {
        let label = OWSLocalizedString(
            "CHOOSE_BACKUP_PLAN_TERM_AND_PRIVACY_POLICY_TEXT",
            comment: "Title for a label allowing users to view Signal's Terms & Conditions.",
        )
        return Text(" [\(label)](https://support.signal.org/)")
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

// MARK: -

private struct PlanOptionView: View {
    struct BulletPoint {
        let iconKey: String
        let text: String
    }

    let title: String
    let subtitle: String
    let bullets: [BulletPoint]
    let isCurrentPlan: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    if isCurrentPlan {
                        Label(
                            OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_CURRENT_PLAN_LABEL",
                                comment: "A label indicating that a given Backup plan option is what the user has already enabled.",
                            ),
                            systemImage: "checkmark",
                        )
                        .font(.footnote)
                        .foregroundStyle(Color.Signal.secondaryLabel)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background {
                            Capsule().fill(Color.Signal.secondaryFill)
                        }
                    }

                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Text(subtitle).foregroundStyle(Color.Signal.secondaryLabel)

                    ForEach(bullets, id: \.iconKey) { bullet in
                        Label {
                            Text(bullet.text).font(.subheadline)
                        } icon: {
                            Image(bullet.iconKey)
                                .foregroundStyle(
                                    isSelected
                                        ? Color.Signal.ultramarine
                                        : Color.Signal.label,
                                )
                        }
                        .padding(.leading, 20)
                        .padding(.vertical, 2)
                    }
                }

                Spacer()

                Group {
                    if isSelected {
                        Circle()
                            .fill(Color.Signal.ultramarine)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .resizable()
                                    .foregroundColor(.white)
                                    .padding(6)
                            }
                    } else {
                        Circle()
                            .stroke(Color.Signal.secondaryLabel, lineWidth: 2)
                            .opacity(0.3)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .background(Color.Signal.secondaryGroupedBackground)
            .cornerRadius(16)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        Color.Signal.ultramarine,
                        lineWidth: isSelected ? 3 : 0,
                    )
            }
            .shadow(
                color: isSelected ? .black.opacity(0.12) : .clear,
                radius: 8,
                y: 2,
            )
        }
        .buttonStyle(.plain)
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
