//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageDecrypter.h"
#import "NSData+messagePadding.h"
#import "NotificationsProtocol.h"
#import "OWSAnalytics.h"
#import "OWSBlockingManager.h"
#import "OWSError.h"
#import "OWSIdentityManager.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSErrorMessage.h"
#import "TSPreKeyManager.h"
#import "TSStorageManager+PreKeyStore.h"
#import "TSStorageManager+SessionStore.h"
#import "TSStorageManager+SignedPreKeyStore.h"
#import "TSStorageManager.h"
#import "TextSecureKitEnv.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/SessionCipher.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageDecrypter ()

@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) OWSIdentityManager *identityManager;

@end

#pragma mark -

@implementation OWSMessageDecrypter

+ (instancetype)sharedManager
{
    static OWSMessageDecrypter *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    OWSIdentityManager *identityManager = [OWSIdentityManager sharedManager];
    OWSBlockingManager *blockingManager = [OWSBlockingManager sharedManager];

    return [self initWithStorageManager:storageManager identityManager:identityManager blockingManager:blockingManager];
}

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
                       identityManager:(OWSIdentityManager *)identityManager
                       blockingManager:(OWSBlockingManager *)blockingManager
{
    self = [super init];

    if (!self) {
        return self;
    }

    _storageManager = storageManager;
    _identityManager = identityManager;
    _blockingManager = blockingManager;

    _dbConnection = storageManager.newDatabaseConnection;

    OWSSingletonAssert();

    return self;
}

#pragma mark - Blocking

- (BOOL)isEnvelopeBlocked:(OWSSignalServiceProtosEnvelope *)envelope
{
    OWSAssert(envelope);

    return [_blockingManager.blockedPhoneNumbers containsObject:envelope.source];
}

#pragma mark - Decryption

- (void)decryptEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
           successBlock:(DecryptSuccessBlock)successBlockParameter
           failureBlock:(DecryptFailureBlock)failureBlockParameter
{
    OWSAssert(envelope);
    OWSAssert(successBlockParameter);
    OWSAssert(failureBlockParameter);
    OWSAssert([TSAccountManager isRegistered]);

    // Ensure that successBlock and failureBlock are called on a worker queue.
    DecryptSuccessBlock successBlock = ^(NSData *_Nullable plaintextData) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            successBlockParameter(plaintextData);
        });
    };
    DecryptFailureBlock failureBlock = ^() {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            failureBlockParameter();
        });
    };
    DDLogInfo(@"%@ decrypting envelope: %@", self.tag, [self descriptionForEnvelope:envelope]);

    OWSAssert(envelope.source.length > 0);
    if ([self isEnvelopeBlocked:envelope]) {
        DDLogInfo(@"%@ ignoring blocked envelope: %@", self.tag, envelope.source);
        failureBlock();
        return;
    }

    @try {
        switch (envelope.type) {
            case OWSSignalServiceProtosEnvelopeTypeCiphertext: {
                [self decryptSecureMessage:envelope
                    successBlock:^(NSData *_Nullable plaintextData) {
                        DDLogDebug(@"%@ decrypted secure message.", self.tag);
                        successBlock(plaintextData);
                    }
                    failureBlock:^(NSError *_Nullable error) {
                        DDLogError(@"%@ decrypting secure message from address: %@ failed with error: %@",
                            self.tag,
                            envelopeAddress(envelope),
                            error);
                        OWSProdError([OWSAnalyticsEvents messageManagerErrorCouldNotHandleSecureMessage]);
                        failureBlock();
                    }];
                // Return to avoid double-acknowledging.
                return;
            }
            case OWSSignalServiceProtosEnvelopeTypePrekeyBundle: {
                [self decryptPreKeyBundle:envelope
                    successBlock:^(NSData *_Nullable plaintextData) {
                        DDLogDebug(@"%@ decrypted pre-key whisper message", self.tag);
                        successBlock(plaintextData);
                    }
                    failureBlock:^(NSError *_Nullable error) {
                        DDLogError(@"%@ decrypting pre-key whisper message from address: %@ failed "
                                   @"with error: %@",
                            self.tag,
                            envelopeAddress(envelope),
                            error);
                        OWSProdError([OWSAnalyticsEvents messageManagerErrorCouldNotHandlePrekeyBundle]);
                        failureBlock();
                    }];
                // Return to avoid double-acknowledging.
                return;
            }
            // These message types don't have a payload to decrypt.
            case OWSSignalServiceProtosEnvelopeTypeReceipt:
            case OWSSignalServiceProtosEnvelopeTypeKeyExchange:
            case OWSSignalServiceProtosEnvelopeTypeUnknown:
                successBlock(nil);
                // Return to avoid double-acknowledging.
                return;
            default:
                DDLogWarn(@"Received unhandled envelope type: %d", (int)envelope.type);
                break;
        }
    } @catch (NSException *exception) {
        DDLogError(@"Received an incorrectly formatted protocol buffer: %@", exception.debugDescription);
        OWSProdFail([OWSAnalyticsEvents messageManagerErrorInvalidProtocolMessage]);
    }

    failureBlock();
}

- (void)decryptSecureMessage:(OWSSignalServiceProtosEnvelope *)envelope
                successBlock:(DecryptSuccessBlock)successBlock
                failureBlock:(void (^)(NSError *_Nullable error))failureBlock
{
    OWSAssert(envelope);
    OWSAssert(successBlock);
    OWSAssert(failureBlock);

    [self decryptEnvelope:envelope
        cipherTypeName:@"Secure Message"
        missingPayloadBlock:^{
            OWSProdFail([OWSAnalyticsEvents messageManagerErrorMessageEnvelopeHasNoContent]);
        }
        cipherMessageBlock:^(NSData *encryptedData) {
            return [[WhisperMessage alloc] initWithData:encryptedData];
        }
        successBlock:successBlock
        failureBlock:failureBlock];
}

- (void)decryptPreKeyBundle:(OWSSignalServiceProtosEnvelope *)envelope
               successBlock:(DecryptSuccessBlock)successBlock
               failureBlock:(void (^)(NSError *_Nullable error))failureBlock
{
    OWSAssert(envelope);
    OWSAssert(successBlock);
    OWSAssert(failureBlock);

    // Check whether we need to refresh our PreKeys every time we receive a PreKeyWhisperMessage.
    [TSPreKeyManager checkPreKeys];

    [self decryptEnvelope:envelope
        cipherTypeName:@"PreKey Bundle"
        missingPayloadBlock:^{
            OWSProdFail([OWSAnalyticsEvents messageManagerErrorPrekeyBundleEnvelopeHasNoContent]);
        }
        cipherMessageBlock:^(NSData *encryptedData) {
            return [[PreKeyWhisperMessage alloc] initWithData:encryptedData];
        }
        successBlock:successBlock
        failureBlock:failureBlock];
}

- (void)decryptEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
         cipherTypeName:(NSString *)cipherTypeName
    missingPayloadBlock:(void (^_Nonnull)())missingPayloadBlock
     cipherMessageBlock:(id<CipherMessage> (^_Nonnull)(NSData *))cipherMessageBlock
           successBlock:(DecryptSuccessBlock)successBlock
           failureBlock:(void (^)(NSError *_Nullable error))failureBlock
{
    OWSAssert(envelope);
    OWSAssert(cipherTypeName.length > 0);
    OWSAssert(missingPayloadBlock);
    OWSAssert(cipherMessageBlock);
    OWSAssert(successBlock);
    OWSAssert(failureBlock);

    TSStorageManager *storageManager = self.storageManager;
    NSString *recipientId = envelope.source;
    int deviceId = envelope.sourceDevice;

    // DEPRECATED - Remove after all clients have been upgraded.
    NSData *encryptedData = envelope.hasContent ? envelope.content : envelope.legacyMessage;
    if (!encryptedData) {
        missingPayloadBlock();
        failureBlock(nil);
        return;
    }

    dispatch_async([OWSDispatch sessionStoreQueue], ^{
        @try {
            id<CipherMessage> cipherMessage = cipherMessageBlock(encryptedData);
            SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storageManager
                                                                    preKeyStore:storageManager
                                                              signedPreKeyStore:storageManager
                                                               identityKeyStore:self.identityManager
                                                                    recipientId:recipientId
                                                                       deviceId:deviceId];

            NSData *plaintextData = [[cipher decrypt:cipherMessage] removePadding];
            successBlock(plaintextData);
        } @catch (NSException *exception) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self processException:exception envelope:envelope];
                NSString *errorDescription = [NSString
                    stringWithFormat:@"Exception while decrypting %@: %@", cipherTypeName, exception.description];
                NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, errorDescription);
                failureBlock(error);
            });
        }
    });
}

- (void)processException:(NSException *)exception envelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    OWSAssert([NSThread isMainThread]);

    DDLogError(@"%@ Got exception: %@ of type: %@ with reason: %@",
        self.tag,
        exception.description,
        exception.name,
        exception.reason);

    __block TSErrorMessage *errorMessage;
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
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
            // Duplicate messages are dismissed
            return;
        } else if ([exception.name isEqualToString:InvalidVersionException]) {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorInvalidMessageVersion], envelope);
            errorMessage = [TSErrorMessage invalidVersionWithEnvelope:envelope withTransaction:transaction];
        } else if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
            // Should no longer get here, since we now record the new identity for incoming messages.
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorUntrustedIdentityKeyException], envelope);
            OWSFail(@"%@ Failed to trust identity on incoming message from: %@", self.tag, envelopeAddress(envelope));
            return;
        } else {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorCorruptMessage], envelope);
            errorMessage = [TSErrorMessage corruptedMessageWithEnvelope:envelope withTransaction:transaction];
        }

        [errorMessage saveWithTransaction:transaction];
    }];

    if (errorMessage != nil) {
        [self notifyForErrorMessage:errorMessage withEnvelope:envelope];
    }
}

- (void)notifyForErrorMessage:(TSErrorMessage *)errorMessage withEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    TSThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:envelope.source];
    [[TextSecureKitEnv sharedEnv].notificationsManager notifyUserForErrorMessage:errorMessage inThread:contactThread];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
