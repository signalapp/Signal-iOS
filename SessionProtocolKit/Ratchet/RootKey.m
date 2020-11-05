//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "RootKey.h"
#import "ChainKey.h"
#import "RKCK.h"
#import "TSDerivedSecrets.h"
#import <Curve25519Kit/Curve25519.h>
#import <SessionProtocolKit/OWSAsserts.h>

static NSString* const kCoderData      = @"kCoderData";

@implementation RootKey

+(BOOL)supportsSecureCoding{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:_keyData forKey:kCoderData];
}

- (id)initWithCoder:(NSCoder *)aDecoder{
    self = [super init];

    if (self) {
        _keyData = [aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderData];
    }

    return self;
}

- (instancetype)initWithData:(NSData *)data{
    self = [super init];

    OWSAssert(data.length == 32);

    if (self) {
        _keyData = data;
    }

    return self;
}

- (RKCK *)throws_createChainWithTheirEphemeral:(NSData *)theirEphemeral ourEphemeral:(ECKeyPair *)ourEphemeral
{
    OWSAssert(theirEphemeral);
    OWSAssert(ourEphemeral);

    NSData *sharedSecret = [Curve25519 generateSharedSecretFromPublicKey:theirEphemeral andKeyPair:ourEphemeral];
    OWSAssert(sharedSecret.length == 32);

    TSDerivedSecrets *secrets =
        [TSDerivedSecrets throws_derivedRatchetedSecretsWithSharedSecret:sharedSecret rootKey:_keyData];
    OWSAssert(secrets);

    RKCK *newRKCK = [[RKCK alloc] initWithRK:[[RootKey alloc]  initWithData:secrets.cipherKey]
                                          CK:[[ChainKey alloc] initWithData:secrets.macKey index:0]];

    return newRKCK;
}

@end
