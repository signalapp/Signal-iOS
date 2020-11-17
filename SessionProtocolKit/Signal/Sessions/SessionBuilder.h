//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AxolotlStore.h"
#import "IdentityKeyStore.h"
#import "PreKeyBundle.h"
#import "PreKeyStore.h"
#import "SessionStore.h"
#import "SignedPreKeyStore.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PreKeyWhisperMessage;

extern const int kPreKeyOfLastResortId;

@interface SessionBuilder : NSObject

- (instancetype)initWithAxolotlStore:(id<AxolotlStore>)sessionStore
                         recipientId:(NSString *)recipientId
                            deviceId:(int)deviceId;

- (instancetype)initWithSessionStore:(id<SessionStore>)sessionStore
                         preKeyStore:(id<PreKeyStore>)preKeyStore
                   signedPreKeyStore:(id<SignedPreKeyStore>)signedPreKeyStore
                    identityKeyStore:(id<IdentityKeyStore>)identityKeyStore
                         recipientId:(NSString *)recipientId
                            deviceId:(int)deviceId;

- (void)throws_processPrekeyBundle:(PreKeyBundle *)preKeyBundle
                   protocolContext:(nullable id)protocolContext NS_SWIFT_UNAVAILABLE("throws objc exceptions");
- (BOOL)processPrekeyBundle:(PreKeyBundle *)preKeyBundle
            protocolContext:(nullable id)protocolContext
                      error:(NSError **)outError;

- (int)throws_processPrekeyWhisperMessage:(PreKeyWhisperMessage *)message
                              withSession:(SessionRecord *)sessionRecord
                          protocolContext:(nullable id)protocolContext NS_SWIFT_UNAVAILABLE("throws objc exceptions");

@end

NS_ASSUME_NONNULL_END
