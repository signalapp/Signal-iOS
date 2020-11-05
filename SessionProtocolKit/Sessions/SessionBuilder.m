//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SessionBuilder.h"
#import "AliceAxolotlParameters.h"
#import "AxolotlExceptions.h"
#import "AxolotlParameters.h"
#import "AxolotlStore.h"
#import "BobAxolotlParameters.h"
#import "NSData+keyVersionByte.h"
#import "PreKeyWhisperMessage.h"
#import "PrekeyBundle.h"
#import "RatchetingSession.h"
#import "SessionState.h"
#import <Curve25519Kit/Curve25519.h>
#import <Curve25519Kit/Ed25519.h>
#import <SessionProtocolKit/NSData+OWS.h>
#import <SessionProtocolKit/SCKExceptionWrapper.h>
#import <SessionProtocolKit/OWSAsserts.h>

NS_ASSUME_NONNULL_BEGIN

#define CURRENT_VERSION 3
#define MINUMUM_VERSION 3

const int kPreKeyOfLastResortId = 0xFFFFFF;

@interface SessionBuilder ()

@property (nonatomic, readonly)NSString* recipientId;
@property (nonatomic, readonly)int deviceId;

@property(nonatomic, readonly)id<SessionStore>      sessionStore;
@property(nonatomic, readonly)id<PreKeyStore>       prekeyStore ;
@property(nonatomic, readonly)id<SignedPreKeyStore> signedPreKeyStore;
@property(nonatomic, readonly)id<IdentityKeyStore>  identityStore;


@end

@implementation SessionBuilder

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

    if (self) {
        _sessionStore      = sessionStore;
        _prekeyStore       = preKeyStore;
        _signedPreKeyStore = signedPreKeyStore;
        _identityStore     = identityKeyStore;
        _recipientId       = recipientId;
        _deviceId          = deviceId;
    }

    return self;
}

- (BOOL)processPrekeyBundle:(PreKeyBundle *)preKeyBundle
            protocolContext:(nullable id)protocolContext
                      error:(NSError **)outError
{
    return [SCKExceptionWrapper
        tryBlock:^{
            [self throws_processPrekeyBundle:preKeyBundle protocolContext:protocolContext];
        }
           error:outError];
}

- (void)throws_processPrekeyBundle:(PreKeyBundle *)preKeyBundle protocolContext:(nullable id)protocolContext
{
    OWSAssert(preKeyBundle);

    NSData *theirIdentityKey = preKeyBundle.identityKey.throws_removeKeyType;
    NSData *theirSignedPreKey = preKeyBundle.signedPreKeyPublic.throws_removeKeyType;

    if (![self.identityStore isTrustedIdentityKey:theirIdentityKey
                                      recipientId:self.recipientId
                                        direction:TSMessageDirectionOutgoing
                                  protocolContext:protocolContext]) {
        @throw [NSException exceptionWithName:UntrustedIdentityKeyException reason:@"Identity key is not valid" userInfo:@{}];
    }

    // NOTE: we use preKeyBundle.signedPreKeyPublic which has the key type byte.
    if (![Ed25519 verifySignature:preKeyBundle.signedPreKeySignature
                        publicKey:theirIdentityKey
                             data:preKeyBundle.signedPreKeyPublic]) {
        @throw [NSException exceptionWithName:InvalidKeyException reason:@"KeyIsNotValidlySigned" userInfo:nil];
    }

    SessionRecord *sessionRecord =
        [self.sessionStore loadSession:self.recipientId deviceId:preKeyBundle.deviceId protocolContext:protocolContext];
    ECKeyPair     *ourBaseKey          = [Curve25519 generateKeyPair];
    NSData *theirOneTimePreKey = preKeyBundle.preKeyPublic.throws_removeKeyType;
    int           theirOneTimePreKeyId = preKeyBundle.preKeyId;
    int           theirSignedPreKeyId  = preKeyBundle.signedPreKeyId;


    AliceAxolotlParameters *params =
        [[AliceAxolotlParameters alloc] initWithIdentityKey:[self.identityStore identityKeyPair:protocolContext]
                                           theirIdentityKey:theirIdentityKey
                                                 ourBaseKey:ourBaseKey
                                          theirSignedPreKey:theirSignedPreKey
                                         theirOneTimePreKey:theirOneTimePreKey
                                            theirRatchetKey:theirSignedPreKey];

    if (!sessionRecord.isFresh) {
        [sessionRecord archiveCurrentState];
    }

    [RatchetingSession throws_initializeSession:[sessionRecord sessionState]
                                 sessionVersion:CURRENT_VERSION
                                AliceParameters:params];

    DDLogInfo(@"setUnacknowledgedPreKeyMessage for: %@ with preKeyId: %d", self.recipientId, theirOneTimePreKeyId);

    [sessionRecord.sessionState setUnacknowledgedPreKeyMessage:theirOneTimePreKeyId signedPreKey:theirSignedPreKeyId baseKey:ourBaseKey.publicKey];
    [sessionRecord.sessionState setLocalRegistrationId:[self.identityStore localRegistrationId:protocolContext]];
    [sessionRecord.sessionState setRemoteRegistrationId:preKeyBundle.registrationId];
    [sessionRecord.sessionState setAliceBaseKey:ourBaseKey.publicKey];

    // Saving invalidates any existing sessions, so be sure to save *before* storing the new session.
    BOOL previousIdentityExisted = [self.identityStore saveRemoteIdentity:theirIdentityKey
                                                              recipientId:self.recipientId
                                                          protocolContext:protocolContext];
    if (previousIdentityExisted) {
        DDLogInfo(@"%@ PKBundle removing previous session states for changed identity for recipient:%@",
            self.tag,
            self.recipientId);
        [sessionRecord removePreviousSessionStates];
    }

    [self.sessionStore storeSession:self.recipientId
                           deviceId:self.deviceId
                            session:sessionRecord
                    protocolContext:protocolContext];
}

- (int)throws_processPrekeyWhisperMessage:(PreKeyWhisperMessage *)message
                              withSession:(SessionRecord *)sessionRecord
                          protocolContext:(nullable id)protocolContext
{
    OWSAssert(message);
    OWSAssert(sessionRecord);

    int    messageVersion    = message.version;
    NSData *theirIdentityKey = message.identityKey.throws_removeKeyType;

    if (![self.identityStore isTrustedIdentityKey:theirIdentityKey
                                      recipientId:self.recipientId
                                        direction:TSMessageDirectionIncoming
                                  protocolContext:protocolContext]) {
        @throw [NSException exceptionWithName:UntrustedIdentityKeyException reason:@"There is a previously known identity key." userInfo:@{}];
    }

    int unSignedPrekeyId = -1;

    switch (messageVersion) {
        case 3:
            unSignedPrekeyId =
                [self throws_processPrekeyV3:message withSession:sessionRecord protocolContext:protocolContext];
            break;
        default:
            @throw [NSException exceptionWithName:InvalidVersionException reason:@"Trying to initialize with unknown version" userInfo:@{}];
            break;
    }

    [self.identityStore saveRemoteIdentity:theirIdentityKey
                               recipientId:self.recipientId
                           protocolContext:protocolContext];

    return unSignedPrekeyId;
}

- (int)throws_processPrekeyV3:(PreKeyWhisperMessage *)message
                  withSession:(SessionRecord *)sessionRecord
              protocolContext:(nullable id)protocolContext
{
    OWSAssert(message);
    OWSAssert(sessionRecord);

    NSData *baseKey = message.baseKey.throws_removeKeyType;

    if ([sessionRecord hasSessionState:message.version baseKey:baseKey]) {
        return -1;
    }

    ECKeyPair *ourSignedPrekey = [self.signedPreKeyStore throws_loadSignedPrekey:message.signedPrekeyId].keyPair;

    ECKeyPair *_Nullable ourOneTimePreKey;
    if (message.prekeyID >= 0) {
        ourOneTimePreKey = [self.prekeyStore throws_loadPreKey:message.prekeyID].keyPair;
    } else {
        DDLogWarn(@"%@ Processing PreKey message which had no one-time prekey.", self.tag);
    }

    BobAxolotlParameters *params =
        [[BobAxolotlParameters alloc] initWithMyIdentityKeyPair:[self.identityStore identityKeyPair:protocolContext]
                                               theirIdentityKey:message.identityKey.throws_removeKeyType
                                                ourSignedPrekey:ourSignedPrekey
                                                  ourRatchetKey:ourSignedPrekey
                                               ourOneTimePrekey:ourOneTimePreKey
                                                   theirBaseKey:baseKey];

    if (!sessionRecord.isFresh) {
        [sessionRecord archiveCurrentState];
    }

    [RatchetingSession throws_initializeSession:sessionRecord.sessionState
                                 sessionVersion:message.version
                                  BobParameters:params];

    [sessionRecord.sessionState setLocalRegistrationId:[self.identityStore localRegistrationId:protocolContext]];
    [sessionRecord.sessionState setRemoteRegistrationId:message.registrationId];
    [sessionRecord.sessionState setAliceBaseKey:baseKey];

    // If we used a prekey and it wasn't the prekey of last resort
    if (message.prekeyID >= 0 && message.prekeyID != kPreKeyOfLastResortId) {
        return message.prekeyID;
    } else {
        return -1;
    }
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
