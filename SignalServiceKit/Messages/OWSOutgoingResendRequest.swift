//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension OWSOutgoingResendRequest {
    @objc
    override open func buildPlainTextData(_ thread: TSThread, transaction: DBWriteTransaction) -> Data? {
        do {
            let decryptionErrorMessage = try DecryptionErrorMessage(bytes: decryptionErrorData)
            let plaintextContent = PlaintextContent(decryptionErrorMessage)
            return plaintextContent.serialize()
        } catch {
            owsFailDebug("Failed to build plaintext: \(error)")
            return nil
        }
    }
}
