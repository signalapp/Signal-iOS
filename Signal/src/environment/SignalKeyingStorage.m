//
//  SignalKeyingStorage.m
//  Signal
//
//  Created by Frederic Jacobs on 09/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//
#import "CryptoTools.h"
#import "SignalKeyingStorage.h"
#import "Constraints.h"
#import "TSStorageManager.h"
#import "UICKeyChainStore.h"
#import "Util.h"


#define LOCAL_NUMBER_KEY @"Number"
#define PASSWORD_COUNTER_KEY @"PasswordCounter"
#define SAVED_PASSWORD_KEY @"Password"
#define SIGNALING_MAC_KEY @"Signaling Mac Key"
#define SIGNALING_CIPHER_KEY @"Signaling Cipher Key"
#define ZID_KEY @"ZID"
#define ZID_LENGTH 12
#define SIGNALING_EXTRA_KEY @"Signaling Extra Key"

#define SignalKeyingCollection @"SignalKeyingCollection"

#define SIGNALING_MAC_KEY_LENGTH    20
#define SIGNALING_CIPHER_KEY_LENGTH 16
#define SAVED_PASSWORD_LENGTH 18
#define SIGNALING_EXTRA_KEY_LENGTH 4

@implementation SignalKeyingStorage

+ (void)generateServerAuthPassword{
    [self storeString:[[CryptoTools generateSecureRandomData:SAVED_PASSWORD_LENGTH] encodedAsBase64] forKey:SAVED_PASSWORD_KEY];
}

+ (void)generateSignaling{
    [self storeData:[CryptoTools generateSecureRandomData:SIGNALING_MAC_KEY_LENGTH] forKey:SIGNALING_MAC_KEY];
    [self storeData:[CryptoTools generateSecureRandomData:SIGNALING_CIPHER_KEY_LENGTH] forKey:SIGNALING_CIPHER_KEY];
    [self storeData:[CryptoTools generateSecureRandomData:SIGNALING_EXTRA_KEY_LENGTH] forKey:SIGNALING_EXTRA_KEY];
    [self storeData:[CryptoTools generateSecureRandomData:ZID_LENGTH] forKey:ZID_KEY];
}

+(void)wipeKeychain{
    [TSStorageManager.sharedManager purgeCollection:SignalKeyingCollection];
}

+(int64_t) getAndIncrementOneTimeCounter {
    __block int64_t oldCounter;
    oldCounter = [[self stringForKey:PASSWORD_COUNTER_KEY] longLongValue];
    int64_t newCounter = (oldCounter == INT64_MAX)?INT64_MIN:(oldCounter + 1);
    [self storeString:[@(newCounter) stringValue] forKey:PASSWORD_COUNTER_KEY];
    return newCounter;
}

+ (void)setLocalNumberTo:(PhoneNumber *)localNumber{
    require(localNumber != nil);
    require(localNumber.toE164!= nil);
    
    NSString *e164 = localNumber.toE164;
    [self storeString:e164 forKey:LOCAL_NUMBER_KEY];
}

+ (PhoneNumber *)localNumber{
    NSString *lnString = [self stringForKey:LOCAL_NUMBER_KEY];
    checkOperation(lnString != nil );
    PhoneNumber *num = [PhoneNumber tryParsePhoneNumberFromE164:lnString];
    return lnString?num:nil;
}

+(Zid *)zid{
    NSData *data = [self dataForKey:ZID_KEY];
    if (data.length != ZID_LENGTH) {
        DDLogError(@"ZID length is incorrect. Is %lu, should be %d", (unsigned long)data.length, ZID_LENGTH);
    }
    Zid *zid = [Zid zidWithData:data];
    return zid;
}


+(NSData *)signalingCipherKey{
    return [self dataForKey:SIGNALING_CIPHER_KEY andVerifyLength:SIGNALING_CIPHER_KEY_LENGTH];
}

+(NSData *)signalingMacKey{
    return [self dataForKey:SIGNALING_MAC_KEY andVerifyLength:SIGNALING_MAC_KEY_LENGTH];
}

+ (NSData *)signalingExtraKey{
    return [self dataForKey:SIGNALING_EXTRA_KEY andVerifyLength:SIGNALING_EXTRA_KEY_LENGTH];
}

+(NSString *)serverAuthPassword{
    NSString *password = [self stringForKey:SAVED_PASSWORD_KEY];
    NSData *data = [password decodedAsBase64Data];
    if (data.length != SAVED_PASSWORD_LENGTH) {
        DDLogError(@"The server password has incorrect length. Is %lu but should be %d", (unsigned long)data.length, SAVED_PASSWORD_LENGTH);
    }
    return password;
}

#pragma mark Keychain wrapper methods

+(void)storeData:(NSData*)data forKey:(NSString*)key{
    [TSStorageManager.sharedManager setObject:data forKey:key inCollection:SignalKeyingCollection];
}

+(NSData*)dataForKey:(NSString*)key andVerifyLength:(uint)length{
    NSData *data = [self dataForKey:key];
    
    if (data.length != length) {
        DDLogError(@"Length of data not matching. Got %lu, expected %u", (unsigned long)data.length, length);
    }
    
    return data;
}

+(NSData*)dataForKey:(NSString*)key{
    return [TSStorageManager.sharedManager dataForKey:key inCollection:SignalKeyingCollection];
}

+(NSString*)stringForKey:(NSString*)key{
    return [TSStorageManager.sharedManager stringForKey:key inCollection:SignalKeyingCollection];
}

+(void)storeString:(NSString*)string forKey:(NSString*)key{
    [TSStorageManager.sharedManager setObject:string forKey:key inCollection:SignalKeyingCollection];
}


+ (void)migrateToVersion2Dot0{
    
    [self storeString:[UICKeyChainStore stringForKey:LOCAL_NUMBER_KEY] forKey:LOCAL_NUMBER_KEY];
    [self storeString:[UICKeyChainStore stringForKey:PASSWORD_COUNTER_KEY] forKey:PASSWORD_COUNTER_KEY];
    [self storeString:[UICKeyChainStore stringForKey:SAVED_PASSWORD_KEY] forKey:SAVED_PASSWORD_KEY];
    
    [self storeData:[UICKeyChainStore dataForKey:SIGNALING_MAC_KEY] forKey:SIGNALING_MAC_KEY];
    [self storeData:[UICKeyChainStore dataForKey:SIGNALING_CIPHER_KEY] forKey:SIGNALING_CIPHER_KEY];
    [self storeData:[UICKeyChainStore dataForKey:ZID_KEY] forKey:ZID_KEY];
    [self storeData:[UICKeyChainStore dataForKey:SIGNALING_EXTRA_KEY] forKey:SIGNALING_EXTRA_KEY];
}



@end
