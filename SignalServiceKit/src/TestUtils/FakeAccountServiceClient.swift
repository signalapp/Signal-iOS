//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

#if TESTABLE_BUILD

@objc
public class FakeAccountServiceClient: AccountServiceClient {
    @objc
    public override init() {}

    // MARK: - Public

    public override func deprecated_requestPreauthChallenge(e164: String, pushToken: String, isVoipToken: Bool) -> Promise<Void> {
        return Promise { $0.resolve() }
    }

    public override func deprecated_requestVerificationCode(e164: String, preauthChallenge: String?, captchaToken: String?, transport: TSVerificationTransport) -> Promise<Void> {
        return Promise { $0.resolve() }
    }

    public override func getPreKeysCount(for identity: OWSIdentity) -> Promise<Int> {
        return Promise { $0.resolve(0) }
    }

    public override func setPreKeys(
        for identity: OWSIdentity,
        identityKey: IdentityKey,
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        preKeyRecords: [SignalServiceKit.PreKeyRecord],
        auth: ChatServiceAuth
    ) -> Promise<Void> {
        return .value(())
    }

    public override func setSignedPreKey(_ signedPreKey: SignalServiceKit.SignedPreKeyRecord, for identity: OWSIdentity) -> Promise<Void> {
        return Promise { $0.resolve() }
    }

    public override func updatePrimaryDeviceAccountAttributes() -> Promise<Void> {
        return Promise { $0.resolve() }
    }

    public override func getAccountWhoAmI() -> Promise<WhoAmIRequestFactory.Responses.WhoAmI> {
        return Promise {
            $0.resolve(WhoAmIRequestFactory.Responses.WhoAmI(
                aci: FutureAci.randomForTesting().uuidValue,
                pni: FuturePni.randomForTesting().uuidValue,
                e164: E164("+17735550199")!,
                usernameHash: nil
            ))
        }
    }
}

#endif
