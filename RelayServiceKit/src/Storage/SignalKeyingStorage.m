//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalKeyingStorage.h"
#import <RelayServiceKit/OWSPrimaryStorage.h>
#import <RelayServiceKit/SecurityUtils.h>
#import <RelayServiceKit/YapDatabaseConnection+OWS.h>

#define SignalKeyingCollection @"SignalKeyingCollection"

#define SIGNALING_MAC_KEY_LENGTH 20
#define SIGNALING_CIPHER_KEY_LENGTH 16
#define SIGNALING_EXTRA_KEY_LENGTH 4
#define SAVED_PASSWORD_LENGTH 18

@implementation SignalKeyingStorage


+ (int64_t)getAndIncrementOneTimeCounter
{
    __block int64_t oldCounter;
    oldCounter = [[self stringForKey:PASSWORD_COUNTER_KEY] longLongValue];
    int64_t newCounter = (oldCounter == INT64_MAX) ? INT64_MIN : (oldCounter + 1);
    [self storeString:[@(newCounter) stringValue] forKey:PASSWORD_COUNTER_KEY];
    return newCounter;
}

+ (NSData *)signalingCipherKey
{
    return [self dataForKey:SIGNALING_CIPHER_KEY andVerifyLength:SIGNALING_CIPHER_KEY_LENGTH];
}

+ (NSData *)signalingMacKey
{
    return [self dataForKey:SIGNALING_MAC_KEY andVerifyLength:SIGNALING_MAC_KEY_LENGTH];
}

+ (NSData *)signalingExtraKey
{
    return [self dataForKey:SIGNALING_EXTRA_KEY andVerifyLength:SIGNALING_EXTRA_KEY_LENGTH];
}

+ (void)generateServerAuthPassword {
    [self storeString:[[SecurityUtils generateRandomBytes:SAVED_PASSWORD_LENGTH] base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength]
                forKey:SAVED_PASSWORD_KEY] ;
}

+ (NSString *)serverAuthPassword {
    return [self stringForKey:SAVED_PASSWORD_KEY];
}

+ (void)generateSignaling
{
    [self storeData:[SecurityUtils generateRandomBytes:SIGNALING_MAC_KEY_LENGTH] forKey:SIGNALING_MAC_KEY];
    [self storeData:[SecurityUtils generateRandomBytes:SIGNALING_CIPHER_KEY_LENGTH] forKey:SIGNALING_CIPHER_KEY];
    [self storeData:[SecurityUtils generateRandomBytes:SIGNALING_EXTRA_KEY_LENGTH] forKey:SIGNALING_EXTRA_KEY];
}


#pragma mark Keychain wrapper methods

+ (void)storeData:(NSData *)data forKey:(NSString *)key
{
    [OWSPrimaryStorage.dbReadWriteConnection setObject:data forKey:key inCollection:SignalKeyingCollection];
}

+ (NSData *)dataForKey:(NSString *)key andVerifyLength:(uint)length
{
    NSData *data = [self dataForKey:key];

    if (data.length != length) {
        DDLogError(@"Length of data not matching. Got %lu, expected %u", (unsigned long)data.length, length);
    }

    return data;
}

+ (NSData *)dataForKey:(NSString *)key
{
    return [OWSPrimaryStorage.dbReadConnection dataForKey:key inCollection:SignalKeyingCollection];
}

+ (NSString *)stringForKey:(NSString *)key
{
    return [OWSPrimaryStorage.dbReadConnection stringForKey:key inCollection:SignalKeyingCollection];
}

+ (void)storeString:(NSString *)string forKey:(NSString *)key
{
    [OWSPrimaryStorage.dbReadWriteConnection setObject:string forKey:key inCollection:SignalKeyingCollection];
}

@end
