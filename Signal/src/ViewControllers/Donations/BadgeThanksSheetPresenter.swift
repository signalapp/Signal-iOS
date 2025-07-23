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

    static func fromGlobalsWithSneakyTransaction(
        successMode: DonationReceiptCredentialResultStore.Mode
    ) -> BadgeThanksSheetPresenter? {
        guard let redemptionSuccess = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
            Deps.donationReceiptCredentialResultStore.getRedemptionSuccess(
                successMode: successMode,
                tx: tx
            )
        }) else {
            owsFailBeta("[Donations] Missing redemption success while trying to present badge thanks! \(successMode)")
            return nil
        }

        return .fromGlobals(
            redemptionSuccess: redemptionSuccess,
            successMode: successMode,
        )
    }

    static func fromGlobals(
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

    @MainActor
    func presentAndRecordBadgeThanks(
        fromViewController: UIViewController
    ) async {
        let logger = PrefixedLogger(prefix: "[Donations]", suffix: "\(successMode)")
        logger.info("Preparing to present badge thanks sheet.")

        do {
            try await self.badgeStore.populateAssetsOnBadge(self.redemptionSuccess.badge)
        } catch {
            logger.error("Failed to populated badge assets for badge thanks sheet!")
            return
        }

        logger.info("Showing badge thanks sheet on receipt credential redemption.")
        let badgeThanksSheet = BadgeThanksSheet(receiptCredentialRedemptionSuccess: self.redemptionSuccess)

        await fromViewController.awaitablePresent(badgeThanksSheet, animated: true)

        await self.databaseStorage.awaitableWrite { tx in
            self.donationReceiptCredentialResultStore.setHasPresentedSuccess(
                successMode: self.successMode,
                tx: tx
            )
        }
    }
}
