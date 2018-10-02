//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageDecrypter.h"
#import "NSData+messagePadding.h"
#import "NotificationsProtocol.h"
#import "OWSAnalytics.h"
#import "OWSBlockingManager.h"
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
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/SessionCipher.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalMetadataKit/SignalMetadataKit-Swift.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageDecrypter ()

@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;
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

    _dbConnection = primaryStorage.newDatabaseConnection;

    OWSSingletonAssert();

    return self;
}

#pragma mark - Singletons

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
    OWSAssertDebug([TSAccountManager isRegistered]);

    // successBlock is called synchronously so that we can avail ourselves of
    // the transaction.
    //
    // Ensure that failureBlock is called on a worker queue.
    DecryptFailureBlock failureBlock = ^() {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            failureBlockParameter();
        });
    };

    DecryptSuccessBlock successBlock
        = ^(NSData *envelopeData, NSData *_Nullable plaintextData, YapDatabaseReadWriteTransaction *transaction) {
              // Having received a valid (decryptable) message from this user,
              // make note of the fact that they have a valid Signal account.
              [SignalRecipient markRecipientAsRegistered:envelope.source
                                                deviceId:envelope.sourceDevice
                                             transaction:transaction];

              successBlockParameter(envelopeData, plaintextData, transaction);
          };

    @try {
        OWSLogInfo(@"decrypting envelope: %@", [self descriptionForEnvelope:envelope]);

        OWSAssertDebug(envelope.source.length > 0);
        if ([self isEnvelopeSenderBlocked:envelope]) {
            OWSLogInfo(@"ignoring blocked envelope: %@", envelope.source);
            failureBlock();
            return;
        }

        switch (envelope.type) {
            case SSKProtoEnvelopeTypeCiphertext: {
                [self decryptSecureMessage:envelope
                    envelopeData:envelopeData
                    successBlock:^(NSData *envelopeData,
                        NSData *_Nullable plaintextData,
                        YapDatabaseReadWriteTransaction *transaction) {
                        OWSLogDebug(@"decrypted secure message.");
                        successBlock(envelopeData, plaintextData, transaction);
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
                [self decryptPreKeyBundle:envelope
                    envelopeData:envelopeData
                    successBlock:^(NSData *envelopeData,
                        NSData *_Nullable plaintextData,
                        YapDatabaseReadWriteTransaction *transaction) {
                        OWSLogDebug(@"decrypted pre-key whisper message");
                        successBlock(envelopeData, plaintextData, transaction);
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
                [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    successBlock(envelopeData, nil, transaction);
                }];
                // Return to avoid double-acknowledging.
                return;
            }
            case SSKProtoEnvelopeTypeUnidentifiedSender: {
                [self decryptUnidentifiedSender:envelope
                    successBlock:^(NSData *envelopeData,
                        NSData *_Nullable plaintextData,
                        YapDatabaseReadWriteTransaction *transaction) {
                        OWSLogDebug(@"decrypted unidentified sender message");
                        successBlock(envelopeData, plaintextData, transaction);
                    }
                    failureBlock:^(NSError *_Nullable error) {
                        OWSLogError(@"decrypting unidentified sender message from address: %@ failed "
                                    @"with error: %@",
                            envelopeAddress(envelope),
                            error);
                        OWSProdError([OWSAnalyticsEvents messageManagerErrorCouldNotHandleUnidentifiedSenderMessage]);
                        failureBlock();
                    }];
                // Return to avoid double-acknowledging.
                return;
            }
            default:
                OWSLogWarn(@"Received unhandled envelope type: %d", (int)envelope.type);
                break;
        }
    } @catch (NSException *exception) {
        OWSFailDebug(@"Received an invalid envelope: %@", exception.debugDescription);
        OWSProdFail([OWSAnalyticsEvents messageManagerErrorInvalidProtocolMessage]);

        [[self.primaryStorage newDatabaseConnection]
            readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                TSErrorMessage *errorMessage = [TSErrorMessage corruptedMessageInUnknownThread];
                [SSKEnvironment.shared.notificationsManager notifyUserForThreadlessErrorMessage:errorMessage
                                                                                    transaction:transaction];
            }];
    }

    failureBlock();
}

- (void)decryptSecureMessage:(SSKProtoEnvelope *)envelope
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
            return [[WhisperMessage alloc] initWithData:encryptedData];
        }
              successBlock:successBlock
              failureBlock:failureBlock];
}

- (void)decryptPreKeyBundle:(SSKProtoEnvelope *)envelope
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
            return [[PreKeyWhisperMessage alloc] initWithData:encryptedData];
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
        failureBlock(nil);
        return;
    }

    [self.dbConnection
        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            @try {
                id<CipherMessage> cipherMessage = cipherMessageBlock(encryptedData);
                SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:self.primaryStorage
                                                                        preKeyStore:self.primaryStorage
                                                                  signedPreKeyStore:self.primaryStorage
                                                                   identityKeyStore:self.identityManager
                                                                        recipientId:recipientId
                                                                           deviceId:deviceId];

                // plaintextData may be nil for some envelope types.
                NSData *_Nullable plaintextData =
                    [[cipher decrypt:cipherMessage protocolContext:transaction] removePadding];
                successBlock(envelopeData, plaintextData, transaction);
            } @catch (NSException *exception) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [self processException:exception envelope:envelope];
                    NSString *errorDescription = [NSString
                        stringWithFormat:@"Exception while decrypting %@: %@", cipherTypeName, exception.description];
                    OWSFailDebug(@"%@", errorDescription);
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

    // Check whether we need to refresh our PreKeys every time we receive a Unidentified Sender Message.
    [TSPreKeyManager checkPreKeys];

    // NOTE: We don't need to bother with `legacyMessage` for UD messages.
    NSData *encryptedData = envelope.content;
    if (!encryptedData) {
        OWSProdFail([OWSAnalyticsEvents messageManagerErrorMessageEnvelopeHasNoContent]);
        failureBlock(nil);
        return;
    }

    if (!envelope.hasServerTimestamp) {
        OWSProdFail(@"UD Envelope is missing server timestamp.");
        failureBlock(nil);
        return;
    }
    UInt64 serverTimestamp = envelope.serverTimestamp;

    NSData *_Nullable trustRootData = [NSData dataFromBase64String:kUDTrustRoot];
    OWSAssert(trustRootData);
    NSError *error;
    ECPublicKey *_Nullable trustRoot = [[ECPublicKey alloc] initWithKeyData:trustRootData error:&error];
    if (error || !trustRoot) {
        OWSProdFail(@"Invalid UD trust root.");
        failureBlock(nil);
        return;
    }
    id<SMKCertificateValidator> certificateValidator =
        [[SMKCertificateDefaultValidator alloc] initWithTrustRoot:trustRoot];

    [self.dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        @try {
            NSError *error;
            SMKSecretSessionCipher *_Nullable cipher =
                [[SMKSecretSessionCipher alloc] initWithSessionStore:self.primaryStorage
                                                         preKeyStore:self.primaryStorage
                                                   signedPreKeyStore:self.primaryStorage
                                                       identityStore:self.identityManager
                                                               error:&error];
            if (error || !cipher) {
                NSString *errorDescription =
                    [NSString stringWithFormat:@"Could not create secret session cipher: %@", error];
                OWSFailDebug(@"%@", errorDescription);
                NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, errorDescription);
                return failureBlock(error);
            }

            SMKDecryptResult *_Nullable decryptResult =
                [cipher decryptMessageWithCertificateValidator:certificateValidator
                                                cipherTextData:encryptedData
                                                     timestamp:serverTimestamp
                                               protocolContext:transaction
                                                         error:&error];

            NSString *source = decryptResult.senderRecipientId;
            if (source.length < 1) {
                OWSProdFail(@"Invalid UD source.");
                return failureBlock(nil);
            }
            long sourceDeviceId = decryptResult.senderDeviceId;
            if (sourceDeviceId < 1 || sourceDeviceId > UINT32_MAX) {
                OWSProdFail(@"Invalid UD sender device id.");
                return failureBlock(nil);
            }
            NSData *plaintextData = [decryptResult.paddedPayload removePadding];

            SSKProtoEnvelopeBuilder *envelopeBuilder = [envelope asBuilder];
            [envelopeBuilder setSource:source];
            [envelopeBuilder setSourceDevice:(uint32_t)sourceDeviceId];
            NSData *_Nullable newEnvelopeData = [envelopeBuilder buildSerializedDataAndReturnError:&error];
            if (error || !newEnvelopeData) {
                NSString *errorDescription =
                    [NSString stringWithFormat:@"Could not update UD envelope data: %@", error];
                OWSFailDebug(@"%@", errorDescription);
                NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, errorDescription);
                return failureBlock(error);
            }

            successBlock(newEnvelopeData, plaintextData, transaction);
        } @catch (NSException *exception) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self processException:exception envelope:envelope];
                NSString *errorDescription =
                    [NSString stringWithFormat:@"Exception while decrypting ud message: %@", exception.description];
                OWSFailDebug(@"%@", errorDescription);
                NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, errorDescription);
                failureBlock(error);
            });
        }
    }];
}

- (void)processException:(NSException *)exception envelope:(SSKProtoEnvelope *)envelope
{
    OWSLogError(
        @"Got exception: %@ of type: %@ with reason: %@", exception.description, exception.name, exception.reason);


    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSErrorMessage *errorMessage;

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
            [errorMessage saveWithTransaction:transaction];
            [self notifyUserForErrorMessage:errorMessage envelope:envelope transaction:transaction];
        }
    }];
}

- (void)notifyUserForErrorMessage:(TSErrorMessage *)errorMessage
                         envelope:(SSKProtoEnvelope *)envelope
                      transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    TSThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:envelope.source transaction:transaction];
    [SSKEnvironment.shared.notificationsManager notifyUserForErrorMessage:errorMessage
                                                                   thread:contactThread
                                                              transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
