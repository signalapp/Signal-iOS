//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit
import SignalServiceKit
import SignalUI

public class RegistrationUtils: Dependencies {

    private init() {}

    class func reregister(fromViewController: UIViewController) {
        AssertIsOnMainThread()

        // If this is not the primary device, jump directly to the re-linking flow.
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true else {
            showRelinkingUI()
            return
        }

        guard
            let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction,
            let e164 = E164(localIdentifiers.phoneNumber)
        else {
            owsFailDebug("could not get local address for re-registration.")
            return
        }

        Logger.info("phoneNumber: \(e164)")

        preferences.unsetRecordedAPNSTokens()

        showReRegistration(e164: e164, aci: localIdentifiers.aci)
    }

    class func showReregistrationUI(fromViewController viewController: UIViewController) {
        // If this is not the primary device, jump directly to the re-linking flow.
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true else {
            showRelinkingUI()
            return
        }

        let actionSheet = ActionSheetController()
        actionSheet.addAction(ActionSheetAction(
            title: NSLocalizedString(
                "DEREGISTRATION_REREGISTER_WITH_SAME_PHONE_NUMBER",
                comment: "Label for button that lets users re-register using the same phone number."
            ),
            style: .destructive,
            handler: { _ in
                Logger.info("Reregistering from banner")
                RegistrationUtils.reregister(fromViewController: viewController)
            }
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)
        viewController.presentActionSheet(actionSheet)
    }

    private class func showRelinkingUI() {
        Logger.info("showRelinkingUI")

        let success = DependenciesBridge.shared.db.write { tx -> Bool in
            guard
                let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx),
                let localE164 = E164(localIdentifiers.phoneNumber)
            else {
                return false
            }
            DependenciesBridge.shared.registrationStateChangeManager.resetForReregistration(
                localPhoneNumber: localE164,
                localAci: localIdentifiers.aci,
                wasPrimaryDevice: DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx).isPrimaryDevice ?? false,
                tx: tx
            )
            return true
        }
        guard success else {
            owsFailDebug("could not reset for re-registration.")
            return
        }

        preferences.unsetRecordedAPNSTokens()
        ProvisioningController.presentRelinkingFlow()
    }

    private class func showReRegistration(e164: E164, aci: Aci) {
        Logger.info("Attempting to start re-registration")
        let dependencies = RegistrationCoordinatorDependencies.from(NSObject())
        let desiredMode = RegistrationMode.reRegistering(.init(e164: e164, aci: aci))
        let loader = RegistrationCoordinatorLoaderImpl(dependencies: dependencies)
        let coordinator = databaseStorage.write {
            return loader.coordinator(
                forDesiredMode: desiredMode,
                transaction: $0.asV2Write
            )
        }
        let navController = RegistrationNavigationController.withCoordinator(coordinator)
        let window: UIWindow = CurrentAppContext().mainWindow!
        window.rootViewController = navController
    }
}
