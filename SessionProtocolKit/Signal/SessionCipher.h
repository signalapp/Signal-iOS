//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AxolotlStore.h"
#import "IdentityKeyStore.h"
#import "PreKeyStore.h"
#import "PreKeyWhisperMessage.h"
#import "SessionState.h"
#import "SessionStore.h"
#import "SignedPreKeyStore.h"
#import "WhisperMessage.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SessionCipher : NSObject

- (instancetype)initWithAxolotlStore:(id<AxolotlStore>)sessionStore recipientId:(NSString*)recipientId deviceId:(int)deviceId;

- (instancetype)initWithSessionStore:(id<SessionStore>)sessionStore preKeyStore:(id<PreKeyStore>)preKeyStore signedPreKeyStore:(id<SignedPreKeyStore>)signedPreKeyStore identityKeyStore:(id<IdentityKeyStore>)identityKeyStore recipientId:(NSString*)recipientId deviceId:(int)deviceId;

// protocolContext is an optional parameter that can be used to ensure that all
// identity and session store writes are coordinated and/or occur within a single
// transaction.
- (id<CipherMessage>)throws_encryptMessage:(NSData *)paddedMessage
                           protocolContext:(nullable id)protocolContext NS_SWIFT_UNAVAILABLE("throws objc exceptions");
- (nullable id<CipherMessage>)encryptMessage:(NSData *)paddedMessage
                             protocolContext:(nullable id)protocolContext
                                       error:(NSError **)outError;

- (NSData *)throws_decrypt:(id<CipherMessage>)whisperMessage
           protocolContext:(nullable id)protocolContext NS_SWIFT_UNAVAILABLE("throws objc exceptions");
- (nullable NSData *)decrypt:(id<CipherMessage>)whisperMessage
             protocolContext:(nullable id)protocolContext
                       error:(NSError **)outError;

- (int)throws_remoteRegistrationId:(nullable id)protocolContext NS_SWIFT_UNAVAILABLE("throws objc exceptions");

- (int)throws_sessionVersion:(nullable id)protocolContext NS_SWIFT_UNAVAILABLE("throws objc exceptions");

@end

NS_ASSUME_NONNULL_END
