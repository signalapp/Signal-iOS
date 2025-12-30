//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ProvisioningPermissionsViewController: ProvisioningBaseViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.hidesBackButton = true

        let hostingController = HostingController(
            wrappedView: RegistrationPermissionsView(
                requestingContactsAuthorization: false,
                permissionTask: { [weak self] in
                    await self?.requestPermissions()
                },
            ),
        )
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    func needsToAskForAnyPermissions() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .notDetermined
    }
}

extension ProvisioningPermissionsViewController: RegistrationPermissionsPresenter {
    func requestPermissions() async {
        Logger.info("")

        // If you request any additional permissions, make sure to add them to
        // `needsToAskForAnyPermissions`.
        await AppEnvironment.shared.pushRegistrationManagerRef.registerUserNotificationSettings()
        provisioningController.provisioningPermissionsDidComplete(viewController: self)
    }
}
