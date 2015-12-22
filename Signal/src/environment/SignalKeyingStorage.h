//
//  SignalKeyingStorage.h
//  Signal
//
//  Created by Frederic Jacobs on 09/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PhoneNumber.h"
#import "Zid.h"

#define LOCAL_NUMBER_KEY @"Number"
#define PASSWORD_COUNTER_KEY @"PasswordCounter"
#define SAVED_PASSWORD_KEY @"Password"
#define SIGNALING_MAC_KEY @"Signaling Mac Key"
#define SIGNALING_CIPHER_KEY @"Signaling Cipher Key"
#define SIGNALING_EXTRA_KEY @"Signaling Extra Key"

@interface SignalKeyingStorage : NSObject

+ (void)generateSignaling;
+ (void)generateServerAuthPassword;

#pragma mark Signaling Key

+ (int64_t)getAndIncrementOneTimeCounter;

#pragma mark Server Auth

+ (NSString *)serverAuthPassword;

#pragma mark Signaling

+ (NSData *)signalingMacKey;
+ (NSData *)signalingCipherKey;

/**
 *  Returns the extra keying material generated at registration.
 ⚠️ Warning: Users of older versions of Signal (<= 2.1.1) might have the signaling cipher key as extra keing
 material.
 *
 *  @return Extra keying material from registration time
 */

+ (NSData *)signalingExtraKey;

@end
