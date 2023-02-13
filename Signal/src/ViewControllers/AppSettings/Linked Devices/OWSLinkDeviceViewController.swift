//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalMessaging
import SignalServiceKit

extension OWSLinkDeviceViewController {
    @objc
    func provisionWithUrl(_ deviceProvisioningUrl: DeviceProvisioningURL) {
        // Optimistically set this flag.
        OWSDeviceManager.shared().setMayHaveLinkedDevices()

        let aciIdentityKeyPair = identityManager.identityKeyPair(for: .aci)
        let pniIdentityKeyPair = identityManager.identityKeyPair(for: .pni)
        let accountAddress = tsAccountManager.localAddress
        let pni = tsAccountManager.localPni
        let myProfileKeyData = profileManager.localProfileKey().keyData
        let areReadReceiptsEnabled = receiptManager.areReadReceiptsEnabled()

        guard let myAci = accountAddress?.uuid, let myPhoneNumber = accountAddress?.phoneNumber else {
            owsFail("Can't provision without an aci & phone number.")
        }
        guard let aciIdentityKeyPair else {
            owsFail("Can't provision without an aci identity.")
        }

        let deviceProvisioner = OWSDeviceProvisioner(
            myAciIdentityKeyPair: aciIdentityKeyPair.identityKeyPair,
            myPniIdentityKeyPair: pniIdentityKeyPair?.identityKeyPair,
            theirPublicKey: deviceProvisioningUrl.publicKey,
            theirEphemeralDeviceId: deviceProvisioningUrl.ephemeralDeviceId,
            myAci: myAci,
            myPhoneNumber: myPhoneNumber,
            myPni: pni,
            profileKey: myProfileKeyData,
            readReceiptsEnabled: areReadReceiptsEnabled,
            provisioningService: DeviceProvisioningServiceImpl(
                networkManager: networkManager,
                schedulers: DependenciesBridge.shared.schedulers
            ),
            schedulers: DependenciesBridge.shared.schedulers
        )

        deviceProvisioner.provision().map(on: DispatchQueue.main) {
            Logger.info("Successfully provisioned device.")

            self.delegate?.expectMoreDevices()
            self.popToLinkedDeviceList()

            // The service implementation of the socket connection caches the linked
            // device state, so all sync message sends will fail on the socket until it
            // is cycled.
            self.socketManager.cycleSocket()

            // Fetch the local profile to determine if all linked devices support UD.
            self.profileManager.fetchLocalUsersProfile()

        }.catch(on: DispatchQueue.main) { error in
            Logger.error("Failed to provision device with error: \(error)")
            self.presentActionSheet(self.retryActionSheetController(error: error, retryBlock: { [weak self] in
                self?.provisionWithUrl(deviceProvisioningUrl)
            }))
        }
    }

    private func retryActionSheetController(error: Error, retryBlock: @escaping () -> Void) -> ActionSheetController {
        switch error {
        case let error as DeviceLimitExceededError:
            let actionSheet = ActionSheetController(
                title: error.errorDescription,
                message: error.recoverySuggestion
            )
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.okButton,
                handler: { [weak self] _ in
                    self?.popToLinkedDeviceList()
                }
            ))
            return actionSheet

        default:
            let actionSheet = ActionSheetController(
                title: NSLocalizedString("LINKING_DEVICE_FAILED_TITLE", comment: "Alert Title"),
                message: error.userErrorDescription
            )
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.retryButton,
                style: .default,
                handler: { action in retryBlock() }
            ))
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.cancelButton,
                style: .cancel,
                handler: { [weak self] action in
                    DispatchQueue.main.async { self?.dismiss(animated: true) }
                }
            ))
            return actionSheet
        }
    }
}
