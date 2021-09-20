//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalClient

extension TSInvalidIdentityKeyReceivingErrorMessage {
    @objc(identityKeyFromEncodedPreKeySignalMessage:error:)
    private func identityKey(from encodedPreKeySignalMessage: Data) throws -> Data {
        return Data(try PreKeySignalMessage(bytes: encodedPreKeySignalMessage).identityKey.keyBytes)
    }

    @objc
    public func decrypt(messagesToDecrypt: [TSInvalidIdentityKeyReceivingErrorMessage]?) {
        AssertIsOnMainThread()

        guard let messagesToDecrypt = messagesToDecrypt else {
            return
        }

        for errorMessage in messagesToDecrypt {
            guard let envelopeData = errorMessage.envelopeData else {
                owsFailDebug("Missing envelopeData.")
                continue
            }
            messageProcessor.processEncryptedEnvelopeData(envelopeData,
                                                          encryptedEnvelope: nil,
                                                          serverDeliveryTimestamp: 0,
                                                          envelopeSource: .identityChangeError) { _ in
                // Here we remove the existing error message because handleReceivedEnvelope will
                // either
                //  1.) succeed and create a new successful message in the thread or...
                //  2.) fail and create a new identical error message in the thread.
                Self.databaseStorage.write { transaction in
                    errorMessage.anyRemove(transaction: transaction)
                }
            }
        }
    }
}
