//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class BadgeThanksSheetPresenter {
    private struct Deps: Dependencies {
        static var receiptCredentialResultStore: SubscriptionReceiptCredentialResultStore {
            DependenciesBridge.shared.subscriptionReceiptCredentialResultStore
        }
    }

    private let badgeStore: BadgeStore
    private let databaseStorage: SDSDatabaseStorage
    private let receiptCredentialResultStore: SubscriptionReceiptCredentialResultStore

    private var redemptionSuccess: SubscriptionReceiptCredentialRedemptionSuccess
    private let successMode: SubscriptionReceiptCredentialResultStore.Mode

    private init(
        badgeStore: BadgeStore,
        databaseStorage: SDSDatabaseStorage,
        receiptCredentialResultStore: SubscriptionReceiptCredentialResultStore,
        redemptionSuccess: SubscriptionReceiptCredentialRedemptionSuccess,
        successMode: SubscriptionReceiptCredentialResultStore.Mode
    ) {
        self.badgeStore = badgeStore
        self.databaseStorage = databaseStorage
        self.receiptCredentialResultStore = receiptCredentialResultStore
        self.redemptionSuccess = redemptionSuccess
        self.successMode = successMode
    }

    static func loadWithSneakyTransaction(
        successMode: SubscriptionReceiptCredentialResultStore.Mode
    ) -> BadgeThanksSheetPresenter? {
        guard let redemptionSuccess = Deps.databaseStorage.read(block: { tx in
            Deps.receiptCredentialResultStore.getRedemptionSuccess(
                successMode: successMode,
                tx: tx.asV2Read
            )
        }) else {
            owsFailBeta("[Donations] Missing redemption success while trying to present badge thanks! \(successMode)")
            return nil
        }

        return BadgeThanksSheetPresenter(
            badgeStore: Deps.profileManager.badgeStore,
            databaseStorage: Deps.databaseStorage,
            receiptCredentialResultStore: Deps.receiptCredentialResultStore,
            redemptionSuccess: redemptionSuccess,
            successMode: successMode
        )
    }

    static func load(
        redemptionSuccess: SubscriptionReceiptCredentialRedemptionSuccess,
        successMode: SubscriptionReceiptCredentialResultStore.Mode
    ) -> BadgeThanksSheetPresenter {
        return BadgeThanksSheetPresenter(
            badgeStore: Deps.profileManager.badgeStore,
            databaseStorage: Deps.databaseStorage,
            receiptCredentialResultStore: Deps.receiptCredentialResultStore,
            redemptionSuccess: redemptionSuccess,
            successMode: successMode
        )
    }

    func presentBadgeThanksAndClearSuccess(
        fromViewController: UIViewController
    ) {
        let logger = PrefixedLogger(prefix: "[Donations]", suffix: "\(successMode)")
        logger.info("Preparing to present badge thanks sheet.")

        firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            return self.badgeStore.populateAssetsOnBadge(
                self.redemptionSuccess.badge
            )
        }.map(on: DispatchQueue.main) {
            logger.info("Showing badge thanks sheet on receipt credential redemption.")

            let badgeThanksSheet = BadgeThanksSheet(
                receiptCredentialRedemptionSuccess: self.redemptionSuccess
            )

            fromViewController.present(badgeThanksSheet, animated: true) {
                self.databaseStorage.write { tx in
                    self.receiptCredentialResultStore.clearRedemptionSuccess(
                        successMode: self.successMode,
                        tx: tx.asV2Write
                    )
                }
            }
        }.catch(on: DispatchQueue.global()) { _ in
            logger.error("Failed to populated badge assets for badge thanks sheet!")
        }
    }
}
