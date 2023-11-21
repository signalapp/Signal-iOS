//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit

// MARK: -

public class AccountManager: NSObject, Dependencies {

    public override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    func performInitialStorageServiceRestore(authedDevice: AuthedDevice = .implicit) -> Promise<Void> {
        return firstly {
            self.storageServiceManager.restoreOrCreateManifestIfNecessary(authedDevice: authedDevice)
        }.done {
            // In the case that we restored our profile from a previous registration,
            // re-upload it so that the user does not need to refill in all the details.
            // Right now the avatar will always be lost since we do not store avatars in
            // the storage service.

            if self.profileManager.hasProfileName || self.profileManager.localProfileAvatarData() != nil {
                Logger.debug("restored local profile name. Uploading...")
                // if we don't have a `localGivenName`, there's nothing to upload, and trying
                // to upload would fail.

                // Note we *don't* return this promise. There's no need to block registration on
                // it completing, and if there are any errors, it's durable.
                firstly {
                    self.profileManagerImpl.reuploadLocalProfilePromise(authedAccount: authedDevice.authedAccount)
                }.catch { error in
                    Logger.error("error: \(error)")
                }
            } else {
                Logger.debug("no local profile name restored.")
            }
        }.timeout(seconds: 60)
    }

    func updatePushTokens(pushToken: String, voipToken: String?) -> Promise<Void> {
        let request = OWSRequestFactory.registerForPushRequest(
            withPushIdentifier: pushToken,
            voipIdentifier: voipToken
        )
        return updatePushTokens(request: request)
    }

    func updatePushTokens(request: TSRequest) -> Promise<Void> {
        return updatePushTokens(request: request, remainingRetries: 3)
    }

    private func updatePushTokens(
        request: TSRequest,
        remainingRetries: Int
    ) -> Promise<Void> {
        return networkManager.makePromise(request: request)
            .asVoid()
            .recover(on: DispatchQueue.global()) { error -> Promise<Void> in
                if remainingRetries > 0 {
                    return self.updatePushTokens(
                        request: request,
                        remainingRetries: remainingRetries - 1
                    )
                } else {
                    owsFailDebugUnlessNetworkFailure(error)
                    return Promise(error: error)
                }
            }
    }

    // MARK: Turn Server

    func getTurnServerInfo() -> Promise<TurnServerInfo> {
        let request = OWSRequestFactory.turnServerInfoRequest()
        return firstly {
            Self.networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            guard let json = response.responseBodyJson,
                  let responseDictionary = json as? [String: AnyObject],
                  let turnServerInfo = TurnServerInfo(attributes: responseDictionary) else {
                throw OWSAssertionError("Missing or invalid JSON")
            }
            return turnServerInfo
        }
    }
}
