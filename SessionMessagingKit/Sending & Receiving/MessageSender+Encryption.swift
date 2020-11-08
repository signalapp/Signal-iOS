import SessionProtocolKit
import SessionUtilities

internal extension MessageSender {

    static func encryptWithSignalProtocol(_ plaintext: Data, for publicKey: String, using transaction: Any) throws -> Data {
        
    }

//    NSError *error;
//    LKSessionResetImplementation *sessionResetImplementation = [LKSessionResetImplementation new];
//
//    SMKSecretSessionCipher *_Nullable secretCipher =
//        [[SMKSecretSessionCipher alloc] initWithSessionResetImplementation:sessionResetImplementation
//                                                              sessionStore:self.primaryStorage
//                                                               preKeyStore:self.primaryStorage
//                                                         signedPreKeyStore:self.primaryStorage
//                                                             identityStore:self.identityManager
//                                                                     error:&error];
//    if (error || !secretCipher) {
//        OWSRaiseException(@"SecretSessionCipherFailure", @"Can't create secret session cipher.");
//    }
//
//    // Loki: The way this works is:
//    // • Alice sends a session request (i.e. a pre key bundle) to Bob using fallback encryption.
//    // • She may send any number of subsequent messages also encrypted using fallback encryption.
//    // • When Bob receives the session request, he sets up his Signal cipher session locally and sends back a null message,
//    //   now encrypted using Signal encryption.
//    // • Alice receives this, sets up her Signal cipher session locally, and sends any subsequent messages
//    //   using Signal encryption.
//
//    BOOL shouldUseFallbackEncryption = [LKSessionManagementProtocol shouldUseFallbackEncryptionForMessage:message recipientID:recipientID transaction:transaction];
//
//    if (shouldUseFallbackEncryption) {
//        [LKLogger print:@"[Loki] Using fallback encryption"];
//    } else {
//        [LKLogger print:@"[Loki] Using Signal Encryption"];
//    }
//
//    serializedMessage = [secretCipher throwswrapped_encryptMessageWithRecipientPublicKey:recipientID
//                                                                                deviceID:@(OWSDevicePrimaryDeviceId).intValue
//                                                                         paddedPlaintext:plainText.paddedMessageBody
//                                                                       senderCertificate:messageSend.senderCertificate
//                                                                         protocolContext:transaction
//                                                                useFallbackSessionCipher:shouldUseFallbackEncryption
//                                                                                   error:&error];
//
//    SCKRaiseIfExceptionWrapperError(error);
//    if (serializedMessage == nil || error != nil) {
//        OWSFailDebug(@"Error while UD encrypting message: %@.", error);
//        return nil;
//    }
//    messageType = TSUnidentifiedSenderMessageType;

    static func encryptWithSharedSenderKeys(_ plaintext: Data, for groupPublicKey: String, using transaction: Any) throws -> Data {
        // 1. ) Encrypt the data with the user's sender key
        guard let userPublicKey = Configuration.shared.storage.getUserPublicKey() else {
            SNLog("Couldn't find user key pair.")
            throw Error.noUserPublicKey
        }
        let (ivAndCiphertext, keyIndex) = try SharedSenderKeys.encrypt(plaintext, for: groupPublicKey, senderPublicKey: userPublicKey, using: transaction)
        let encryptedMessage = ClosedGroupCiphertextMessage(_throws_withIVAndCiphertext: ivAndCiphertext, senderPublicKey: Data(hex: userPublicKey), keyIndex: UInt32(keyIndex))
        // 2. ) Encrypt the result for the group's public key to hide the sender public key and key index
        let intermediate = try AESGCM.encrypt(encryptedMessage.serialized, for: groupPublicKey.removing05PrefixIfNeeded())
        // 3. ) Wrap the result
        return try SNProtoClosedGroupCiphertextMessageWrapper.builder(ciphertext: intermediate.ciphertext, ephemeralPublicKey: intermediate.ephemeralPublicKey).build().serializedData()
    }
}
