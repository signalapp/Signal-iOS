//
//  SignalKeyingStorage.m
//  Signal
//
//  Created by Frederic Jacobs on 09/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//
#import "Constraints.h"
#import "CryptoTools.h"
#import "SignalKeyingStorage.h"
#import "TSStorageManager.h"
#import "Util.h"

#define SignalKeyingCollection @"SignalKeyingCollection"

#define SIGNALING_MAC_KEY_LENGTH 20
#define SIGNALING_CIPHER_KEY_LENGTH 16
#define SAVED_PASSWORD_LENGTH 18
#define SIGNALING_EXTRA_KEY_LENGTH 4

@implementation SignalKeyingStorage

+ (void)generateServerAuthPassword {
    [self storeString:[[CryptoTools generateSecureRandomData:SAVED_PASSWORD_LENGTH] encodedAsBase64]
               forKey:SAVED_PASSWORD_KEY];
}

+ (void)generateSignaling {
    [self storeData:[CryptoTools generateSecureRandomData:SIGNALING_MAC_KEY_LENGTH] forKey:SIGNALING_MAC_KEY];
    [self storeData:[CryptoTools generateSecureRandomData:SIGNALING_CIPHER_KEY_LENGTH] forKey:SIGNALING_CIPHER_KEY];
    [self storeData:[CryptoTools generateSecureRandomData:SIGNALING_EXTRA_KEY_LENGTH] forKey:SIGNALING_EXTRA_KEY];
}

+ (int64_t)getAndIncrementOneTimeCounter {
    __block int64_t oldCounter;
    oldCounter         = [[self stringForKey:PASSWORD_COUNTER_KEY] longLongValue];
    int64_t newCounter = (oldCounter == INT64_MAX) ? INT64_MIN : (oldCounter + 1);
    [self storeString:[@(newCounter) stringValue] forKey:PASSWORD_COUNTER_KEY];
    return newCounter;
}

+ (NSData *)signalingCipherKey {
    return [self dataForKey:SIGNALING_CIPHER_KEY andVerifyLength:SIGNALING_CIPHER_KEY_LENGTH];
}

+ (NSData *)signalingMacKey {
    return [self dataForKey:SIGNALING_MAC_KEY andVerifyLength:SIGNALING_MAC_KEY_LENGTH];
}

+ (NSData *)signalingExtraKey {
    return [self dataForKey:SIGNALING_EXTRA_KEY andVerifyLength:SIGNALING_EXTRA_KEY_LENGTH];
}

+ (NSString *)serverAuthPassword {
    return [self stringForKey:SAVED_PASSWORD_KEY];
}

#pragma mark Keychain wrapper methods

+ (void)storeData:(NSData *)data forKey:(NSString *)key {
    [TSStorageManager.sharedManager setObject:data forKey:key inCollection:SignalKeyingCollection];
}

+ (NSData *)dataForKey:(NSString *)key andVerifyLength:(uint)length {
    NSData *data = [self dataForKey:key];

    if (data.length != length) {
        DDLogError(@"Length of data not matching. Got %lu, expected %u", (unsigned long)data.length, length);
    }

    return data;
}

+ (NSData *)dataForKey:(NSString *)key {
    return [TSStorageManager.sharedManager dataForKey:key inCollection:SignalKeyingCollection];
}

+ (NSString *)stringForKey:(NSString *)key {
    return [TSStorageManager.sharedManager stringForKey:key inCollection:SignalKeyingCollection];
}

+ (void)storeString:(NSString *)string forKey:(NSString *)key {
    [TSStorageManager.sharedManager setObject:string forKey:key inCollection:SignalKeyingCollection];
}

@end
