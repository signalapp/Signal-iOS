//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSData+OWS.h"
#import "PreKeyBundle+jsonDict.h"

NS_ASSUME_NONNULL_BEGIN

@implementation PreKeyBundle (jsonDict)

+ (nullable PreKeyBundle *)preKeyBundleFromDictionary:(NSDictionary *)dictionary forDeviceNumber:(NSNumber *)number
{
    PreKeyBundle *bundle        = nil;

    id identityKeyObject = [dictionary objectForKey:@"identityKey"];
    if (![identityKeyObject isKindOfClass:[NSString class]]) {
        OWSFail(@"Unexpected identityKeyObject: %@", [identityKeyObject class]);
        return nil;
    }
    NSString *identityKeyString = (NSString *)identityKeyObject;

    id devicesObject = [dictionary objectForKey:@"devices"];
    if (![devicesObject isKindOfClass:[NSArray class]]) {
        OWSFail(@"Unexpected devicesObject: %@", [devicesObject class]);
        return nil;
    }
    NSArray *devicesArray = (NSArray *)devicesObject;

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

        NSDictionary *_Nullable preKeyDict;
        id optionalPreKeyDict = [deviceDict objectForKey:@"preKey"];
        // JSON parsing might give us NSNull, so we can't simply check for non-nil.
        if ([optionalPreKeyDict isKindOfClass:[NSDictionary class]]) {
            preKeyDict = (NSDictionary *)optionalPreKeyDict;
        }

        int prekeyId;
        NSData *_Nullable preKeyPublic;

        if (!preKeyDict) {
            DDLogInfo(@"%@ No one-time prekey included in the bundle.", self.logTag);
            prekeyId = -1;
        } else {
            prekeyId = [[preKeyDict objectForKey:@"keyId"] intValue];
            NSString *preKeyPublicString = [preKeyDict objectForKey:@"publicKey"];
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

NS_ASSUME_NONNULL_END
