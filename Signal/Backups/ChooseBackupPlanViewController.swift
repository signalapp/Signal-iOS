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

    private let backupIdManager: BackupIdManager
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let tsAccountManager: TSAccountManager

    private let onConfirmPlanSelectionBlock: OnConfirmPlanSelectionBlock
    private let viewModel: ChooseBackupPlanViewModel

    init(
        initialPlanSelection: PlanSelection?,
        storeKitAvailability: StoreKitAvailability,
        backupIdManager: BackupIdManager,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
        tsAccountManager: TSAccountManager,
        onConfirmPlanSelectionBlock: @escaping OnConfirmPlanSelectionBlock,
    ) {
        self.backupIdManager = backupIdManager
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.tsAccountManager = tsAccountManager

        self.onConfirmPlanSelectionBlock = onConfirmPlanSelectionBlock
        self.viewModel = ChooseBackupPlanViewModel(
            initialPlanSelection: initialPlanSelection,
            storeKitAvailability: storeKitAvailability,
        )

        super.init(wrappedView: ChooseBackupPlanView(viewModel: viewModel))

        viewModel.actionsDelegate = self
    }

    static func load(
        fromViewController: UIViewController,
        initialPlanSelection: PlanSelection?,
        onConfirmPlanSelectionBlock: @escaping OnConfirmPlanSelectionBlock,
    ) async throws(OWSAssertionError) -> ChooseBackupPlanViewController {
        let storeKitAvailability: StoreKitAvailability
        if FeatureFlags.Backups.avoidStoreKitForTesters {
            storeKitAvailability = .unavailableForTesters
        } else {
            let backupSubscriptionManager = DependenciesBridge.shared.backupSubscriptionManager

            let paidPlanDisplayPrice: String
            do {
                paidPlanDisplayPrice = try await ModalActivityIndicatorViewController
                    .presentAndPropagateResult(from: fromViewController) {
                        try await backupSubscriptionManager.subscriptionDisplayPrice()
                    }
            } catch {
                throw OWSAssertionError("Failed to get paidPlanDisplayPrice!")
            }

            storeKitAvailability = .available(paidPlanDisplayPrice: paidPlanDisplayPrice)
        }

        return ChooseBackupPlanViewController(
            initialPlanSelection: initialPlanSelection,
            storeKitAvailability: storeKitAvailability,
            backupIdManager: DependenciesBridge.shared.backupIdManager,
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
        onConfirmPlanSelectionBlock(self, planSelection)
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
    let storeKitAvailability: StoreKitAvailability

    weak var actionsDelegate: ActionsDelegate?

    init(
        initialPlanSelection: PlanSelection?,
        storeKitAvailability: StoreKitAvailability,
    ) {
        self.planSelection = initialPlanSelection ?? .free

        self.initialPlanSelection = initialPlanSelection
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
                    title: {
                        switch viewModel.storeKitAvailability {
                        case .available(let paidPlanDisplayPrice):
                            String(
                                format: OWSLocalizedString(
                                    "CHOOSE_BACKUP_PLAN_PAID_PLAN_TITLE",
                                    comment: "Title for the paid plan option, when choosing a Backup plan. Embeds {{ the formatted monthly cost, as currency, of the paid plan }}."
                                ),
                                paidPlanDisplayPrice
                            )
                        case .unavailableForTesters:
                            OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_PAID_PLAN_NO_PURCHASES_TITLE",
                                comment: "Title for the paid plan option, when choosing a Backup plan as a tester."
                            )
                        }
                    }(),
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
        } pinnedFooter: {
            Button {
                viewModel.confirmSelection()
            } label: {
                let text = switch viewModel.planSelection {
                case .free:
                    CommonStrings.continueButton
                case .paid:
                    switch viewModel.storeKitAvailability {
                    case .available(let paidPlanDisplayPrice):
                        String(
                            format: OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_SUBSCRIBE_PAID_BUTTON_TEXT",
                                comment: "Text for a button that will subscribe the user to the paid Backup plan. Embeds {{ the formatted monthly cost, as currency, of the paid plan }}."
                            ),
                            paidPlanDisplayPrice
                        )
                    case .unavailableForTesters:
                        CommonStrings.continueButton
                    }
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
        .multilineTextAlignment(.center)
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
            storeKitAvailability: storeKitAvailability
        )
        let actionsDelegate = ChoosePlanActionsDelegate()
        ObjectRetainer.retainObject(actionsDelegate, forLifetimeOf: viewModel)
        viewModel.actionsDelegate = actionsDelegate

        return viewModel
    }
}

#Preview("Purchases") {
    ChooseBackupPlanView(viewModel: .forPreview(
        storeKitAvailability: .available(paidPlanDisplayPrice: "$1.99")
    ))
}

#Preview("No Purchases") {
    ChooseBackupPlanView(viewModel: .forPreview(
        storeKitAvailability: .unavailableForTesters
    ))
}

#endif
