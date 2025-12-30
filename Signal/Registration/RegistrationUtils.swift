//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

public class RegistrationUtils {

    private init() {}

    class func reregister(fromViewController: UIViewController, appReadiness: AppReadinessSetter) {
        AssertIsOnMainThread()

        // If this is not the primary device, jump directly to the re-linking flow.
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true else {
            showRelinkingUI(appReadiness: appReadiness)
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

        SSKEnvironment.shared.preferencesRef.unsetRecordedAPNSTokens()

        showReRegistration(e164: e164, aci: localIdentifiers.aci, appReadiness: appReadiness)
    }

    class func showReregistrationUI(fromViewController viewController: UIViewController, appReadiness: AppReadinessSetter) {
        // If this is not the primary device, jump directly to the re-linking flow.
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true else {
            showRelinkingUI(appReadiness: appReadiness)
            return
        }

        let actionSheet = ActionSheetController(
            title: NSLocalizedString(
                "DEREGISTRATION_REREGISTER_PROMPT_TITLE",
                comment: "Title for prompt that lets users re-register using the same phone number.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: NSLocalizedString(
                "DEREGISTRATION_REREGISTER_BUTTON",
                comment: "Button that lets users re-register using the same phone number.",
            ),
            style: .default,
            handler: { _ in
                Logger.info("Reregistering from banner")
                RegistrationUtils.reregister(fromViewController: viewController, appReadiness: appReadiness)
            },
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)
        viewController.presentActionSheet(actionSheet)
    }

    private class func showRelinkingUI(appReadiness: AppReadinessSetter) {
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
                discoverability: DependenciesBridge.shared.phoneNumberDiscoverabilityManager.phoneNumberDiscoverability(tx: tx),
                wasPrimaryDevice: DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx).isPrimaryDevice ?? false,
                tx: tx,
            )
            return true
        }
        guard success else {
            owsFailDebug("could not reset for re-registration.")
            return
        }

        SSKEnvironment.shared.preferencesRef.unsetRecordedAPNSTokens()
        ProvisioningController.presentRelinkingFlow(appReadiness: appReadiness)
    }

    private class func showReRegistration(e164: E164, aci: Aci, appReadiness: AppReadinessSetter) {
        Logger.info("Attempting to start re-registration")
        let dependencies = RegistrationCoordinatorDependencies.from(NSObject())
        let desiredMode = RegistrationMode.reRegistering(.init(e164: e164, aci: aci))
        let loader = RegistrationCoordinatorLoaderImpl(dependencies: dependencies)
        let coordinator = SSKEnvironment.shared.databaseStorageRef.write {
            return loader.coordinator(
                forDesiredMode: desiredMode,
                transaction: $0,
            )
        }
        let navController = RegistrationNavigationController.withCoordinator(coordinator, appReadiness: appReadiness)
        let window: UIWindow = CurrentAppContext().mainWindow!
        window.rootViewController = navController
    }
}
