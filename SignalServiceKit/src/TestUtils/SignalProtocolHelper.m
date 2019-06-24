//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SignalProtocolHelper.h"
#import <AxolotlKit/AliceAxolotlParameters.h>
#import <AxolotlKit/BobAxolotlParameters.h>
#import <AxolotlKit/RatchetingSession.h>
#import <AxolotlKit/SessionCipher.h>
#import <SignalCoreKit/SCKExceptionWrapper.h>

NS_ASSUME_NONNULL_BEGIN

@implementation SignalProtocolHelper

+ (BOOL)sessionInitializationWithAliceSessionStore:(id<SessionStore>)aliceSessionStore
                             aliceIdentityKeyStore:(id<IdentityKeyStore>)aliceIdentityKeyStore
                                   aliceIdentifier:(NSString *)aliceIdentifier
                              aliceIdentityKeyPair:(ECKeyPair *)aliceIdentityKeyPair
                                   bobSessionStore:(id<SessionStore>)bobSessionStore
                               bobIdentityKeyStore:(id<IdentityKeyStore>)bobIdentityKeyStore
                                     bobIdentifier:(NSString *)bobIdentifier
                                bobIdentityKeyPair:(ECKeyPair *)bobIdentityKeyPair
                                   protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
                                             error:(NSError **)error
{
    return [SCKExceptionWrapper
        tryBlock:^{
            [self throws_sessionInitializationWithAliceSessionStore:aliceSessionStore
                                              aliceIdentityKeyStore:aliceIdentityKeyStore
                                                    aliceIdentifier:aliceIdentifier
                                               aliceIdentityKeyPair:aliceIdentityKeyPair
                                                    bobSessionStore:bobSessionStore
                                                bobIdentityKeyStore:bobIdentityKeyStore
                                                      bobIdentifier:bobIdentifier
                                                 bobIdentityKeyPair:bobIdentityKeyPair
                                                    protocolContext:protocolContext];
        }
           error:error];
}

+ (void)throws_sessionInitializationWithAliceSessionStore:(id<SessionStore>)aliceSessionStore
                                    aliceIdentityKeyStore:(id<IdentityKeyStore>)aliceIdentityKeyStore
                                          aliceIdentifier:(NSString *)aliceIdentifier
                                     aliceIdentityKeyPair:(ECKeyPair *)aliceIdentityKeyPair
                                          bobSessionStore:(id<SessionStore>)bobSessionStore
                                      bobIdentityKeyStore:(id<IdentityKeyStore>)bobIdentityKeyStore
                                            bobIdentifier:(NSString *)bobIdentifier
                                       bobIdentityKeyPair:(ECKeyPair *)bobIdentityKeyPair
                                          protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
{
    // Alice store's the shared session under Bob's identifier
    SessionRecord *aliceSessionRecord = [aliceSessionStore loadSession:bobIdentifier
                                                              deviceId:1
                                                       protocolContext:protocolContext];
    SessionState *aliceSessionState = aliceSessionRecord.sessionState;

    // Bob store's the shared session under Alice's identifier
    SessionRecord *bobSessionRecord = [bobSessionStore loadSession:aliceIdentifier
                                                          deviceId:1
                                                   protocolContext:protocolContext];
    SessionState *bobSessionState = bobSessionRecord.sessionState;

    ECKeyPair *aliceBaseKey = [Curve25519 generateKeyPair];

    ECKeyPair *bobBaseKey = [Curve25519 generateKeyPair];
    ECKeyPair *bobOneTimePK = [Curve25519 generateKeyPair];

    AliceAxolotlParameters *aliceParams = [[AliceAxolotlParameters alloc] initWithIdentityKey:aliceIdentityKeyPair theirIdentityKey:[bobIdentityKeyPair publicKey] ourBaseKey:aliceBaseKey theirSignedPreKey:[bobBaseKey publicKey] theirOneTimePreKey:[bobOneTimePK publicKey] theirRatchetKey:[bobBaseKey publicKey]];

    BobAxolotlParameters   *bobParams = [[BobAxolotlParameters alloc] initWithMyIdentityKeyPair:bobIdentityKeyPair theirIdentityKey:[aliceIdentityKeyPair publicKey] ourSignedPrekey:bobBaseKey ourRatchetKey:bobBaseKey ourOneTimePrekey:bobOneTimePK theirBaseKey:[aliceBaseKey publicKey]];

    [RatchetingSession throws_initializeSession:bobSessionState sessionVersion:3 BobParameters:bobParams];

    [RatchetingSession throws_initializeSession:aliceSessionState sessionVersion:3 AliceParameters:aliceParams];

    [aliceIdentityKeyStore saveRemoteIdentity:bobIdentityKeyPair.publicKey
                                  recipientId:bobIdentifier
                              protocolContext:nil];
    [aliceSessionStore storeSession:bobIdentifier
                           deviceId:1
                            session:aliceSessionRecord
                    protocolContext:protocolContext];

    [bobIdentityKeyStore saveRemoteIdentity:aliceIdentityKeyPair.publicKey
                                recipientId:aliceIdentifier
                            protocolContext:protocolContext];
    [bobSessionStore storeSession:aliceIdentifier deviceId:1 session:bobSessionRecord protocolContext:protocolContext];

    OWSAssertDebug([aliceSessionState.remoteIdentityKey isEqualToData:bobSessionState.localIdentityKey]);
}

@end

NS_ASSUME_NONNULL_END
