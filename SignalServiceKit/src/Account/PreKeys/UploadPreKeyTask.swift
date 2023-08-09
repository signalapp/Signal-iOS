//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension PreKeyTasks {

    internal class Upload {

        private let serviceClient: AccountServiceClient

        internal init(
            serviceClient: AccountServiceClient
        ) {
            self.serviceClient = serviceClient
        }

        func runTask(
            bundle: PreKeyUploadBundle,
            auth: ChatServiceAuth
        ) -> Promise<Void> {
            // If there is nothing to update, skip this step.
            guard !bundle.isEmpty() else { return Promise.value(()) }

            return self.serviceClient.setPreKeys(
                for: bundle.identity,
                identityKey: bundle.identityKeyPair.publicKey,
                signedPreKeyRecord: bundle.getSignedPreKey(),
                preKeyRecords: bundle.getPreKeyRecords(),
                pqLastResortPreKeyRecord: bundle.getLastResortPreKey(),
                pqPreKeyRecords: bundle.getPqPreKeyRecords(),
                auth: auth
            )
        }
    }
}

extension PreKeyUploadBundle {

    fileprivate func isEmpty() -> Bool {
        if
            getPreKeyRecords() == nil,
            getSignedPreKey() == nil,
            getLastResortPreKey() == nil,
            getPqPreKeyRecords() == nil
        {
            return true
        }
        return false
    }
}
