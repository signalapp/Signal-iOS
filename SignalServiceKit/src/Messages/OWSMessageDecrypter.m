//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageDecrypter.h"
#import "NSData+messagePadding.h"
#import "NSString+SSK.h"
#import "NotificationsProtocol.h"
#import "OWSAnalytics.h"
#import "OWSBlockingManager.h"
#import "OWSDevice.h"
#import "OWSError.h"
#import "OWSIdentityManager.h"
#import "OWSPrimaryStorage+PreKeyStore.h"
#import "OWSPrimaryStorage+SessionStore.h"
#import "OWSPrimaryStorage+SignedPreKeyStore.h"
#import "OWSPrimaryStorage.h"
#import "SSKEnvironment.h"
#import "SignalRecipient.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSErrorMessage.h"
#import "TSPreKeyManager.h"
#import <SessionAxolotlKit/AxolotlExceptions.h>
#import <SessionAxolotlKit/NSData+keyVersionByte.h>
#import <SessionAxolotlKit/SessionCipher.h>
#import <SessionCoreKit/NSData+OWS.h>
#import <SessionCoreKit/Randomness.h>
#import <SessionCoreKit/SCKExceptionWrapper.h>
#import <SessionMetadataKit/SessionMetadataKit-Swift.h>
#import <SessionServiceKit/SessionServiceKit-Swift.h>

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
@property (nonatomic) NSString *source;
@property (nonatomic) UInt32 sourceDevice;
@property (nonatomic) BOOL isUDMessage;

@end

#pragma mark -

@implementation OWSMessageDecryptResult

+ (OWSMessageDecryptResult *)resultWithEnvelopeData:(NSData *)envelopeData
                                      plaintextData:(nullable NSData *)plaintextData
                                             source:(NSString *)source
                                       sourceDevice:(UInt32)sourceDevice
                                        isUDMessage:(BOOL)isUDMessage
{
    OWSAssertDebug(envelopeData);
    OWSAssertDebug(source.length > 0);
    OWSAssertDebug(sourceDevice > 0);

    OWSMessageDecryptResult *result = [OWSMessageDecryptResult new];
    result.envelopeData = envelopeData;
    result.plaintextData = plaintextData;
    result.source = source;
    result.sourceDevice = sourceDevice;
    result.isUDMessage = isUDMessage;
    return result;
}

@end

#pragma mark -

@interface OWSMessageDecrypter ()

@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;
@property (nonatomic, readonly) LKSessionResetImplementation *sessionResetImplementation;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

#pragma mark -

@implementation OWSMessageDecrypter

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    _primaryStorage = primaryStorage;
    _sessionResetImplementation = [LKSessionResetImplementation new];
    _dbConnection = primaryStorage.newDatabaseConnection;

    OWSSingletonAssert();

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

#pragma mark - Blocking

- (BOOL)isEnvelopeSenderBlocked:(SSKProtoEnvelope *)envelope
{
    OWSAssertDebug(envelope);

    return [self.blockingManager.blockedPhoneNumbers containsObject:envelope.source];
}

#pragma mark - Decryption

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

    NSString *localRecipientId = self.tsAccountManager.localNumber;
    uint32_t localDeviceId = OWSDevicePrimaryDeviceId;
    DecryptSuccessBlock successBlock = ^(
        OWSMessageDecryptResult *result, YapDatabaseReadWriteTransaction *transaction) {
        // Ensure all blocked messages are discarded.
        if ([self isEnvelopeSenderBlocked:envelope]) {
            OWSLogInfo(@"Ignoring blocked envelope from: %@.", envelope.source);
            return failureBlock();
        }

        if ([result.source isEqualToString:localRecipientId] && result.sourceDevice == localDeviceId) {
            // Self-sent messages should be discarded during the decryption process.
            OWSFailDebug(@"Unexpected self-sent sync message.");
            return failureBlock();
        }

        // Having received a valid (decryptable) message from this user,
        // make note of the fact that they have a valid Signal account.
        [SignalRecipient markRecipientAsRegistered:result.source deviceId:result.sourceDevice transaction:transaction];

        successBlockParameter(result, transaction);
    };

    @try {
        OWSLogInfo(@"Decrypting envelope: %@.", [self descriptionForEnvelope:envelope]);

        if (envelope.type != SSKProtoEnvelopeTypeUnidentifiedSender) {
            if (!envelope.hasSource || envelope.source.length < 1 || ![ECKeyPair isValidHexEncodedPublicKeyWithCandidate:envelope.source]) {
                OWSFailDebug(@"Incoming envelope with invalid source.");
                return failureBlock();
            }
            if (!envelope.hasSourceDevice || envelope.sourceDevice < 1) {
                OWSFailDebug(@"Incoming envelope with invalid source device.");
                return failureBlock();
            }

            // We block UD messages later, after they are decrypted.
            if ([self isEnvelopeSenderBlocked:envelope]) {
                OWSLogInfo(@"Ignoring blocked envelope from: %@.", envelope.source);
                return failureBlock();
            }
        }

        switch (envelope.type) {
            case SSKProtoEnvelopeTypeCiphertext: {
                [self throws_decryptSecureMessage:envelope
                    envelopeData:envelopeData
                    successBlock:^(OWSMessageDecryptResult *result, YapDatabaseReadWriteTransaction *transaction) {
                        OWSLogDebug(@"Decrypted secure message.");
                        successBlock(result, transaction);
                    }
                    failureBlock:^(NSError *_Nullable error) {
                        OWSLogError(@"Decrypting secure message from: %@ failed with error: %@.",
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
                    successBlock:^(OWSMessageDecryptResult *result, YapDatabaseReadWriteTransaction *transaction) {
                        OWSLogDebug(@"Decrypted pre key bundle message.");
                        successBlock(result, transaction);
                    }
                    failureBlock:^(NSError *_Nullable error) {
                        OWSLogError(@"Decrypting pre key bundle message from: %@ failed with error: %@.",
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
                [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    OWSMessageDecryptResult *result =
                        [OWSMessageDecryptResult resultWithEnvelopeData:envelopeData
                                                          plaintextData:nil
                                                                 source:envelope.source
                                                           sourceDevice:envelope.sourceDevice
                                                            isUDMessage:NO];
                    successBlock(result, transaction);
                } error:nil];
                // Return to avoid double-acknowledging.
                return;
            }
            case SSKProtoEnvelopeTypeClosedGroupCiphertext: {
                [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    NSError *error = nil;
                    NSArray *plaintextAndSenderPublicKey = [LKClosedGroupUtilities decryptEnvelope:envelope transaction:transaction error:&error];
                    if (error != nil) { return failureBlock(); }
                    NSData *plaintext = plaintextAndSenderPublicKey[0];
                    NSString *senderPublicKey = plaintextAndSenderPublicKey[1];
                    SSKProtoEnvelopeBuilder *newEnvelope = [envelope asBuilder];
                    [newEnvelope setSource:senderPublicKey];
                    NSData *newEnvelopeAsData = [newEnvelope buildSerializedDataAndReturnError:&error];
                    if (error != nil) { return failureBlock(); }
                    NSString *userPublicKey = [OWSIdentityManager.sharedManager.identityKeyPair hexEncodedPublicKey];
                    if ([senderPublicKey isEqual:userPublicKey]) { return failureBlock(); }
                    OWSMessageDecryptResult *result = [OWSMessageDecryptResult resultWithEnvelopeData:newEnvelopeAsData
                                                                                        plaintextData:[plaintext removePadding]
                                                                                               source:senderPublicKey
                                                                                         sourceDevice:OWSDevicePrimaryDeviceId
                                                                                          isUDMessage:NO];
                    successBlock(result, transaction);
                } error:nil];
                return;
            }
            case SSKProtoEnvelopeTypeUnidentifiedSender: {
                [self decryptUnidentifiedSender:envelope
                    successBlock:^(OWSMessageDecryptResult *result, YapDatabaseReadWriteTransaction *transaction) {
                        OWSLogDebug(@"Decrypted unidentified sender message.");
                        successBlock(result, transaction);
                    }
                    failureBlock:^(NSError *_Nullable error) {
                        OWSLogError(@"Decrypting unidentified sender message from: %@ failed with error: %@.",
                            envelopeAddress(envelope),
                            error);
                        OWSProdError([OWSAnalyticsEvents messageManagerErrorCouldNotHandleUnidentifiedSenderMessage]);
                        failureBlock();
                    }];
                // Return to avoid double-acknowledging.
                return;
            }
            default:
                OWSLogWarn(@"Received unhandled envelope type: %d.", (int)envelope.type);
                break;
        }
    } @catch (NSException *exception) {
        OWSFailDebug(@"Received an invalid envelope: %@.", exception.debugDescription);
        OWSProdFail([OWSAnalyticsEvents messageManagerErrorInvalidProtocolMessage]);

        [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            TSErrorMessage *errorMessage = [TSErrorMessage corruptedMessageInUnknownThread];
            [SSKEnvironment.shared.notificationsManager notifyUserForThreadlessErrorMessage:errorMessage
                                                                                transaction:transaction];
        } error:nil];
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
    [TSPreKeyManager checkPreKeys];

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

    NSString *recipientId = envelope.source;
    int deviceId = envelope.sourceDevice;

    // DEPRECATED - Remove `legacyMessage` after all clients have been upgraded.
    NSData *encryptedData = envelope.content ?: envelope.legacyMessage;
    if (!encryptedData) {
        OWSProdFail([OWSAnalyticsEvents messageManagerErrorMessageEnvelopeHasNoContent]);
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, @"Envelope has no content.");
        return failureBlock(error);
    }

    [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        @try {
            id<CipherMessage> cipherMessage = cipherMessageBlock(encryptedData);
            LKSessionCipher *cipher = [[LKSessionCipher alloc]
                                       initWithSessionResetImplementation:self.sessionResetImplementation
                                       sessionStore:self.primaryStorage
                                       preKeyStore:self.primaryStorage
                                       signedPreKeyStore:self.primaryStorage
                                       identityKeyStore:self.identityManager
                                       recipientID:recipientId
                                       deviceID:deviceId];

            // plaintextData may be nil for some envelope types.
            NSError *error = nil;
            NSData *_Nullable decryptedData = [cipher decrypt:cipherMessage protocolContext:transaction error:&error];
            // Throw if we got an error
            SCKRaiseIfExceptionWrapperError(error);
            NSData *_Nullable plaintextData = decryptedData != nil ? [decryptedData removePadding] : nil;

            OWSMessageDecryptResult *result = [OWSMessageDecryptResult resultWithEnvelopeData:envelopeData
                                                                                plaintextData:plaintextData
                                                                                       source:envelope.source
                                                                                 sourceDevice:envelope.sourceDevice
                                                                                  isUDMessage:NO];
            successBlock(result, transaction);
        } @catch (NSException *exception) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self processException:exception envelope:envelope];
                NSString *errorDescription = [NSString
                    stringWithFormat:@"Exception while decrypting %@: %@.", cipherTypeName, exception.description];
                OWSLogError(@"%@", errorDescription);
                NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, errorDescription);
                failureBlock(error);
            });
        }
    }];
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

    UInt64 serverTimestamp = envelope.timestamp;

    id<SMKCertificateValidator> certificateValidator =
        [[SMKCertificateDefaultValidator alloc] initWithTrustRoot:self.udManager.trustRoot];

    NSString *localRecipientId = self.tsAccountManager.localNumber;
    uint32_t localDeviceId = OWSDevicePrimaryDeviceId;

    [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSError *cipherError;
        SMKSecretSessionCipher *_Nullable cipher =
            [[SMKSecretSessionCipher alloc] initWithSessionResetImplementation:self.sessionResetImplementation
                                                                  sessionStore:self.primaryStorage
                                                                   preKeyStore:self.primaryStorage
                                                             signedPreKeyStore:self.primaryStorage
                                                                 identityStore:self.identityManager
                                                           error:&cipherError];

        if (cipherError || !cipher) {
            OWSFailDebug(@"Could not create secret session cipher: %@.", cipherError);
            cipherError = EnsureDecryptError(cipherError, @"Could not create secret session cipher.");
            return failureBlock(cipherError);
        }

        NSError *decryptError;
        SMKDecryptResult *_Nullable decryptResult =
            [cipher throwswrapped_decryptMessageWithCertificateValidator:certificateValidator
                                                          cipherTextData:encryptedData
                                                               timestamp:serverTimestamp
                                                        localRecipientId:localRecipientId
                                                           localDeviceId:localDeviceId
                                                         protocolContext:transaction
                                                                   error:&decryptError];

        if (!decryptResult) {
            if (!decryptError) {
                OWSFailDebug(@"Caller should provide specific error.");
                NSError *error = OWSErrorWithCodeDescription(
                    OWSErrorCodeFailedToDecryptUDMessage, @"Could not decrypt UD message.");
                return failureBlock(error);
            }

            // Decrypt Failure Part 1: Unwrap failure details

            NSError *_Nullable underlyingError;
            SSKProtoEnvelope *_Nullable identifiedEnvelope;

            if (![decryptError.domain isEqualToString:@"SessionMetadataKit.SecretSessionKnownSenderError"]) {
                underlyingError = decryptError;
                identifiedEnvelope = envelope;
            } else {
                underlyingError = decryptError.userInfo[NSUnderlyingErrorKey];

                NSString *senderRecipientId
                    = decryptError.userInfo[SecretSessionKnownSenderError.kSenderRecipientIdKey];
                OWSAssert(senderRecipientId);

                NSNumber *senderDeviceId = decryptError.userInfo[SecretSessionKnownSenderError.kSenderDeviceIdKey];
                OWSAssert(senderDeviceId);

                SSKProtoEnvelopeBuilder *identifiedEnvelopeBuilder = envelope.asBuilder;
                identifiedEnvelopeBuilder.source = senderRecipientId;
                identifiedEnvelopeBuilder.sourceDevice = senderDeviceId.unsignedIntValue;
                NSError *identifiedEnvelopeBuilderError;

                identifiedEnvelope = [identifiedEnvelopeBuilder buildAndReturnError:&identifiedEnvelopeBuilderError];
                if (identifiedEnvelopeBuilderError) {
                    OWSFailDebug(@"identifiedEnvelopeBuilderError: %@", identifiedEnvelopeBuilderError);
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
                        stringWithFormat:@"Exception while decrypting UD message: %@.", underlyingException.description];
                    OWSLogError(@"%@", errorDescription);
                    NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, errorDescription);
                    failureBlock(error);
                });
                return;
            }

            if ([underlyingError.domain isEqualToString:@"SessionMetadataKit.SMKSecretSessionCipherError"]
                && underlyingError.code == SMKSecretSessionCipherErrorSelfSentMessage) {
                // Self-sent messages can be safely discarded.
                failureBlock(underlyingError);
                return;
            }

            // Attempt to recover automatically
            if ([decryptError userInfo][NSUnderlyingErrorKey] != nil) {
                NSDictionary *underlyingErrorUserInfo = [[decryptError userInfo][NSUnderlyingErrorKey] userInfo];
                if (underlyingErrorUserInfo[SCKExceptionWrapperUnderlyingExceptionKey] != nil) {
                    NSException *underlyingUnderlyingError = underlyingErrorUserInfo[SCKExceptionWrapperUnderlyingExceptionKey];
                    if ([[underlyingUnderlyingError reason] hasPrefix:@"Bad Mac!"]) {
                        if ([underlyingError userInfo][@"kSenderRecipientIdKey"] != nil) {
                            NSString *senderPublicKey = [underlyingError userInfo][@"kSenderRecipientIdKey"];
                            TSContactThread *thread = [TSContactThread getThreadWithContactId:senderPublicKey transaction:transaction];
                            if (thread != nil) {
                                [thread addSessionRestoreDevice:senderPublicKey transaction:transaction];
                                [LKSessionManagementProtocol startSessionResetInThread:thread transaction:transaction];
                            }
                        }
                    }
                }
            }

            failureBlock(underlyingError);
            return;
        }

        if (decryptResult.messageType == SMKMessageTypePrekey) {
            [TSPreKeyManager checkPreKeys];
        }

        NSString *source = decryptResult.senderRecipientId;
        if (source.length < 1) {
            NSString *errorDescription = @"Invalid UD sender.";
            OWSFailDebug(@"%@", errorDescription);
            NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, errorDescription);
            return failureBlock(error);
        }

        long sourceDeviceId = decryptResult.senderDeviceId;
        if (sourceDeviceId < 1 || sourceDeviceId > UINT32_MAX) {
            NSString *errorDescription = @"Invalid UD sender device ID.";
            OWSFailDebug(@"%@", errorDescription);
            NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, errorDescription);
            return failureBlock(error);
        }
        NSData *plaintextData = [decryptResult.paddedPayload removePadding];

        SSKProtoEnvelopeBuilder *envelopeBuilder = [envelope asBuilder];
        [envelopeBuilder setSource:source];
        [envelopeBuilder setSourceDevice:(uint32_t)sourceDeviceId];
        if (decryptResult.messageType == SMKMessageTypeFallback) {
            [envelopeBuilder setType:SSKProtoEnvelopeTypeFallbackMessage];
            OWSLogInfo(@"SMKMessageTypeFallback");
        }
        NSError *envelopeBuilderError;
        NSData *_Nullable newEnvelopeData = [envelopeBuilder buildSerializedDataAndReturnError:&envelopeBuilderError];
        if (envelopeBuilderError || !newEnvelopeData) {
            OWSFailDebug(@"Could not update UD envelope data: %@", envelopeBuilderError);
            NSError *error = EnsureDecryptError(envelopeBuilderError, @"Could not update UD envelope data");
            return failureBlock(error);
        }

        OWSMessageDecryptResult *result = [OWSMessageDecryptResult resultWithEnvelopeData:newEnvelopeData
                                                                            plaintextData:plaintextData
                                                                                   source:source
                                                                             sourceDevice:(uint32_t)sourceDeviceId
                                                                              isUDMessage:YES];
        successBlock(result, transaction);
    }];
}

- (void)processException:(NSException *)exception envelope:(SSKProtoEnvelope *)envelope
{
    OWSLogError(
        @"Got exception: %@ of type: %@ with reason: %@", exception.description, exception.name, exception.reason);

    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSErrorMessage *errorMessage;

        if (envelope.source.length == 0) {
            TSErrorMessage *errorMessage = [TSErrorMessage corruptedMessageInUnknownThread];
            [SSKEnvironment.shared.notificationsManager notifyUserForThreadlessErrorMessage:errorMessage
                                                                                transaction:transaction];
            return;
        }

        if ([exception.name isEqualToString:NoSessionException]) {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorNoSession], envelope);
            errorMessage = [TSErrorMessage missingSessionWithEnvelope:envelope withTransaction:transaction];
        } else if ([exception.name isEqualToString:InvalidKeyException]) {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorInvalidKey], envelope);
            errorMessage = [TSErrorMessage invalidKeyExceptionWithEnvelope:envelope withTransaction:transaction];
        } else if ([exception.name isEqualToString:InvalidKeyIdException]) {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorInvalidKeyId], envelope);
            errorMessage = [TSErrorMessage invalidKeyExceptionWithEnvelope:envelope withTransaction:transaction];
        } else if ([exception.name isEqualToString:DuplicateMessageException]) {
            // Duplicate messages are silently discarded.
            return;
        } else if ([exception.name isEqualToString:InvalidVersionException]) {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorInvalidMessageVersion], envelope);
            errorMessage = [TSErrorMessage invalidVersionWithEnvelope:envelope withTransaction:transaction];
        } else if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
            // Should no longer get here, since we now record the new identity for incoming messages.
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorUntrustedIdentityKeyException], envelope);
            OWSFailDebug(@"Failed to trust identity on incoming message from: %@", envelopeAddress(envelope));
            return;
        } else {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorCorruptMessage], envelope);
            errorMessage = [TSErrorMessage corruptedMessageWithEnvelope:envelope withTransaction:transaction];
        }

        OWSAssertDebug(errorMessage);
        if (errorMessage != nil) {
            [LKSessionManagementProtocol handleDecryptionError:errorMessage forPublicKey:envelope.source transaction:transaction];
            if (![LKSessionMetaProtocol isErrorMessageFromBeforeRestoration:errorMessage]) {
                [errorMessage saveWithTransaction:transaction];
                [self notifyUserForErrorMessage:errorMessage envelope:envelope transaction:transaction];
            } else {
                // Show the thread if it exists before restoration
                NSString *masterPublicKey = [LKDatabaseUtilities getMasterHexEncodedPublicKeyFor:envelope.source in:transaction] ?: envelope.source;
                TSThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:masterPublicKey transaction:transaction];
                contactThread.shouldThreadBeVisible = true;
                [contactThread saveWithTransaction:transaction];
            }
        }
    } error:nil];
}

- (void)notifyUserForErrorMessage:(TSErrorMessage *)errorMessage
                         envelope:(SSKProtoEnvelope *)envelope
                      transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSString *masterPublicKey = [LKDatabaseUtilities getMasterHexEncodedPublicKeyFor:envelope.source in:transaction] ?: envelope.source;
    TSThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:masterPublicKey transaction:transaction];
    [SSKEnvironment.shared.notificationsManager notifyUserForErrorMessage:errorMessage
                                                                   thread:contactThread
                                                              transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
