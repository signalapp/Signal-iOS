//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class BackupPlanUpsellViewController: HostingController<BackupPlanUpsellView> {
    private let viewModel: BackupPlanUpsellViewModel

    init(
        titleText: String,
        bodyText: String,
        backupPlanUpsellConfiguration upsellConfig: BackupPlanUpsellConfiguration,
        onTappedSubscribe: @escaping (BackupPlanUpsellViewController) -> Void,
    ) {
        self.viewModel = BackupPlanUpsellViewModel(
            titleText: titleText,
            bodyText: bodyText,
            storageAllowanceBytes: upsellConfig.backupSubscriptionConfiguration.storageAllowanceBytes,
            storeKitAvailability: upsellConfig.storeKitAvailability,
        )

        super.init(wrappedView: BackupPlanUpsellView(viewModel: viewModel))

        viewModel.onTappedNoThanks = { [weak self] in
            self?.dismiss(animated: true)
        }
        viewModel.onTappedSubscribe = { [weak self] in
            guard let self else { return }
            onTappedSubscribe(self)
        }
    }

    static func load(
        titleTextBuilder: @escaping (DBReadTransaction) -> String,
        bodyTextBuilder: @escaping (DBReadTransaction) -> String,
        fromViewController: UIViewController,
        onTappedSubscribe: @escaping (BackupPlanUpsellViewController) -> Void,
    ) async throws(SheetDisplayableError) -> BackupPlanUpsellViewController {
        let backupSubscriptionManager = DependenciesBridge.shared.backupSubscriptionManager
        let db = DependenciesBridge.shared.db
        let subscriptionConfigManager = DependenciesBridge.shared.subscriptionConfigManager

        let upsellConfig: BackupPlanUpsellConfiguration
        let titleText: String
        let bodyText: String
        (
            upsellConfig,
            titleText,
            bodyText,
        ) = try await ModalActivityIndicatorViewController.presentAndPropagateResult(
            from: fromViewController,
        ) { () throws(SheetDisplayableError) in
            let upsellConfig = try await BackupPlanUpsellConfiguration.load(
                backupSubscriptionManager: backupSubscriptionManager,
                db: db,
                subscriptionConfigManager: subscriptionConfigManager,
            )

            return db.read { tx in
                (
                    upsellConfig,
                    titleTextBuilder(tx),
                    bodyTextBuilder(tx),
                )
            }
        }

        return BackupPlanUpsellViewController(
            titleText: titleText,
            bodyText: bodyText,
            backupPlanUpsellConfiguration: upsellConfig,
            onTappedSubscribe: onTappedSubscribe,
        )
    }
}

// MARK: -

private class BackupPlanUpsellViewModel: ObservableObject {
    let titleText: String
    let bodyText: String
    let storageAllowanceBytes: UInt64
    let storeKitAvailability: BackupPlanUpsellConfiguration.StoreKitAvailability

    var onTappedSubscribe: (() -> Void)!
    var onTappedNoThanks: (() -> Void)!

    init(
        titleText: String,
        bodyText: String,
        storageAllowanceBytes: UInt64,
        storeKitAvailability: BackupPlanUpsellConfiguration.StoreKitAvailability,
    ) {
        self.titleText = titleText
        self.bodyText = bodyText
        self.storageAllowanceBytes = storageAllowanceBytes
        self.storeKitAvailability = storeKitAvailability
    }
}

// MARK: -

struct BackupPlanUpsellView: View {
    @ObservedObject private var viewModel: BackupPlanUpsellViewModel

    fileprivate init(viewModel: BackupPlanUpsellViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollableContentPinnedFooterView {
            VStack {
                Spacer().frame(height: 32)

                Image(.backupsLogo)
                    .frame(width: 80, height: 80)

                Spacer().frame(height: 16)

                Text(viewModel.titleText)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.Signal.label)

                Spacer().frame(height: 12)

                Text(viewModel.bodyText)
                    .foregroundStyle(Color.Signal.secondaryLabel)

                Spacer().frame(height: 20)

                BackupPlanPaidOptionView(
                    storeKitAvailability: viewModel.storeKitAvailability,
                    storageAllowanceBytes: viewModel.storageAllowanceBytes,
                    bulletIconTintColor: .Signal.ultramarine,
                    isCurrentPlan: false,
                    isSelected: false,
                    showSelectionCircle: false,
                )

                BackupPlanTermsAndConditionsView()
                    .padding(.vertical, 16)
            }
            .padding(.horizontal, 16)
        } pinnedFooter: {
            Button {
                viewModel.onTappedSubscribe()
            } label: {
                let text = switch viewModel.storeKitAvailability {
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

                Text(text)
            }
            .buttonStyle(Registration.UI.LargePrimaryButtonStyle())
            .padding(.horizontal, 24)

            Spacer().frame(height: 16)

            Button {
                viewModel.onTappedNoThanks()
            } label: {
                Text(OWSLocalizedString(
                    "BACKUP_PLAN_UPSELL_NO_THANKS_BUTTON_TEXT",
                    comment: "Title for a button on a Backup plan upsell view that dismisses the upsell without subscribing.",
                ))
            }
            .buttonStyle(Registration.UI.LargeSecondaryButtonStyle())
            .padding(.horizontal, 24)
        }
        .padding(.horizontal)
        .multilineTextAlignment(.center)
        .background(Color.Signal.groupedBackground)
    }
}

// MARK: -

#if DEBUG

#Preview {
    BackupPlanUpsellView(viewModel: {
        let viewModel = BackupPlanUpsellViewModel(
            titleText: "Hot Deal on Backups Today!",
            bodyText: "For one day only, get Signal Secure Backups at a screamin' deal. Keep that media safe!",
            storageAllowanceBytes: 100 * .gigabyte,
            storeKitAvailability: .available(paidPlanDisplayPrice: "$1.99"),
        )
        viewModel.onTappedNoThanks = { print("No Thanks") }
        viewModel.onTappedSubscribe = { print("Subscribe") }
        return viewModel
    }())
}

#endif
