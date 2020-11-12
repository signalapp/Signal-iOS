//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SessionCipher.h"
#import "AES-CBC.h"
#import "AxolotlExceptions.h"
#import "AxolotlParameters.h"
#import "ChainKey.h"
#import "MessageKeys.h"
#import "NSData+keyVersionByte.h"
#import "PreKeyStore.h"
#import "RootKey.h"
#import "SessionBuilder.h"
#import "SessionState.h"
#import "SessionStore.h"
#import "SignedPreKeyStore.h"
#import "WhisperMessage.h"
#import <Curve25519Kit/Curve25519.h>
#import <Curve25519Kit/Ed25519.h>
#import <HKDFKit/HKDFKit.h>
#import <SignalCoreKit/SCKExceptionWrapper.h>
#import <SignalCoreKit/SignalCoreKit.h>
#import <SignalCoreKit/OWSAsserts.h>

NS_ASSUME_NONNULL_BEGIN

@interface SessionCipher ()

@property (nonatomic, readonly) NSString *recipientId;
@property (nonatomic, readonly) int deviceId;

@property (nonatomic, readonly) id<IdentityKeyStore> identityKeyStore;
@property (nonatomic, readonly) id<SessionStore> sessionStore;
@property (nonatomic, readonly) SessionBuilder *sessionBuilder;
@property (nonatomic, readonly) id<PreKeyStore> prekeyStore;

@end

#pragma mark -

@implementation SessionCipher

- (instancetype)initWithAxolotlStore:(id<AxolotlStore>)sessionStore recipientId:(NSString*)recipientId deviceId:(int)deviceId{
    OWSAssert(sessionStore);
    OWSAssert(recipientId);
    return [self initWithSessionStore:sessionStore
                          preKeyStore:sessionStore
                    signedPreKeyStore:sessionStore
                     identityKeyStore:sessionStore
                          recipientId:recipientId
                             deviceId:deviceId];
}

- (instancetype)initWithSessionStore:(id<SessionStore>)sessionStore
                         preKeyStore:(id<PreKeyStore>)preKeyStore
                   signedPreKeyStore:(id<SignedPreKeyStore>)signedPreKeyStore
                    identityKeyStore:(id<IdentityKeyStore>)identityKeyStore
                         recipientId:(NSString*)recipientId
                            deviceId:(int)deviceId{
    OWSAssert(sessionStore);
    OWSAssert(preKeyStore);
    OWSAssert(signedPreKeyStore);
    OWSAssert(identityKeyStore);
    OWSAssert(recipientId);

    self = [super init];

    if (self){
        _recipientId = recipientId;
        _deviceId = deviceId;
        _sessionStore = sessionStore;
        _identityKeyStore = identityKeyStore;
        _prekeyStore = preKeyStore;
        _sessionBuilder = [[SessionBuilder alloc] initWithSessionStore:sessionStore
                                                           preKeyStore:preKeyStore
                                                     signedPreKeyStore:signedPreKeyStore
                                                      identityKeyStore:identityKeyStore
                                                           recipientId:recipientId
                                                              deviceId:deviceId];
    }

    return self;
}

- (nullable id<CipherMessage>)encryptMessage:(NSData *)paddedMessage
                             protocolContext:(nullable id)protocolContext
                                       error:(NSError **)outError
{
    __block id<CipherMessage> result;
    [SCKExceptionWrapper
        tryBlock:^{
            result = [self throws_encryptMessage:paddedMessage protocolContext:protocolContext];
        }
           error:outError];

    return result;
}

- (id<CipherMessage>)throws_encryptMessage:(NSData *)paddedMessage protocolContext:(nullable id)protocolContext
{
    OWSAssert(paddedMessage);

    SessionRecord *sessionRecord =
        [self.sessionStore loadSession:self.recipientId deviceId:self.deviceId protocolContext:protocolContext];
    SessionState *sessionState = sessionRecord.sessionState;
    ChainKey *chainKey = sessionState.senderChainKey;
    MessageKeys *messageKeys = [chainKey throws_messageKeys];
    NSData *senderRatchetKey = sessionState.senderRatchetKey;
    int previousCounter = sessionState.previousCounter;
    int sessionVersion = sessionState.version;

    if (![self.identityKeyStore isTrustedIdentityKey:sessionState.remoteIdentityKey
                                         recipientId:self.recipientId
                                           direction:TSMessageDirectionOutgoing
                                     protocolContext:protocolContext]) {
        DDLogWarn(
            @"%@ Previously known identity key for while encrypting for recipient: %@", self.tag, self.recipientId);
        @throw [NSException exceptionWithName:UntrustedIdentityKeyException
                                       reason:@"There is a previously known identity key."
                                     userInfo:@{}];
    }

    [self.identityKeyStore saveRemoteIdentity:sessionState.remoteIdentityKey
                                  recipientId:self.recipientId
                              protocolContext:protocolContext];

    NSData *ciphertextBody =
        [AES_CBC throws_encryptCBCMode:paddedMessage withKey:messageKeys.cipherKey withIV:messageKeys.iv];

    id<CipherMessage> cipherMessage =
        [[WhisperMessage alloc] init_throws_withVersion:sessionVersion
                                                 macKey:messageKeys.macKey
                                       senderRatchetKey:senderRatchetKey.prependKeyType
                                                counter:chainKey.index
                                        previousCounter:previousCounter
                                             cipherText:ciphertextBody
                                      senderIdentityKey:sessionState.localIdentityKey.prependKeyType
                                    receiverIdentityKey:sessionState.remoteIdentityKey.prependKeyType];

    if ([sessionState hasUnacknowledgedPreKeyMessage]) {
        PendingPreKey *items = [sessionState unacknowledgedPreKeyMessageItems];
        int localRegistrationId = [sessionState localRegistrationId];

        DDLogInfo(@"Building PreKeyWhisperMessage for: %@ with preKeyId: %d", self.recipientId, items.preKeyId);

        cipherMessage =
            [[PreKeyWhisperMessage alloc] init_throws_withWhisperMessage:cipherMessage
                                                          registrationId:localRegistrationId
                                                                prekeyId:items.preKeyId
                                                          signedPrekeyId:items.signedPreKeyId
                                                                 baseKey:items.baseKey.prependKeyType
                                                             identityKey:sessionState.localIdentityKey.prependKeyType];
    }

    [sessionState setSenderChainKey:[chainKey nextChainKey]];
    [self.sessionStore storeSession:self.recipientId
                           deviceId:self.deviceId
                            session:sessionRecord
                    protocolContext:protocolContext];

    return cipherMessage;
}

- (nullable NSData *)decrypt:(id<CipherMessage>)whisperMessage
             protocolContext:(nullable id)protocolContext
                       error:(NSError **)outError
{
    __block NSData *_Nullable result;
    [SCKExceptionWrapper
        tryBlock:^{
            result = [self throws_decrypt:whisperMessage protocolContext:protocolContext];
        }
           error:outError];

    return result;
}

- (NSData *)throws_decrypt:(id<CipherMessage>)whisperMessage protocolContext:(nullable id)protocolContext
{
    OWSAssert(whisperMessage);

    switch (whisperMessage.cipherMessageType) {
        case CipherMessageType_Whisper:
            if (![whisperMessage isKindOfClass:[WhisperMessage class]]) {
                OWSFail(@"Unexpected message type: %@", [whisperMessage class]);
                return nil;
            }
            return [self throws_decryptWhisperMessage:(WhisperMessage *)whisperMessage protocolContext:protocolContext];
        case CipherMessageType_Prekey:
            if (![whisperMessage isKindOfClass:[PreKeyWhisperMessage class]]) {
                OWSFail(@"Unexpected message type: %@", [whisperMessage class]);
                return nil;
            }
            return [self throws_decryptPreKeyWhisperMessage:(PreKeyWhisperMessage *)whisperMessage
                                            protocolContext:protocolContext];
        default:
            OWSFailDebug(@"Unexpected message type: %@", [whisperMessage class]);
            return [NSData new];
    }
}

- (NSData *)throws_decryptPreKeyWhisperMessage:(PreKeyWhisperMessage *)preKeyWhisperMessage
                               protocolContext:(nullable id)protocolContext
{
    OWSAssert(preKeyWhisperMessage);

    SessionRecord *sessionRecord =
        [self.sessionStore loadSession:self.recipientId deviceId:self.deviceId protocolContext:protocolContext];
    int unsignedPreKeyId = [self.sessionBuilder throws_processPrekeyWhisperMessage:preKeyWhisperMessage
                                                                       withSession:sessionRecord
                                                                   protocolContext:protocolContext];
    NSData *plaintext = [self throws_decryptWithSessionRecord:sessionRecord
                                               whisperMessage:preKeyWhisperMessage.message
                                              protocolContext:protocolContext];

    [self.sessionStore storeSession:self.recipientId
                           deviceId:self.deviceId
                            session:sessionRecord
                    protocolContext:protocolContext];

    // If there was an unsigned PreKey
    if (unsignedPreKeyId >= 0) {
        [self.prekeyStore removePreKey:unsignedPreKeyId protocolContext:protocolContext];
    }

    return plaintext;
}

- (NSData *)throws_decryptWhisperMessage:(WhisperMessage *)whisperMessage protocolContext:(nullable id)protocolContext
{
    OWSAssert(whisperMessage);

    SessionRecord *sessionRecord =
        [self.sessionStore loadSession:self.recipientId deviceId:self.deviceId protocolContext:protocolContext];
    NSData *plaintext = [self throws_decryptWithSessionRecord:sessionRecord
                                               whisperMessage:whisperMessage
                                              protocolContext:protocolContext];

    if (![self.identityKeyStore isTrustedIdentityKey:sessionRecord.sessionState.remoteIdentityKey
                                         recipientId:self.recipientId
                                           direction:TSMessageDirectionIncoming
                                     protocolContext:protocolContext]) {
        DDLogWarn(
            @"%@ Previously known identity key for while decrypting from recipient: %@", self.tag, self.recipientId);
        @throw [NSException exceptionWithName:UntrustedIdentityKeyException
                                       reason:@"There is a previously known identity key."
                                     userInfo:@{}];
    }

    [self.identityKeyStore saveRemoteIdentity:sessionRecord.sessionState.remoteIdentityKey
                                  recipientId:self.recipientId
                              protocolContext:protocolContext];
    [self.sessionStore storeSession:self.recipientId
                           deviceId:self.deviceId
                            session:sessionRecord
                    protocolContext:protocolContext];

    return plaintext;
}

- (NSData *)throws_decryptWithSessionRecord:(SessionRecord *)sessionRecord
                             whisperMessage:(WhisperMessage *)whisperMessage
                            protocolContext:(nullable id)protocolContext
{
    OWSAssert(sessionRecord);
    OWSAssert(whisperMessage);

    SessionState   *sessionState   = [sessionRecord sessionState];
    NSMutableArray *exceptions     = [NSMutableArray array];

    @try {
        NSData *decryptedData = [self throws_decryptWithSessionState:sessionState
                                                      whisperMessage:whisperMessage
                                                     protocolContext:protocolContext];
        DDLogDebug(@"%@ successfully decrypted with current session state: %@", self.tag, sessionState);
        return decryptedData;
    }
    @catch (NSException *exception) {
        if ([exception.name isEqualToString:InvalidMessageException]) {
            [exceptions addObject:exception];
        } else {
            @throw exception;
        }
    }

    // If we can decrypt the message with an "old" session state, that means the sender is using an "old" session.
    // In which case, we promote that session to "active" so as to converge on a single session for sending/receiving.
    __block NSUInteger stateToPromoteIdx;
    __block NSData *decryptedData;
    [[sessionRecord previousSessionStates]
        enumerateObjectsUsingBlock:^(SessionState *_Nonnull previousState, NSUInteger idx, BOOL *_Nonnull stop) {
            @try {
                decryptedData = [self throws_decryptWithSessionState:previousState
                                                      whisperMessage:whisperMessage
                                                     protocolContext:protocolContext];
                DDLogInfo(@"%@ successfully decrypted with PREVIOUS session state: %@", self.tag, previousState);
                OWSAssert(decryptedData != nil);
                stateToPromoteIdx = idx;
                *stop = YES;
            } @catch (NSException *exception) {
                [exceptions addObject:exception];
            }
        }];

    if (decryptedData) {
        SessionState *sessionStateToPromote = [sessionRecord previousSessionStates][stateToPromoteIdx];
        OWSAssert(sessionStateToPromote != nil);
        DDLogInfo(@"%@ promoting session: %@", self.tag, sessionStateToPromote);
        [[sessionRecord previousSessionStates] removeObjectAtIndex:stateToPromoteIdx];
        [sessionRecord promoteState:sessionStateToPromote];

        return decryptedData;
    }

    BOOL containsActiveSession =
        [self.sessionStore containsSession:self.recipientId deviceId:self.deviceId protocolContext:protocolContext];
    DDLogError(@"%@ No valid session for recipient: %@ containsActiveSession: %@, previousStates: %lu",
        self.tag,
        self.recipientId,
        (containsActiveSession ? @"YES" : @"NO"),
        (unsigned long)sessionRecord.previousSessionStates.count);

    if (containsActiveSession) {
        @throw [NSException exceptionWithName:InvalidMessageException
                                       reason:@"No valid sessions"
                                     userInfo:@{
                                         @"Exceptions" : exceptions
                                     }];
    } else {
        @throw [NSException
            exceptionWithName:NoSessionException
                       reason:[NSString stringWithFormat:@"No session for: %@, %d", self.recipientId, self.deviceId]
                     userInfo:nil];
    }
}

- (NSData *)throws_decryptWithSessionState:(SessionState *)sessionState
                            whisperMessage:(WhisperMessage *)whisperMessage
                           protocolContext:(nullable id)protocolContext
{
    OWSAssert(sessionState);
    OWSAssert(whisperMessage);

    if (![sessionState hasSenderChain]) {
        @throw [NSException exceptionWithName:InvalidMessageException reason:@"Uninitialized session!" userInfo:nil];
    }

    if (whisperMessage.version != sessionState.version) {
        @throw [NSException exceptionWithName:InvalidMessageException
                                       reason:[NSString stringWithFormat:@"Got message version %d but was expecting %d",
                                                        whisperMessage.version,
                                                        sessionState.version]
                                     userInfo:nil];
    }

    int messageVersion = whisperMessage.version;
    NSData *theirEphemeral = whisperMessage.senderRatchetKey.throws_removeKeyType;
    int counter = whisperMessage.counter;
    ChainKey *chainKey = [self throws_getOrCreateChainKeys:sessionState theirEphemeral:theirEphemeral];
    OWSAssert(chainKey);
    MessageKeys *messageKeys = [self throws_getOrCreateMessageKeysForSession:sessionState
                                                              theirEphemeral:theirEphemeral
                                                                    chainKey:chainKey
                                                                     counter:counter];
    OWSAssert(messageKeys);

    [whisperMessage throws_verifyMacWithVersion:messageVersion
                              senderIdentityKey:sessionState.remoteIdentityKey
                            receiverIdentityKey:sessionState.localIdentityKey
                                         macKey:messageKeys.macKey];

    NSData *plaintext =
        [AES_CBC throws_decryptCBCMode:whisperMessage.cipherText withKey:messageKeys.cipherKey withIV:messageKeys.iv];

    [sessionState clearUnacknowledgedPreKeyMessage];

    return plaintext;
}

- (ChainKey *)throws_getOrCreateChainKeys:(SessionState *)sessionState theirEphemeral:(NSData *)theirEphemeral
{
    OWSAssert(sessionState);
    OWSGuardWithException(theirEphemeral, InvalidMessageException);
    OWSGuardWithException(theirEphemeral.length == 32, InvalidMessageException);

    @try {
        if ([sessionState hasReceiverChain:theirEphemeral]) {
            DDLogInfo(@"%@ %@.%d has existing receiver chain.", self.tag, self.recipientId, self.deviceId);
            return [sessionState receiverChainKey:theirEphemeral];
        } else{
            DDLogInfo(@"%@ %@.%d creating new chains.", self.tag, self.recipientId, self.deviceId);
            RootKey *rootKey = [sessionState rootKey];
            OWSAssert(rootKey.keyData.length == 32);

            ECKeyPair *ourEphemeral = [sessionState senderRatchetKeyPair];
            OWSAssert(ourEphemeral.publicKey.length == 32);

            RKCK *receiverChain =
                [rootKey throws_createChainWithTheirEphemeral:theirEphemeral ourEphemeral:ourEphemeral];

            ECKeyPair *ourNewEphemeral = [Curve25519 generateKeyPair];
            OWSAssert(ourNewEphemeral.publicKey.length == 32);

            RKCK *senderChain = [receiverChain.rootKey throws_createChainWithTheirEphemeral:theirEphemeral
                                                                               ourEphemeral:ourNewEphemeral];

            OWSAssert(senderChain.rootKey.keyData.length == 32);
            [sessionState setRootKey:senderChain.rootKey];

            OWSAssert(receiverChain.chainKey.key.length == 32);
            [sessionState addReceiverChain:theirEphemeral chainKey:receiverChain.chainKey];

            int previousCounter;
            ows_sub_overflow(sessionState.senderChainKey.index, 1, &previousCounter);
            [sessionState setPreviousCounter:MAX(previousCounter, 0)];
            [sessionState setSenderChain:ourNewEphemeral chainKey:senderChain.chainKey];

            return receiverChain.chainKey;
        }
    }
    @catch (NSException *exception) {
        @throw [NSException exceptionWithName:InvalidMessageException reason:@"Chainkeys couldn't be derived" userInfo:nil];
    }
}

- (MessageKeys *)throws_getOrCreateMessageKeysForSession:(SessionState *)sessionState
                                          theirEphemeral:(NSData *)theirEphemeral
                                                chainKey:(ChainKey *)chainKey
                                                 counter:(int)counter
{
    OWSAssert(sessionState);
    OWSGuardWithException(theirEphemeral, InvalidMessageException);
    OWSGuardWithException(theirEphemeral.length == 32, InvalidMessageException);
    OWSAssert(chainKey);

    if (chainKey.index > counter) {
        if ([sessionState hasMessageKeys:theirEphemeral counter:counter]) {
            return [sessionState removeMessageKeys:theirEphemeral counter:counter];
        } else {
            OWSLogInfo(
                @"%@ %@.%d Duplicate message for counter: %d", self.tag, self.recipientId, self.deviceId, counter);
            OWSLogFlush();
            @throw [NSException exceptionWithName:DuplicateMessageException reason:@"Received message with old counter!" userInfo:@{}];
        }
    }

    NSUInteger kCounterLimit = 2000;
    int counterOffset;
    if (__builtin_sub_overflow(counter, chainKey.index, &counterOffset)) {
        OWSFailDebug(@"Overflow while calculating counter offset");
        OWSRaiseException(InvalidMessageException, @"Overflow while calculating counter offset");
    }
    if (counterOffset > kCounterLimit) {
        OWSLogError(@"%@ %@.%d Exceeded future message limit: %lu, index: %d, counter: %d)",
            self.tag,
            self.recipientId,
            self.deviceId,
            (unsigned long)kCounterLimit,
            chainKey.index,
            counter);
        OWSLogFlush();
        @throw [NSException exceptionWithName:InvalidMessageException
                                       reason:@"Exceeded message keys chain length limit"
                                     userInfo:@{}];
    }

    while (chainKey.index < counter) {
        MessageKeys *messageKeys = [chainKey throws_messageKeys];
        [sessionState setMessageKeys:theirEphemeral messageKeys:messageKeys];
        chainKey = chainKey.nextChainKey;
    }

    [sessionState setReceiverChainKey:theirEphemeral chainKey:[chainKey nextChainKey]];
    return [chainKey throws_messageKeys];
}

/**
 *  The current version data. First 4 bits are the current version and the last 4 ones are the lowest version we support.
 *
 *  @return Current version data
 */

+ (NSData*)currentProtocolVersion{
    NSUInteger index = 0b00100010;
    NSData *versionByte = [NSData dataWithBytes:&index length:1];
    return versionByte;
}

- (int)throws_remoteRegistrationId:(nullable id)protocolContext
{
    SessionRecord *_Nullable record =
        [self.sessionStore loadSession:self.recipientId deviceId:_deviceId protocolContext:protocolContext];

    if (!record) {
        @throw [NSException exceptionWithName:NoSessionException reason:@"Trying to get registration Id of a non-existing session." userInfo:nil];
    }

    return record.sessionState.remoteRegistrationId;
}

- (int)throws_sessionVersion:(nullable id)protocolContext
{
    SessionRecord *_Nullable record =
        [self.sessionStore loadSession:self.recipientId deviceId:_deviceId protocolContext:protocolContext];

    if (!record) {
        @throw [NSException exceptionWithName:NoSessionException reason:@"Trying to get the version of a non-existing session." userInfo:nil];
    }

    return record.sessionState.version;
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
