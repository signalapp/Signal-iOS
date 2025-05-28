//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import StoreKit
import SwiftUI

class ChooseBackupPlanViewController: HostingController<ChooseBackupPlanView> {
    protocol Delegate: AnyObject {
        func chooseBackupPlanViewController(
            _ chooseBackupPlanViewController: ChooseBackupPlanViewController,
            didEnablePlan planSelection: PlanSelection
        )
    }

    enum PlanSelection {
        case free
        case paid
    }

    private let backupIdManager: BackupIdManager
    private let backupSettingsStore: BackupSettingsStore
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let db: DB
    private let tsAccountManager: TSAccountManager

    private let viewModel: ChooseBackupPlanViewModel

    weak var delegate: Delegate?

    convenience init(
        initialPlanSelection: PlanSelection?,
        paidPlanDisplayPrice: String,
    ) {
        self.init(
            initialPlanSelection: initialPlanSelection,
            paidPlanDisplayPrice: paidPlanDisplayPrice,
            backupIdManager: DependenciesBridge.shared.backupIdManager,
            backupSettingsStore: BackupSettingsStore(),
            backupSubscriptionManager: DependenciesBridge.shared.backupSubscriptionManager,
            db: DependenciesBridge.shared.db,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager
        )
    }

    init(
        initialPlanSelection: PlanSelection?,
        paidPlanDisplayPrice: String,
        backupIdManager: BackupIdManager,
        backupSettingsStore: BackupSettingsStore,
        backupSubscriptionManager: BackupSubscriptionManager,
        db: DB,
        tsAccountManager: TSAccountManager
    ) {
        self.backupIdManager = backupIdManager
        self.backupSettingsStore = backupSettingsStore
        self.backupSubscriptionManager = backupSubscriptionManager
        self.db = db
        self.tsAccountManager = tsAccountManager

        self.viewModel = ChooseBackupPlanViewModel(
            initialPlanSelection: initialPlanSelection,
            paidPlanDisplayPrice: paidPlanDisplayPrice
        )

        super.init(wrappedView: ChooseBackupPlanView(viewModel: viewModel))

        viewModel.actionsDelegate = self
    }
}

// MARK: - ChooseBackupPlanViewModel.ActionsDelegate

extension ChooseBackupPlanViewController: ChooseBackupPlanViewModel.ActionsDelegate {
    fileprivate func confirmSelection(_ planSelection: PlanSelection) {
        Task { await _confirmSelection(planSelection: planSelection) }
    }

    @MainActor
    private func _confirmSelection(planSelection: PlanSelection) async {
        func errorActionSheet(_ message: String) {
            OWSActionSheets.showActionSheet(
                message: message,
                fromViewController: self
            )
        }

        let networkErrorSheetMessage = OWSLocalizedString(
            "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_NETWORK_ERROR",
            comment: "Message shown in an action sheet when the user tries to confirm a plan selection, but encountered a network error."
        )

        // First, reserve a Backup ID. We'll need this regardless of which plan
        // the user chose, and we want to be sure it's succeeded before we
        // attempt a potential purchase. (Redeeming a Backups subscription
        // without this step will fail!)
        do {
            guard let localIdentifiers = db.read(block: { tx in
                tsAccountManager.localIdentifiers(tx: tx)
            }) else {
                return errorActionSheet(OWSLocalizedString(
                    "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_NOT_REGISTERED",
                    comment: "Message shown in an action sheet when the user tries to confirm a plan selection, but is not registered."
                ))
            }

            try await ModalActivityIndicatorViewController.presentAndPropagateResult(
                from: self
            ) {
                _ = try await self.backupIdManager.registerBackupId(
                    localIdentifiers: localIdentifiers,
                    auth: .implicit()
                )
            }
        } catch where error.isNetworkFailureOrTimeout {
            return errorActionSheet(networkErrorSheetMessage)
        } catch {
            owsFailDebug("Unexpectedly failed to register Backup ID! \(error)")
            return errorActionSheet(OWSLocalizedString(
                "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_GENERIC_ERROR",
                comment: "Message shown in an action sheet when the user tries to confirm a plan selection, but encountered a generic error."
            ))
        }

        switch planSelection {
        case .free:
            await db.awaitableWrite { tx in
                backupSettingsStore.setBackupPlan(.free, tx: tx)
            }

            delegate?.chooseBackupPlanViewController(
                self,
                didEnablePlan: planSelection
            )
        case .paid:
            let purchaseResult: BackupSubscription.PurchaseResult
            do {
                purchaseResult = try await backupSubscriptionManager.purchaseNewSubscription()
            } catch StoreKitError.networkError {
                return errorActionSheet(networkErrorSheetMessage)
            } catch {
                owsFailDebug("StoreKit purchase unexpectedly failed: \(error)")
                return errorActionSheet(OWSLocalizedString(
                    "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_PURCHASE",
                    comment: "Message shown in an action sheet when the user tries to confirm selecting the paid plan, but encountered an error from Apple while purchasing."
                ))
            }

            switch purchaseResult {
            case .success:
                // Enable Backups, so that the redemption can upgrade it to
                // .paid below.
                await db.awaitableWrite { tx in
                    backupSettingsStore.setBackupPlan(.free, tx: tx)
                }

                do {
                    try await ModalActivityIndicatorViewController.presentAndPropagateResult(
                        from: self
                    ) {
                        // This upgrades BackupPlan to .paid if it succeeds.
                        try await self.backupSubscriptionManager.redeemSubscriptionIfNecessary()
                    }
                } catch {
                    owsFailDebug("Unexpectedly failed to redeem subscription! \(error)")
                    return errorActionSheet(OWSLocalizedString(
                        "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_PURCHASE_REDEMPTION",
                        comment: "Message shown in an action sheet when the user tries to confirm selecting the paid plan, but encountered an error while redeeming their completed purchase."
                    ))
                }

                // Since BackupPlan is set to .paid when redemption succeeds, we
                // don't need to do anything here.

                delegate?.chooseBackupPlanViewController(
                    self,
                    didEnablePlan: planSelection
                )
            case .pending:
                // The subscription won't be redeemed until if/when the purchase
                // is approved, but if/when that happens BackupPlan will get set
                // set to .paid. For the time being, we can enable Backups as
                // a free-tier user!
                await db.awaitableWrite { tx in
                    backupSettingsStore.setBackupPlan(.free, tx: tx)
                }

                delegate?.chooseBackupPlanViewController(
                    self,
                    didEnablePlan: planSelection
                )
            case .userCancelled:
                // Do nothing – don't even dismiss "choose plan", to give
                // the user the chance to try again. We've reserved a Backup
                // ID at this point, but that's fine even if they don't end
                // up enabling Backups at all.
                break
            }
        }
    }
}

// MARK: -

private class ChooseBackupPlanViewModel: ObservableObject {
    typealias PlanSelection = ChooseBackupPlanViewController.PlanSelection

    protocol ActionsDelegate: AnyObject {
        func confirmSelection(_ planSelection: PlanSelection)
    }

    @Published var planSelection: PlanSelection
    let initialPlanSelection: PlanSelection?
    let paidPlanDisplayPrice: String

    weak var actionsDelegate: ActionsDelegate?

    init(
        initialPlanSelection: PlanSelection?,
        paidPlanDisplayPrice: String
    ) {
        self.planSelection = initialPlanSelection ?? .free
        self.initialPlanSelection = initialPlanSelection
        self.paidPlanDisplayPrice = paidPlanDisplayPrice
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
        VStack {
            ScrollView {
                VStack {
                    Image("backups-choose-plan")
                        .frame(width: 80, height: 80)

                    Spacer().frame(height: 8)

                    Text(OWSLocalizedString(
                        "CHOOSE_BACKUP_PLAN_TITLE",
                        comment: "Title for a view allowing users to choose a Backup plan."
                    ))
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Color.Signal.label)

                    Spacer().frame(height: 12)

                    Text(OWSLocalizedString(
                        "CHOOSE_BACKUP_PLAN_SUBTITLE",
                        comment: "Subtitle for a view allowing users to choose a Backup plan."
                    ))
                    .appendLink(CommonStrings.learnMore) {
                        // TODO: [Backups] Open Support page
                    }
                    .foregroundStyle(Color.Signal.secondaryLabel)

                    Spacer().frame(height: 20)

                    PlanOptionView(
                        title: OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_FREE_PLAN_TITLE",
                            comment: "Title for the free plan option, when choosing a Backup plan."
                        ),
                        subtitle: OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_FREE_PLAN_SUBTITLE",
                            comment: "Subtitle for the free plan option, when choosing a Backup plan."
                        ),
                        bullets: [
                            PlanOptionView.BulletPoint(iconKey: "thread", text: OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_BULLET_FULL_TEXT_BACKUP",
                                comment: "Text for a bullet point in a list of Backup features, describing that all text messages are included."
                            )),
                            PlanOptionView.BulletPoint(iconKey: "album-tilt", text: OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_BULLET_RECENT_MEDIA_BACKUP",
                                comment: "Text for a bullet point in a list of Backup features, describing that recent media is included."
                            )),
                        ],
                        isCurrentPlan: viewModel.initialPlanSelection == .free,
                        isSelected: viewModel.planSelection == .free,
                        onTap: {
                            viewModel.planSelection = .free
                        }
                    )

                    Spacer().frame(height: 16)

                    PlanOptionView(
                        title: String(
                            format: OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_PAID_PLAN_TITLE",
                                comment: "Title for the paid plan option, when choosing a Backup plan. Embeds {{ the formatted monthly cost, as currency, of the paid plan }}."
                            ),
                            viewModel.paidPlanDisplayPrice
                        ),
                        subtitle: OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_PAID_PLAN_SUBTITLE",
                            comment: "Subtitle for the paid plan option, when choosing a Backup plan."
                        ),
                        bullets: [
                            PlanOptionView.BulletPoint(iconKey: "thread", text: OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_BULLET_FULL_TEXT_BACKUP",
                                comment: "Text for a bullet point in a list of Backup features, describing that all text messages are included."
                            )),
                            PlanOptionView.BulletPoint(iconKey: "album-tilt", text: OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_BULLET_FULL_MEDIA_BACKUP",
                                comment: "Text for a bullet point in a list of Backup features, describing that all media is included."
                            )),
                            PlanOptionView.BulletPoint(iconKey: "data", text: OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_BULLET_STORAGE_AMOUNT",
                                comment: "Text for a bullet point in a list of Backup features, describing the amount of included storage."
                            )),
                        ],
                        isCurrentPlan: viewModel.initialPlanSelection == .paid,
                        isSelected: viewModel.planSelection == .paid,
                        onTap: {
                            viewModel.planSelection = .paid
                        }
                    )
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 16)
            }

            Button {
                viewModel.confirmSelection()
            } label: {
                let text = switch viewModel.planSelection {
                case .free:
                    CommonStrings.continueButton
                case .paid:
                    String(
                        format: OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_SUBSCRIBE_PAID_BUTTON_TEXT",
                            comment: "Text for a button that will subscribe the user to the paid Backup plan. Embeds {{ the formatted monthly cost, as currency, of the paid plan }}."
                        ),
                        viewModel.paidPlanDisplayPrice
                    )
                }

                Text(text)
                    .foregroundStyle(.white)
                    .font(.headline)
                    .padding(.vertical, 14)
            }
            .disabled(viewModel.planSelection == viewModel.initialPlanSelection)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .background(Color.Signal.ultramarine)
            .cornerRadius(12)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.Signal.groupedBackground)
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
                                comment: "A label indicating that a given Backup plan option is what the user has already enabled."
                            ),
                            systemImage: "checkmark"
                        )
                        .font(.footnote)
                        .foregroundStyle(Color.Signal.secondaryLabel)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background {
                            Capsule().fill(Color.Signal.secondaryFill)
                        }
                    }

                    Text(title).font(.headline)
                    Text(subtitle).foregroundStyle(Color.Signal.secondaryLabel)

                    ForEach(bullets, id: \.iconKey) { bullet in
                        Label {
                            Text(bullet.text).font(.subheadline)
                        } icon: {
                            Image(bullet.iconKey)
                                .foregroundStyle(
                                    isSelected
                                    ? Color.Signal.ultramarine
                                    : Color.Signal.label
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
                        lineWidth: isSelected ? 3 : 0
                    )
            }
            .shadow(
                color: isSelected ? .black.opacity(0.12) : .clear,
                radius: 8,
                y: 2
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: -

#if DEBUG

private extension ChooseBackupPlanViewModel {
    static func forPreview() -> ChooseBackupPlanViewModel {
        class ChoosePlanActionsDelegate: ChooseBackupPlanViewModel.ActionsDelegate {
            func confirmSelection(_ planSelection: ChooseBackupPlanViewModel.PlanSelection) {
                print("Confirming \(planSelection)")
            }
        }

        let viewModel = ChooseBackupPlanViewModel(
            initialPlanSelection: .free,
            paidPlanDisplayPrice: "$2.99"
        )
        let actionsDelegate = ChoosePlanActionsDelegate()
        ObjectRetainer.retainObject(actionsDelegate, forLifetimeOf: viewModel)
        viewModel.actionsDelegate = actionsDelegate

        return viewModel
    }
}

#Preview {
    ChooseBackupPlanView(viewModel: .forPreview())
}

#endif
