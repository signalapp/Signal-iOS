//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageDecrypter.h"
#import "NSData+messagePadding.h"
#import "NotificationsProtocol.h"
#import "OWSAnalytics.h"
#import "OWSBlockingManager.h"
#import "OWSDevice.h"
#import "OWSError.h"
#import "OWSIdentityManager.h"
#import "OWSOutgoingNullMessage.h"
#import "SSKEnvironment.h"
#import "SSKPreKeyStore.h"
#import "SSKSessionStore.h"
#import "SSKSignedPreKeyStore.h"
#import "SignalRecipient.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSErrorMessage.h"
#import "TSPreKeyManager.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <AxolotlKit/SessionCipher.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalCoreKit/SCKExceptionWrapper.h>
#import <SignalMetadataKit/SignalMetadataKit-Swift.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSError *EnsureDecryptError(NSError *_Nullable error, NSString *fallbackErrorDescription)
{
    if (error) {
        return error;
    }
    OWSCFailDebug(@"Caller should provide specific error");
    return OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, fallbackErrorDescription);
}

#pragma mark -

@interface OWSMessageDecryptResult ()

@property (nonatomic) NSData *envelopeData;
@property (nonatomic, nullable) NSData *plaintextData;
@property (nonatomic) SignalServiceAddress *sourceAddress;
@property (nonatomic) UInt32 sourceDevice;
@property (nonatomic) BOOL isUDMessage;

@end

#pragma mark -

@implementation OWSMessageDecryptResult

+ (OWSMessageDecryptResult *)resultWithEnvelopeData:(NSData *)envelopeData
                                      plaintextData:(nullable NSData *)plaintextData
                                      sourceAddress:(SignalServiceAddress *)sourceAddress
                                       sourceDevice:(UInt32)sourceDevice
                                        isUDMessage:(BOOL)isUDMessage
{
    OWSAssertDebug(envelopeData);
    OWSAssertDebug(sourceAddress.isValid);
    OWSAssertDebug(sourceDevice > 0);

    OWSMessageDecryptResult *result = [OWSMessageDecryptResult new];
    result.envelopeData = envelopeData;
    result.plaintextData = plaintextData;
    result.sourceAddress = sourceAddress;
    result.sourceDevice = sourceDevice;
    result.isUDMessage = isUDMessage;
    return result;
}

@end

#pragma mark -

@interface OWSMessageDecrypter ()

@property (atomic, readonly) NSMutableSet<NSString *> *senderIdsResetDuringCurrentBatch;

@end

@implementation OWSMessageDecrypter

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    _senderIdsResetDuringCurrentBatch = [NSMutableSet new];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(messageDecryptJobQueueDidFlush)
                                                 name:kNSNotificationNameMessageDecryptionDidFlushQueue
                                               object:nil];

    return self;
}

#pragma mark - Dependencies

- (OWSBlockingManager *)blockingManager
{
    OWSAssertDebug(SSKEnvironment.shared.blockingManager);

    return SSKEnvironment.shared.blockingManager;
}

- (OWSIdentityManager *)identityManager
{
    OWSAssertDebug(SSKEnvironment.shared.identityManager);

    return SSKEnvironment.shared.identityManager;
}

- (id<OWSUDManager>)udManager
{
    OWSAssertDebug(SSKEnvironment.shared.udManager);

    return SSKEnvironment.shared.udManager;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);
    
    return SSKEnvironment.shared.tsAccountManager;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (SSKSessionStore *)sessionStore
{
    return SSKEnvironment.shared.sessionStore;
}

- (SSKPreKeyStore *)preKeyStore
{
    return SSKEnvironment.shared.preKeyStore;
}

- (SSKSignedPreKeyStore *)signedPreKeyStore
{
    return SSKEnvironment.shared.signedPreKeyStore;
}

- (MessageSender *)messageSender
{
    OWSAssertDebug(SSKEnvironment.shared.messageSender);

    return SSKEnvironment.shared.messageSender;
}

- (MessageProcessing *)messageProcessing
{
    return SSKEnvironment.shared.messageProcessing;
}

- (SDSKeyValueStore *)keyValueStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"OWSMessageDecrypter"];
}

#pragma mark - Blocking

- (BOOL)isEnvelopeSenderBlocked:(SSKProtoEnvelope *)envelope
{
    OWSAssertDebug(envelope);

    return [self.blockingManager isAddressBlocked:envelope.sourceAddress];
}

#pragma mark - Decryption

- (void)messageDecryptJobQueueDidFlush
{
    // We don't want to send additional resets until we
    // have received the "empty" response from the WebSocket
    // or finished at least one REST fetch.
    if (!self.messageProcessing.hasCompletedInitialFetch) {
        return;
    }

    // We clear all recently reset sender ids any time the
    // decryption queue has drained, so that any new messages
    // that fail to decrypt will reset the session again.
    [self.senderIdsResetDuringCurrentBatch removeAllObjects];
}

- (void)decryptEnvelope:(SSKProtoEnvelope *)envelope
           envelopeData:(NSData *)envelopeData
           successBlock:(DecryptSuccessBlock)successBlockParameter
           failureBlock:(DecryptFailureBlock)failureBlockParameter
{
    OWSAssertDebug(envelope);
    OWSAssertDebug(envelopeData);
    OWSAssertDebug(successBlockParameter);
    OWSAssertDebug(failureBlockParameter);
    OWSAssertDebug([self.tsAccountManager isRegistered]);

    // successBlock is called synchronously so that we can avail ourselves of
    // the transaction.
    //
    // Ensure that failureBlock is called on a worker queue.
    DecryptFailureBlock failureBlock = ^() {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            failureBlockParameter();
        });
    };

    uint32_t localDeviceId = self.tsAccountManager.storedDeviceId;
    DecryptSuccessBlock successBlock = ^(OWSMessageDecryptResult *result, SDSAnyWriteTransaction *transaction) {
        // Ensure all blocked messages are discarded.
        if ([self isEnvelopeSenderBlocked:envelope]) {
            OWSLogInfo(@"Ignoring blocked envelope: %@", envelope.sourceAddress);
            return failureBlock();
        }

        if (result.sourceAddress.isLocalAddress && result.sourceDevice == localDeviceId) {
            // Self-sent messages should be discarded during the decryption process.
            OWSFailDebug(@"Unexpected self-sent sync message.");
            return failureBlock();
        }

        // Having received a valid (decryptable) message from this user,
        // make note of the fact that they have a valid Signal account.
        [SignalRecipient markRecipientAsRegisteredAndGet:result.sourceAddress
                                                deviceId:result.sourceDevice
                                              trustLevel:SignalRecipientTrustLevelHigh
                                             transaction:transaction];

        successBlockParameter(result, transaction);
    };

    @try {
        OWSLogInfo(@"decrypting envelope: %@", [self descriptionForEnvelope:envelope]);

        if (!envelope.hasType) {
            OWSFailDebug(@"Incoming envelope is missing type.");
            return failureBlock();
        }
        if (![SDS fitsInInt64:envelope.timestamp]) {
            OWSFailDebug(@"Invalid timestamp.");
            return failureBlock();
        }
        if (envelope.hasServerTimestamp && ![SDS fitsInInt64:envelope.serverTimestamp]) {
            OWSFailDebug(@"Invalid serverTimestamp.");
            return failureBlock();
        }

        if (envelope.unwrappedType != SSKProtoEnvelopeTypeUnidentifiedSender) {
            if (!envelope.hasValidSource) {
                OWSFailDebug(@"incoming envelope has invalid source");
                return failureBlock();
            }

            if (!envelope.hasSourceDevice || envelope.sourceDevice < 1) {
                OWSFailDebug(@"incoming envelope has invalid source device");
                return failureBlock();
            }

            // We block UD messages later, after they are decrypted.
            if ([self isEnvelopeSenderBlocked:envelope]) {
                OWSLogInfo(@"ignoring blocked envelope: %@", envelope.sourceAddress);
                return failureBlock();
            }
        }

        switch (envelope.unwrappedType) {
            case SSKProtoEnvelopeTypeCiphertext: {
                [self throws_decryptSecureMessage:envelope
                    envelopeData:envelopeData
                    successBlock:^(OWSMessageDecryptResult *result, SDSAnyWriteTransaction *transaction) {
                        OWSLogDebug(@"decrypted secure message.");
                        successBlock(result, transaction);
                    }
                    failureBlock:^(NSError *_Nullable error) {
                        OWSLogError(@"decrypting secure message from address: %@ failed with error: %@",
                            envelopeAddress(envelope),
                            error);
                        OWSProdError([OWSAnalyticsEvents messageManagerErrorCouldNotHandleSecureMessage]);
                        failureBlock();
                    }];
                // Return to avoid double-acknowledging.
                return;
            }
            case SSKProtoEnvelopeTypePrekeyBundle: {
                [self throws_decryptPreKeyBundle:envelope
                    envelopeData:envelopeData
                    successBlock:^(OWSMessageDecryptResult *result, SDSAnyWriteTransaction *transaction) {
                        OWSLogDebug(@"decrypted pre-key whisper message");
                        successBlock(result, transaction);
                    }
                    failureBlock:^(NSError *_Nullable error) {
                        OWSLogError(@"decrypting pre-key whisper message from address: %@ failed "
                                    @"with error: %@",
                            envelopeAddress(envelope),
                            error);
                        OWSProdError([OWSAnalyticsEvents messageManagerErrorCouldNotHandlePrekeyBundle]);
                        failureBlock();
                    }];
                // Return to avoid double-acknowledging.
                return;
            }
            // These message types don't have a payload to decrypt.
            case SSKProtoEnvelopeTypeReceipt:
            case SSKProtoEnvelopeTypeKeyExchange:
            case SSKProtoEnvelopeTypeUnknown: {
                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                    OWSMessageDecryptResult *result =
                        [OWSMessageDecryptResult resultWithEnvelopeData:envelopeData
                                                          plaintextData:nil
                                                          sourceAddress:envelope.sourceAddress
                                                           sourceDevice:envelope.sourceDevice
                                                            isUDMessage:NO];
                    successBlock(result, transaction);
                });
                // Return to avoid double-acknowledging.
                return;
            }
            case SSKProtoEnvelopeTypeUnidentifiedSender: {
                [self decryptUnidentifiedSender:envelope
                    successBlock:^(OWSMessageDecryptResult *result, SDSAnyWriteTransaction *transaction) {
                        OWSLogDebug(@"decrypted unidentified sender message");
                        successBlock(result, transaction);
                    }
                    failureBlock:^(NSError *_Nullable error) {
                        if (error.code != OWSErrorCodeFailedToDecryptDuplicateMessage) {
                            OWSLogError(@"decrypting unidentified sender message from address: %@ failed "
                                        @"with error: %@",
                                envelopeAddress(envelope),
                                error);
                            OWSProdError(
                                [OWSAnalyticsEvents messageManagerErrorCouldNotHandleUnidentifiedSenderMessage]);
                        }
                        failureBlock();
                    }];
                // Return to avoid double-acknowledging.
                return;
            }
            default:
                OWSLogWarn(@"Received unhandled envelope type: %d", (int)envelope.unwrappedType);
                break;
        }
    } @catch (NSException *exception) {
        OWSFailDebug(@"Received an invalid envelope: %@", exception.debugDescription);
        OWSProdFail([OWSAnalyticsEvents messageManagerErrorInvalidProtocolMessage]);

        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            ThreadlessErrorMessage *errorMessage = [ThreadlessErrorMessage corruptedMessageInUnknownThread];
            [SSKEnvironment.shared.notificationsManager notifyUserForThreadlessErrorMessage:errorMessage
                                                                                transaction:transaction];
        });
    }

    failureBlock();
}

- (void)throws_decryptSecureMessage:(SSKProtoEnvelope *)envelope
                       envelopeData:(NSData *)envelopeData
                       successBlock:(DecryptSuccessBlock)successBlock
                       failureBlock:(void (^)(NSError *_Nullable error))failureBlock
{
    OWSAssertDebug(envelope);
    OWSAssertDebug(envelopeData);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    [self decryptEnvelope:envelope
              envelopeData:envelopeData
            cipherTypeName:@"Secure Message"
        cipherMessageBlock:^(NSData *encryptedData) {
            return [[WhisperMessage alloc] init_throws_withData:encryptedData];
        }
              successBlock:successBlock
              failureBlock:failureBlock];
}

- (void)throws_decryptPreKeyBundle:(SSKProtoEnvelope *)envelope
                      envelopeData:(NSData *)envelopeData
                      successBlock:(DecryptSuccessBlock)successBlock
                      failureBlock:(void (^)(NSError *_Nullable error))failureBlock
{
    OWSAssertDebug(envelope);
    OWSAssertDebug(envelopeData);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    // Check whether we need to refresh our PreKeys every time we receive a PreKeyWhisperMessage.
    [TSPreKeyManager checkPreKeysIfNecessary];

    [self decryptEnvelope:envelope
              envelopeData:envelopeData
            cipherTypeName:@"PreKey Bundle"
        cipherMessageBlock:^(NSData *encryptedData) {
            return [[PreKeyWhisperMessage alloc] init_throws_withData:encryptedData];
        }
              successBlock:successBlock
              failureBlock:failureBlock];
}

- (void)decryptEnvelope:(SSKProtoEnvelope *)envelope
           envelopeData:(NSData *)envelopeData
         cipherTypeName:(NSString *)cipherTypeName
     cipherMessageBlock:(id<CipherMessage> (^_Nonnull)(NSData *))cipherMessageBlock
           successBlock:(DecryptSuccessBlock)successBlock
           failureBlock:(void (^)(NSError *_Nullable error))failureBlock
{
    OWSAssertDebug(envelope);
    OWSAssertDebug(envelopeData);
    OWSAssertDebug(cipherTypeName.length > 0);
    OWSAssertDebug(cipherMessageBlock);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    int deviceId = envelope.sourceDevice;

    // DEPRECATED - Remove `legacyMessage` after all clients have been upgraded.
    NSData *encryptedData = envelope.content ?: envelope.legacyMessage;
    if (!encryptedData) {
        OWSProdFail([OWSAnalyticsEvents messageManagerErrorMessageEnvelopeHasNoContent]);
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, @"Envelope has no content");
        return failureBlock(error);
    }

    DatabaseStorageAsyncWrite(
        SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
            NSString *accountIdentifier = [[OWSAccountIdFinder new] ensureAccountIdForAddress:envelope.sourceAddress
                                                                                  transaction:transaction];
            @try {
                id<CipherMessage> cipherMessage = cipherMessageBlock(encryptedData);
                SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:self.sessionStore
                                                                        preKeyStore:self.preKeyStore
                                                                  signedPreKeyStore:self.signedPreKeyStore
                                                                   identityKeyStore:self.identityManager
                                                                        recipientId:accountIdentifier
                                                                           deviceId:deviceId];

                // plaintextData may be nil for some envelope types.
                NSData *_Nullable plaintextData =
                    [[cipher throws_decrypt:cipherMessage protocolContext:transaction] removePadding];
                OWSMessageDecryptResult *result = [OWSMessageDecryptResult resultWithEnvelopeData:envelopeData
                                                                                    plaintextData:plaintextData
                                                                                    sourceAddress:envelope.sourceAddress
                                                                                     sourceDevice:envelope.sourceDevice
                                                                                      isUDMessage:NO];
                successBlock(result, transaction);
            } @catch (NSException *exception) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [self processException:exception envelope:envelope];
                    NSString *errorDescription = [NSString
                        stringWithFormat:@"Exception while decrypting %@: %@", cipherTypeName, exception.description];
                    OWSLogError(@"%@", errorDescription);
                    NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, errorDescription);
                    failureBlock(error);
                });
            }
        });
}

- (void)decryptUnidentifiedSender:(SSKProtoEnvelope *)envelope
                     successBlock:(DecryptSuccessBlock)successBlock
                     failureBlock:(void (^)(NSError *_Nullable error))failureBlock
{
    OWSAssertDebug(envelope);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    // NOTE: We don't need to bother with `legacyMessage` for UD messages.
    NSData *encryptedData = envelope.content;
    if (!encryptedData) {
        NSString *errorDescription = @"UD Envelope is missing content.";
        OWSFailDebug(@"%@", errorDescription);
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, errorDescription);
        return failureBlock(error);
    }

    if (!envelope.hasServerTimestamp) {
        NSString *errorDescription = @"UD Envelope is missing server timestamp.";
        // TODO: We're seeing incoming UD envelopes without a server timestamp on staging.
        // Until this is fixed, disabling this assert.
        //        OWSFailDebug(@"%@", errorDescription);
        OWSLogError(@"%@", errorDescription);
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, errorDescription);
        return failureBlock(error);
    }
    UInt64 serverTimestamp = envelope.serverTimestamp;
    if (![SDS fitsInInt64:serverTimestamp]) {
        NSString *errorDescription = @"Invalid serverTimestamp.";
        OWSFailDebug(@"%@", errorDescription);
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, errorDescription);
        return failureBlock(error);
    }

    id<SMKCertificateValidator> certificateValidator =
        [[SMKCertificateDefaultValidator alloc] initWithTrustRoot:self.udManager.trustRoot];

    SignalServiceAddress *localAddress = self.tsAccountManager.localAddress;
    uint32_t localDeviceId = self.tsAccountManager.storedDeviceId;

    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self decryptUnidentifiedSender:envelope
                          encryptedData:encryptedData
                   certificateValidator:certificateValidator
                           localAddress:localAddress
                          localDeviceId:localDeviceId
                        serverTimestamp:serverTimestamp
                            transaction:transaction
                           successBlock:successBlock
                           failureBlock:failureBlock];
    });
}

- (void)decryptUnidentifiedSender:(SSKProtoEnvelope *)envelope
                    encryptedData:(NSData *)encryptedData
             certificateValidator:(id<SMKCertificateValidator>)certificateValidator
                     localAddress:(SignalServiceAddress *)localAddress
                    localDeviceId:(uint32_t)localDeviceId
                  serverTimestamp:(UInt64)serverTimestamp
                      transaction:(SDSAnyWriteTransaction *)transaction
                     successBlock:(DecryptSuccessBlock)successBlock
                     failureBlock:(void (^)(NSError *_Nullable error))failureBlock
{
    NSError *cipherError;
    SMKSecretSessionCipher *_Nullable cipher =
        [[SMKSecretSessionCipher alloc] initWithSessionStore:self.sessionStore
                                                 preKeyStore:self.preKeyStore
                                           signedPreKeyStore:self.signedPreKeyStore
                                               identityStore:self.identityManager
                                                       error:&cipherError];
    if (cipherError || !cipher) {
        OWSFailDebug(@"Could not create secret session cipher: %@", cipherError);
        cipherError = EnsureDecryptError(cipherError, @"Could not create secret session cipher");
        return failureBlock(cipherError);
    }

    NSError *decryptError;
    SMKDecryptResult *_Nullable decryptResult =
        [cipher throwswrapped_decryptMessageWithCertificateValidator:certificateValidator
                                                      cipherTextData:encryptedData
                                                           timestamp:serverTimestamp
                                                           localE164:localAddress.phoneNumber
                                                           localUuid:localAddress.uuid
                                                       localDeviceId:localDeviceId
                                                     protocolContext:transaction
                                                               error:&decryptError];

    if (!decryptResult) {
        if (!decryptError) {
            OWSFailDebug(@"Caller should provide specific error");
            NSError *error
                = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, @"Could not decrypt UD message");
            return failureBlock(error);
        }

        // Decrypt Failure Part 1: Unwrap failure details

        NSError *_Nullable underlyingError;
        SSKProtoEnvelope *_Nullable identifiedEnvelope;

        if (![decryptError.domain isEqualToString:@"SignalMetadataKit.SecretSessionKnownSenderError"]) {
            underlyingError = decryptError;
            identifiedEnvelope = envelope;
        } else {
            underlyingError = decryptError.userInfo[NSUnderlyingErrorKey];

            NSString *_Nullable senderE164 = decryptError.userInfo[SecretSessionKnownSenderError.kSenderE164Key];
            NSUUID *_Nullable senderUuid = decryptError.userInfo[SecretSessionKnownSenderError.kSenderUuidKey];
            SignalServiceAddress *senderAddress =
                [[SignalServiceAddress alloc] initWithUuid:senderUuid
                                               phoneNumber:senderE164
                                                trustLevel:SignalRecipientTrustLevelHigh];
            OWSAssert(senderAddress.isValid);

            NSNumber *senderDeviceId = decryptError.userInfo[SecretSessionKnownSenderError.kSenderDeviceIdKey];
            OWSAssert(senderDeviceId);

            SSKProtoEnvelopeBuilder *identifiedEnvelopeBuilder = envelope.asBuilder;
            identifiedEnvelopeBuilder.sourceE164 = senderAddress.phoneNumber;
            identifiedEnvelopeBuilder.sourceUuid = senderAddress.uuidString;
            identifiedEnvelopeBuilder.sourceDevice = senderDeviceId.unsignedIntValue;
            NSError *identifiedEnvelopeBuilderError;

            identifiedEnvelope = [identifiedEnvelopeBuilder buildAndReturnError:&identifiedEnvelopeBuilderError];
            if (identifiedEnvelopeBuilderError) {
                OWSFailDebug(@"failure identifiedEnvelopeBuilderError: %@", identifiedEnvelopeBuilderError);
            }
        }
        OWSAssert(underlyingError);
        OWSAssert(identifiedEnvelope);

        NSException *_Nullable underlyingException;
        if ([underlyingError.domain isEqualToString:SCKExceptionWrapperErrorDomain]
            && underlyingError.code == SCKExceptionWrapperErrorThrown) {

            underlyingException = underlyingError.userInfo[SCKExceptionWrapperUnderlyingExceptionKey];
            OWSAssert(underlyingException);
        }

        // Decrypt Failure Part 2: Handle unwrapped failure details

        if (underlyingException) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self processException:underlyingException envelope:identifiedEnvelope];
                NSString *errorDescription = [NSString
                    stringWithFormat:@"Exception while decrypting ud message: %@", underlyingException.description];
                NSError *error;
                if ([underlyingException.name isEqualToString:DuplicateMessageException]) {
                    OWSLogInfo(@"%@", errorDescription);
                    error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptDuplicateMessage, errorDescription);
                } else {
                    OWSLogError(@"%@", errorDescription);
                    error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, errorDescription);
                }
                failureBlock(error);
            });
            return;
        }

        if ([underlyingError.domain isEqualToString:@"SignalMetadataKit.SMKSecretSessionCipherError"]
            && underlyingError.code == SMKSecretSessionCipherErrorSelfSentMessage) {
            // Self-sent messages can be safely discarded.
            failureBlock(underlyingError);
            return;
        }

        OWSFailDebug(@"Could not decrypt UD message: %@", underlyingError);
        failureBlock(underlyingError);
        return;
    }

    if (decryptResult.messageType == SMKMessageTypePrekey) {
        [TSPreKeyManager checkPreKeysIfNecessary];
    }

    NSString *_Nullable senderE164 = decryptResult.senderE164;
    NSUUID *_Nullable senderUuid = decryptResult.senderUuid;
    SignalServiceAddress *sourceAddress = [[SignalServiceAddress alloc] initWithUuid:senderUuid
                                                                         phoneNumber:senderE164
                                                                          trustLevel:SignalRecipientTrustLevelHigh];
    if (!sourceAddress.isValid) {
        NSString *errorDescription = [NSString stringWithFormat:@"Invalid UD sender: %@", sourceAddress];
        OWSFailDebug(@"%@", errorDescription);
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, errorDescription);
        return failureBlock(error);
    }

    long sourceDeviceId = decryptResult.senderDeviceId;
    if (sourceDeviceId < 1 || sourceDeviceId > UINT32_MAX) {
        NSString *errorDescription = @"Invalid UD sender device id.";
        OWSFailDebug(@"%@", errorDescription);
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, errorDescription);
        return failureBlock(error);
    }
    NSData *plaintextData = [decryptResult.paddedPayload removePadding];

    SSKProtoEnvelopeBuilder *envelopeBuilder = [envelope asBuilder];
    [envelopeBuilder setSourceE164:sourceAddress.phoneNumber];
    [envelopeBuilder setSourceUuid:sourceAddress.uuidString];
    [envelopeBuilder setSourceDevice:(uint32_t)sourceDeviceId];
    NSError *envelopeBuilderError;
    NSData *_Nullable newEnvelopeData = [envelopeBuilder buildSerializedDataAndReturnError:&envelopeBuilderError];
    if (envelopeBuilderError || !newEnvelopeData) {
        OWSFailDebug(@"Could not update UD envelope data: %@", envelopeBuilderError);
        NSError *error = EnsureDecryptError(envelopeBuilderError, @"Could not update UD envelope data");
        return failureBlock(error);
    }

    OWSMessageDecryptResult *result = [OWSMessageDecryptResult resultWithEnvelopeData:newEnvelopeData
                                                                        plaintextData:plaintextData
                                                                        sourceAddress:sourceAddress
                                                                         sourceDevice:(UInt32)sourceDeviceId
                                                                          isUDMessage:YES];
    successBlock(result, transaction);
}

- (void)processException:(NSException *)exception envelope:(SSKProtoEnvelope *)envelope
{
    NSString *logString = [NSString stringWithFormat:@"Got exception: %@ of type: %@ with reason: %@",
                                    exception.description,
                                    exception.name,
                                    exception.reason];
    if ([exception.name isEqualToString:DuplicateMessageException]) {
        OWSLogInfo(@"%@", logString);
        // Duplicate messages are silently discarded.
        return;
    } else {
        OWSLogError(@"%@", logString);
    }

    DatabaseStorageWrite(self.databaseStorage, (^(SDSAnyWriteTransaction *transaction) {
        TSErrorMessage *errorMessage;

        if (!envelope.sourceAddress.isValid) {
            ThreadlessErrorMessage *errorMessage = [ThreadlessErrorMessage corruptedMessageInUnknownThread];
            [SSKEnvironment.shared.notificationsManager notifyUserForThreadlessErrorMessage:errorMessage
                                                                                transaction:transaction];
            return;
        }

        TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactAddress:envelope.sourceAddress
                                                                                  transaction:transaction];

        if (envelope.hasSourceUuid) {
            // Since the message failed to decrypt, we want to reset our session
            // with this device to ensure future messages we receive are decryptable.
            // We achieve this by archiving our current session with this device.
            // It's important we don't do this if we've already recently reset the
            // session for a given device, for example if we're processing a backlog
            // of 50 message from Alice that all fail to decrypt we don't want to
            // reset the session 50 times. We acomplish this by tracking the UUID +
            // device ID pair that we have recently reset, so we can skip subsequent
            // resets. When the message decrypt queue is drained, the list of recently
            // reset IDs is cleared.

            NSString *senderId = [NSString stringWithFormat:@"%@.%d", envelope.sourceUuid, envelope.sourceDevice];

            BOOL hasResetDuringThisBatch = [self.senderIdsResetDuringCurrentBatch containsObject:senderId];

            // We only ever want to archive sessions outside of a given "batch"
            // of message decryption. In practice, this means we:
            // 1. Only archive at max once per sender while draining the initial
            //    queue after establishing the websocket connection, until we
            //    receive the empty response.
            // 2. Only archive once if we get a quick burst of messages that
            //    cannot decrypt in the decryption queue while the app is running.
            //
            // Outside of these cases, we *always* archive your current session
            // when we encounter a decryption error, so that your next message
            // send to that device should send a prekey message and establish
            // a new, healthy, session.
            if (!hasResetDuringThisBatch) {
                [self.senderIdsResetDuringCurrentBatch addObject:senderId];

                OWSLogWarn(@"Archiving session for undecryptable message from %@", senderId);
                [self.sessionStore archiveSessionForAddress:envelope.sourceAddress
                                                   deviceId:envelope.sourceDevice
                                                transaction:transaction];

                // Always notify the user that we have performed an automatic archive.
                errorMessage = [TSErrorMessage sessionRefreshWithEnvelope:envelope withTransaction:transaction];

                NSDate *_Nullable lastNullMessageDate = [self.keyValueStore getDate:senderId transaction:transaction];

                BOOL hasRecentlySentNullMessage = NO;
                if (lastNullMessageDate) {
                    hasRecentlySentNullMessage = fabs([lastNullMessageDate timeIntervalSinceNow])
                        <= RemoteConfig.automaticSessionResetAttemptInterval;
                }

                // In order to quickly get both devices into a healthy state, we
                // try and send a null message immediately to establish the new
                // session. However, we only do this at max once per a given time
                // interval so in the case the other client is continually
                // responding to our message with another message we can't decrypt,
                // we don't get in a loop where we keep responding to them.
                // In general, this should never happen because the other
                // client should be able to decrypt a prekey message.
                if (RemoteConfig.automaticSessionResetKillSwitch) {
                    OWSLogWarn(
                        @"Skipping null message after undecryptable message from %@ due to kill switch.", senderId);
                } else if (hasRecentlySentNullMessage) {
                    OWSLogWarn(
                        @"Skipping null message after undecryptable message from %@, last null message sent %llu",
                        senderId,
                        [lastNullMessageDate ows_millisecondsSince1970]);
                } else {
                    OWSLogInfo(@"Sending null message to reset session after undecryptable message from: %@", senderId);

                    [self.keyValueStore setDate:[NSDate new] key:senderId transaction:transaction];

                    OWSOutgoingNullMessage *nullMessage =
                        [[OWSOutgoingNullMessage alloc] initWithContactThread:contactThread];
                    [self.messageSender sendMessage:nullMessage.asPreparer
                        success:^{
                            OWSLogInfo(
                                @"Successfully sent null message after session reset for undecryptable message from %@",
                                senderId);
                        }
                        failure:^(NSError *error) {
                            OWSFailDebug(@"Failed to send null message after session reset for undecryptable message "
                                         @"from %@ (%@)",
                                senderId,
                                error.localizedDescription);
                        }];
                }
            } else {
                OWSLogWarn(@"Skipping session reset for undecryptable message from %@, already reset during this batch",
                    senderId);
            }
        } else {
            OWSFailDebug(@"Received envelope missing UUID %@.%d", envelope.sourceAddress, envelope.sourceDevice);
            errorMessage = [TSErrorMessage corruptedMessageWithEnvelope:envelope withTransaction:transaction];
        }

        // Log the error appropriately.
        if ([exception.name isEqualToString:NoSessionException]) {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorNoSession], envelope);
        } else if ([exception.name isEqualToString:InvalidKeyException]) {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorInvalidKey], envelope);
        } else if ([exception.name isEqualToString:InvalidKeyIdException]) {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorInvalidKeyId], envelope);
        } else if ([exception.name isEqualToString:InvalidVersionException]) {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorInvalidMessageVersion], envelope);
        } else if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
            // Should no longer get here, since we now record the new identity for incoming messages.
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorUntrustedIdentityKeyException], envelope);
            OWSFailDebug(@"Failed to trust identity on incoming message from: %@", envelopeAddress(envelope));
        } else {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorCorruptMessage], envelope);
        }

        OWSAssertDebug(errorMessage);
        if (errorMessage != nil) {
            [errorMessage anyInsertWithTransaction:transaction];
            [self notifyUserForErrorMessage:errorMessage contactThread:contactThread transaction:transaction];
        }
    }));
}

- (void)notifyUserForErrorMessage:(TSErrorMessage *)errorMessage
                    contactThread:(TSContactThread *)contactThread
                      transaction:(SDSAnyWriteTransaction *)transaction
{
    [SSKEnvironment.shared.notificationsManager notifyUserForErrorMessage:errorMessage
                                                                   thread:contactThread
                                                              transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
