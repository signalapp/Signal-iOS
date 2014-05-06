//
//  KeyChainStorage.m
//  Signal
//
//  Created by Frederic Jacobs on 06/05/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//
#import "Constraints.h"
#import "CryptoTools.h"
#import "DataUtil.h"
#import "KeyChainStorage.h"
#import "KeychainWrapper.h"
#import "StringUtil.h"
#import "PhoneNumber.h"
#import "Zid.h"


#define LOCAL_NUMBER_KEY @"Number"
#define SAVED_PASSWORD_KEY @"Password"
#define SIGNALING_MAC_KEY @"Signaling Mac Key"
#define SIGNALING_CIPHER_KEY @"Signaling Cipher Key"
#define ZID_KEY @"ZID"
#define SIGNALING_EXTRA_KEY @"Signaling Extra Key"

#define SIGNALING_MAC_KEY_LENGTH    20
#define SIGNALING_CIPHER_KEY_LENGTH 16
#define SAVED_PASSWORD_LENGTH 18
#define SIGNALING_EXTRA_KEY_LENGTH 4

@implementation KeyChainStorage

+(PhoneNumber*) forceGetLocalNumber {
    NSString* localNumber = [self tryGetValueForKey:LOCAL_NUMBER_KEY];
    checkOperation(localNumber != nil);
    return [PhoneNumber tryParsePhoneNumberFromE164:localNumber];
}

+(void) setLocalNumberTo:(PhoneNumber*)localNumber {
    require(localNumber != nil);
    [self setValueForKey:LOCAL_NUMBER_KEY toValue:[localNumber toE164]];
}

+(PhoneNumber*)tryGetLocalNumber {
    NSString* localNumber = [self tryGetValueForKey:LOCAL_NUMBER_KEY];
	return (localNumber != nil ? [PhoneNumber tryParsePhoneNumberFromE164:localNumber] : nil);
}

+(Zid*) getOrGenerateZid {
    return [Zid zidWithData:[self getOrGenerateRandomDataWithKey:ZID_KEY andLength:12]];
}

+(NSString*) getOrGenerateSavedPassword {
    NSString *password = [KeychainWrapper keychainStringFromMatchingIdentifier:SAVED_PASSWORD_KEY];
    
    if (!password) {
        password = [[CryptoTools generateSecureRandomData:SAVED_PASSWORD_LENGTH] encodedAsBase64];
        [KeychainWrapper createKeychainValue:password forIdentifier:SAVED_PASSWORD_KEY];
    }
    
    return password;
}

+(NSData*) getOrGenerateSignalingMacKey {
    return [self getOrGenerateRandomDataWithKey:SIGNALING_MAC_KEY andLength:SIGNALING_MAC_KEY_LENGTH];
}

+(NSData*) getOrGenerateSignalingCipherKey {
    return [self getOrGenerateRandomDataWithKey:SIGNALING_CIPHER_KEY andLength:SIGNALING_CIPHER_KEY_LENGTH];
}

+(NSData*) getOrGenerateSignalingExtraKey {
    return [self getOrGenerateRandomDataWithKey:SIGNALING_EXTRA_KEY andLength:SIGNALING_EXTRA_KEY_LENGTH];
}

+(NSData*) getOrGenerateRandomDataWithKey:(NSString*)key andLength:(NSUInteger)length {
    require(key != nil);
    
    NSData *password = [[KeychainWrapper keychainStringFromMatchingIdentifier:key] decodedAsBase64Data];
    
    if (!password) {
        password = [CryptoTools generateSecureRandomData:length];
        [KeychainWrapper createKeychainValue:[password encodedAsBase64] forIdentifier:key];
    }
    
    return password;
}

+ (NSString*)tryGetValueForKey:(NSString*)key{
    return [KeychainWrapper keychainStringFromMatchingIdentifier:key];
}

+ (void)setValueForKey:(NSString*)key toValue:(NSString*)string{
    [KeychainWrapper createKeychainValue:string forIdentifier:key];
}

+ (void)clear{
    [KeychainWrapper deleteItemFromKeychainWithIdentifier:SIGNALING_MAC_KEY];
    [KeychainWrapper deleteItemFromKeychainWithIdentifier:SIGNALING_EXTRA_KEY];
    [KeychainWrapper deleteItemFromKeychainWithIdentifier:SIGNALING_CIPHER_KEY];
    [KeychainWrapper deleteItemFromKeychainWithIdentifier:SAVED_PASSWORD_KEY];
    [KeychainWrapper deleteItemFromKeychainWithIdentifier:ZID_KEY];
    [KeychainWrapper deleteItemFromKeychainWithIdentifier:LOCAL_NUMBER_KEY];
}

@end
