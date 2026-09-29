//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

enum RegistrationUtils {

    static var isPrimaryByDefault: Bool {
        return !UIDevice.current.isIPad
    }

    static func showReRegistrationPrompt(fromViewController viewController: UIViewController, deregisteredState: DeregisteredState) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        owsPrecondition(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true)

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
                showReRegistration(deregisteredState: deregisteredState)
            },
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)
        viewController.presentActionSheet(actionSheet)
    }

    @MainActor
    static func showReLinking(deregisteredState: DeregisteredState) {
        Logger.info("showReLinking")
        owsPrecondition(!deregisteredState.isPrimary)

        ProvisioningController.presentProvisioningFlow(skipOnboarding: true)
    }

    static func showReRegistration(deregisteredState: DeregisteredState) {
        let logger = PrefixedLogger(prefix: "[ReReg]")
        logger.info("showReRegistration")

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let preferences = SSKEnvironment.shared.preferencesRef

        owsPrecondition(deregisteredState.isPrimary)

        guard let localIdentifiers = deregisteredState.localIdentifiers.asReregisteringLocalIdentifiers else {
            owsFailDebug("couldn't fetch identifiers for re-registration")
            return
        }
        let dependencies = RegistrationCoordinatorDependencies.from(NSObject())
        let desiredMode = RegistrationMode.reRegistering(localIdentifiers)
        let loader = RegistrationCoordinatorLoaderImpl(dependencies: dependencies)
        let coordinator = databaseStorage.write { tx in
            let result = loader.coordinator(
                forDesiredMode: desiredMode,
                transaction: tx,
                logger: logger,
            )
            preferences.unsetRecordedAPNSTokens(tx: tx)
            return result
        }
        let navController = RegistrationNavigationController.withCoordinator(coordinator)
        let window: UIWindow = CurrentAppContext().mainWindow!
        window.rootViewController = navController
    }
}
