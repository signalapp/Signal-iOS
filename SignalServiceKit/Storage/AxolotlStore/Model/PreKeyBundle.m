//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "PreKeyBundle.h"

NS_ASSUME_NONNULL_BEGIN

static NSString* const kCoderPKBIdentityKey           = @"kCoderPKBIdentityKey";
static NSString* const kCoderPKBregistrationId        = @"kCoderPKBregistrationId";
static NSString* const kCoderPKBdeviceId              = @"kCoderPKBdeviceId";
static NSString* const kCoderPKBsignedPreKeyPublic    = @"kCoderPKBsignedPreKeyPublic";
static NSString* const kCoderPKBpreKeyPublic          = @"kCoderPKBpreKeyPublic";
static NSString* const kCoderPKBpreKeyId              = @"kCoderPKBpreKeyId";
static NSString* const kCoderPKBsignedPreKeyId        = @"kCoderPKBsignedPreKeyId";
static NSString* const kCoderPKBsignedPreKeySignature = @"kCoderPKBsignedPreKeySignature";
static NSString *const kCoderPKBpqPreKeyId = @"kCoderPKBpqPreKeyId";
static NSString *const kCoderPKBpqPreKeyPublic = @"kCoderPKBpqPreKeyPublic";
static NSString *const kCoderPKBpqPreKeySignature = @"kCoderPKBpqPreKeySignature";

@implementation PreKeyBundle

- (nullable instancetype)initWithRegistrationId:(int)registrationId
                                       deviceId:(int)deviceId
                                       preKeyId:(int)preKeyId
                                   preKeyPublic:(NSData *)preKeyPublic
                             signedPreKeyPublic:(NSData *)signedPreKeyPublic
                                 signedPreKeyId:(int)signedPreKeyId
                          signedPreKeySignature:(NSData *)signedPreKeySignature
                                     pqPreKeyId:(int)pqPreKeyId
                                 pqPreKeyPublic:(NSData *)pqPreKeyPublic
                              pqPreKeySignature:(NSData *)pqPreKeySignature
                                    identityKey:(NSData *)identityKey
{
    if (preKeyPublic && preKeyPublic.length != 33) {
        OWSFailDebug(@"preKeyPublic && preKeyPublic.length != 33");
        return nil;
    }
    if (signedPreKeyPublic.length != 33) {
        OWSFailDebug(@"signedPreKeyPublic.length != 33");
        return nil;
    }
    if (!signedPreKeySignature) {
        OWSFailDebug(@"!signedPreKeySignature");
        return nil;
    }
    if (identityKey.length != 33) {
        OWSFailDebug(@"identityKey.length != 33");
        return nil;
    }

    self = [super init];

    if (self) {
        _identityKey           = identityKey;
        _registrationId        = registrationId;
        _deviceId              = deviceId;
        _preKeyPublic          = preKeyPublic;
        _preKeyId              = preKeyId;
        _signedPreKeyPublic    = signedPreKeyPublic;
        _signedPreKeyId        = signedPreKeyId;
        _signedPreKeySignature = signedPreKeySignature;
        _pqPreKeyId = pqPreKeyId;
        _pqPreKeyPublic = pqPreKeyPublic;
        _pqPreKeySignature = pqPreKeySignature;
    }
    
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    int registrationId            = [aDecoder decodeIntForKey:kCoderPKBregistrationId];
    int deviceId                  = [aDecoder decodeIntForKey:kCoderPKBdeviceId];
    int preKeyId                  = [aDecoder decodeIntForKey:kCoderPKBpreKeyId];
    int pqPreKeyId = [aDecoder decodeIntForKey:kCoderPKBpqPreKeyId];
    int signedPreKeyId            = [aDecoder decodeIntForKey:kCoderPKBsignedPreKeyId];
    
    NSData *preKeyPublic          = [aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderPKBpreKeyPublic];
    NSData *signedPreKeyPublic    = [aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderPKBsignedPreKeyPublic];
    NSData *signedPreKeySignature = [aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderPKBsignedPreKeySignature];
    NSData *pqPreKeyPublic = [aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderPKBpqPreKeyPublic];
    NSData *pqPreKeySignature = [aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderPKBpqPreKeySignature];
    NSData *identityKey           = [aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderPKBIdentityKey];


    self = [self initWithRegistrationId:registrationId
                               deviceId:deviceId
                               preKeyId:preKeyId
                           preKeyPublic:preKeyPublic
                     signedPreKeyPublic:signedPreKeyPublic
                         signedPreKeyId:signedPreKeyId
                  signedPreKeySignature:signedPreKeySignature
                             pqPreKeyId:pqPreKeyId
                         pqPreKeyPublic:pqPreKeyPublic
                      pqPreKeySignature:pqPreKeySignature
                            identityKey:identityKey];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeInt:_registrationId forKey:kCoderPKBregistrationId];
    [aCoder encodeInt:_deviceId forKey:kCoderPKBdeviceId];
    [aCoder encodeInt:_preKeyId forKey:kCoderPKBpreKeyId];
    [aCoder encodeInt:_pqPreKeyId forKey:kCoderPKBpqPreKeyId];
    [aCoder encodeInt:_signedPreKeyId forKey:kCoderPKBsignedPreKeyId];
    
    [aCoder encodeObject:_preKeyPublic forKey:kCoderPKBpreKeyPublic];
    [aCoder encodeObject:_signedPreKeyPublic forKey:kCoderPKBsignedPreKeyPublic];
    [aCoder encodeObject:_signedPreKeySignature forKey:kCoderPKBsignedPreKeySignature];
    [aCoder encodeObject:_pqPreKeyPublic forKey:kCoderPKBpqPreKeyPublic];
    [aCoder encodeObject:_pqPreKeySignature forKey:kCoderPKBpqPreKeySignature];
    [aCoder encodeObject:_identityKey forKey:kCoderPKBIdentityKey];
}

+(BOOL)supportsSecureCoding{
    return YES;
}

@end

NS_ASSUME_NONNULL_END
