//
//  SGNKeychainUtil.h
//  Signal
//
//  Created by Frederic Jacobs on 09/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PhoneNumber.h"
#import "Zid.h"

@interface SGNKeychainUtil : NSObject

+ (void)generateSignaling;
+ (void)generateServerAuthPassword;

+ (void)wipeKeychain;

#pragma mark Registered Phone Number

+ (PhoneNumber*)localNumber;
+ (void)setLocalNumberTo:(PhoneNumber*)localNumber;

#pragma mark Signaling Key

+ (int64_t)getAndIncrementOneTimeCounter;

#pragma mark Zid

+ (Zid*)zid;

#pragma mark Server Auth

+ (NSString*)serverAuthPassword;

#pragma mark Signaling

+ (NSData*)signalingMacKey;
+ (NSData*)signalingCipherKey;
+ (NSData*)signalingExtraKey;

@end
