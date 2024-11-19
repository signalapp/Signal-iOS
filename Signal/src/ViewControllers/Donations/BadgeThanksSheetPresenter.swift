//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class BadgeThanksSheetPresenter {
    private struct Deps {
        static var donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore {
            DependenciesBridge.shared.donationReceiptCredentialResultStore
        }
    }

    private let badgeStore: BadgeStore
    private let databaseStorage: SDSDatabaseStorage
    private let donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore

    private var redemptionSuccess: DonationReceiptCredentialRedemptionSuccess
    private let successMode: DonationReceiptCredentialResultStore.Mode

    private init(
        badgeStore: BadgeStore,
        databaseStorage: SDSDatabaseStorage,
        donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore,
        redemptionSuccess: DonationReceiptCredentialRedemptionSuccess,
        successMode: DonationReceiptCredentialResultStore.Mode
    ) {
        self.badgeStore = badgeStore
        self.databaseStorage = databaseStorage
        self.donationReceiptCredentialResultStore = donationReceiptCredentialResultStore
        self.redemptionSuccess = redemptionSuccess
        self.successMode = successMode
    }

    static func loadWithSneakyTransaction(
        successMode: DonationReceiptCredentialResultStore.Mode
    ) -> BadgeThanksSheetPresenter? {
        guard let redemptionSuccess = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
            Deps.donationReceiptCredentialResultStore.getRedemptionSuccess(
                successMode: successMode,
                tx: tx.asV2Read
            )
        }) else {
            owsFailBeta("[Donations] Missing redemption success while trying to present badge thanks! \(successMode)")
            return nil
        }

        return BadgeThanksSheetPresenter(
            badgeStore: SSKEnvironment.shared.profileManagerRef.badgeStore,
            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
            donationReceiptCredentialResultStore: Deps.donationReceiptCredentialResultStore,
            redemptionSuccess: redemptionSuccess,
            successMode: successMode
        )
    }

    static func load(
        redemptionSuccess: DonationReceiptCredentialRedemptionSuccess,
        successMode: DonationReceiptCredentialResultStore.Mode
    ) -> BadgeThanksSheetPresenter {
        return BadgeThanksSheetPresenter(
            badgeStore: SSKEnvironment.shared.profileManagerRef.badgeStore,
            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
            donationReceiptCredentialResultStore: Deps.donationReceiptCredentialResultStore,
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
            return Promise.wrapAsync { try await self.badgeStore.populateAssetsOnBadge(self.redemptionSuccess.badge) }
        }.map(on: DispatchQueue.main) {
            logger.info("Showing badge thanks sheet on receipt credential redemption.")

            let badgeThanksSheet = BadgeThanksSheet(
                receiptCredentialRedemptionSuccess: self.redemptionSuccess
            )

            fromViewController.present(badgeThanksSheet, animated: true) {
                self.databaseStorage.write { tx in
                    self.donationReceiptCredentialResultStore.setHasPresentedSuccess(
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
