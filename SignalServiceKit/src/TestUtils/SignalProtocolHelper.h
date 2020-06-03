//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ECKeyPair;
@class SessionRecord;

@protocol SessionStore;
@protocol IdentityKeyStore;
@protocol SPKProtocolWriteContext;

/// Sets up the state between two clients so that they can exchange messages.
/// Keep in mind that session setup is asymmetrical - Alice has to "send" first.
/// Bob must decrypt from Alice before he can encrypt to her.
@interface SignalProtocolHelper : NSObject

+ (BOOL)sessionInitializationWithAliceSessionStore:(id<SessionStore>)aliceSessionStore
                             aliceIdentityKeyStore:(id<IdentityKeyStore>)aliceIdentityKeyStore
                                   aliceIdentifier:(NSString *)aliceIdentifier
                              aliceIdentityKeyPair:(ECKeyPair *)aliceIdentityKeyPair
                                   bobSessionStore:(id<SessionStore>)bobSessionStore
                               bobIdentityKeyStore:(id<IdentityKeyStore>)bobIdentityKeyStore
                                     bobIdentifier:(NSString *)bobIdentifier
                                bobIdentityKeyPair:(ECKeyPair *)bobIdentityKeyPair
                                   protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
                                             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
