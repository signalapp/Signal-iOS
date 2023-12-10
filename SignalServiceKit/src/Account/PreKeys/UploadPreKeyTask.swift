//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

extension PreKeyTasks {

    internal class Upload {
        enum UploadResult {
            case success
            case skipped
            /// An error in which we, a linked device, attempted an upload and
            /// were told by the server that the identity key in our bundle was
            /// incorrect.
            ///
            /// This error should never occur on a primary.
            case incorrectIdentityKeyOnLinkedDevice
            case failure(Swift.Error)
        }

        private let schedulers: Schedulers
        private let serviceClient: AccountServiceClient

        internal init(
            schedulers: Schedulers,
            serviceClient: AccountServiceClient
        ) {
            self.schedulers = schedulers
            self.serviceClient = serviceClient
        }

        func runTask(
            bundle: PreKeyUploadBundle,
            auth: ChatServiceAuth
        ) -> Guarantee<UploadResult> {
            // If there is nothing to update, skip this step.
            guard !bundle.isEmpty() else { return .value(.skipped) }

            PreKey.logger.info("[\(bundle.identity)] uploading prekeys")

            return self.serviceClient.setPreKeys(
                for: bundle.identity,
                signedPreKeyRecord: bundle.getSignedPreKey(),
                preKeyRecords: bundle.getPreKeyRecords(),
                pqLastResortPreKeyRecord: bundle.getLastResortPreKey(),
                pqPreKeyRecords: bundle.getPqPreKeyRecords(),
                auth: auth
            )
            .map(on: schedulers.sync) { () -> UploadResult in
                return .success
            }
            .recover(on: schedulers.sync) { error -> Guarantee<UploadResult> in
                switch error.httpStatusCode {
                case 403:
                    return .value(.incorrectIdentityKeyOnLinkedDevice)
                default:
                    return .value(.failure(error))
                }
            }
        }
    }
}

private extension PreKeyUploadBundle {
    func isEmpty() -> Bool {
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
