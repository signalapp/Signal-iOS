//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#define LOCAL_NUMBER_KEY @"Number"
#define PASSWORD_COUNTER_KEY @"PasswordCounter"
#define SIGNALING_MAC_KEY @"Signaling Mac Key"
#define SIGNALING_CIPHER_KEY @"Signaling Cipher Key"
#define SIGNALING_EXTRA_KEY @"Signaling Extra Key"

// TODO:
@interface SignalKeyingStorage : NSObject

+ (void)generateSignaling;

#pragma mark Signaling Key

+ (int64_t)getAndIncrementOneTimeCounter;

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
