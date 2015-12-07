//
//  PreKeyBundle+jsonDict.m
//  Signal
//
//  Created by Frederic Jacobs on 26/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "NSData+Base64.h"
#import "PreKeyBundle+jsonDict.h"

@implementation PreKeyBundle (jsonDict)

+ (PreKeyBundle *)preKeyBundleFromDictionary:(NSDictionary *)dictionary forDeviceNumber:(NSNumber *)number {
    PreKeyBundle *bundle        = nil;
    NSString *identityKeyString = [dictionary objectForKey:@"identityKey"];
    NSArray *devicesArray       = [dictionary objectForKey:@"devices"];

    if (!(identityKeyString && [devicesArray isKindOfClass:[NSArray class]])) {
        DDLogError(@"Failed to get identity key or messages array from server request");
        return nil;
    }

    NSData *identityKey = [NSData dataFromBase64StringNoPadding:identityKeyString];

    for (NSDictionary *deviceDict in devicesArray) {
        NSNumber *registrationIdString = [deviceDict objectForKey:@"registrationId"];
        NSNumber *deviceIdString       = [deviceDict objectForKey:@"deviceId"];

        if (!(registrationIdString && deviceIdString)) {
            DDLogError(@"Failed to get the registration id and device id");
            return nil;
        }

        if (![deviceIdString isEqualToNumber:number]) {
            DDLogWarn(@"Got a keyid for another device");
            return nil;
        }

        int registrationId = [registrationIdString intValue];
        int deviceId       = [deviceIdString intValue];

        NSDictionary *preKey = [deviceDict objectForKey:@"preKey"];
        int prekeyId;
        NSData *preKeyPublic = nil;

        if (!preKey) {
            prekeyId = -1;
        } else {
            prekeyId                     = [[preKey objectForKey:@"keyId"] intValue];
            NSString *preKeyPublicString = [preKey objectForKey:@"publicKey"];
            preKeyPublic                 = [NSData dataFromBase64StringNoPadding:preKeyPublicString];
        }

        NSDictionary *signedPrekey = [deviceDict objectForKey:@"signedPreKey"];

        if (![signedPrekey isKindOfClass:[NSDictionary class]]) {
            DDLogError(@"Device doesn't have signed prekeys registered");
            return nil;
        }

        NSNumber *signedKeyIdNumber     = [signedPrekey objectForKey:@"keyId"];
        NSString *signedSignatureString = [signedPrekey objectForKey:@"signature"];
        NSString *signedPublicKeyString = [signedPrekey objectForKey:@"publicKey"];


        if (!(signedKeyIdNumber && signedPublicKeyString && signedSignatureString)) {
            DDLogError(@"Missing signed key material");
            return nil;
        }

        NSData *signedPrekeyPublic    = [NSData dataFromBase64StringNoPadding:signedPublicKeyString];
        NSData *signedPreKeySignature = [NSData dataFromBase64StringNoPadding:signedSignatureString];

        if (!(signedPrekeyPublic && signedPreKeySignature)) {
            DDLogError(@"Failed to parse signed keying material");
            return nil;
        }

        int signedPreKeyId = [signedKeyIdNumber intValue];

        bundle = [[self alloc] initWithRegistrationId:registrationId
                                             deviceId:deviceId
                                             preKeyId:prekeyId
                                         preKeyPublic:preKeyPublic
                                   signedPreKeyPublic:signedPrekeyPublic
                                       signedPreKeyId:signedPreKeyId
                                signedPreKeySignature:signedPreKeySignature
                                          identityKey:identityKey];
    }

    return bundle;
}

@end
