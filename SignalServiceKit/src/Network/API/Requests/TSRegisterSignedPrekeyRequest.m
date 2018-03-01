//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSRegisterSignedPrekeyRequest.h"
#import "TSConstants.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <AxolotlKit/PreKeyRecord.h>
#import <AxolotlKit/SignedPreKeyStore.h>
#import <Curve25519Kit/Curve25519.h>

@implementation TSRegisterSignedPrekeyRequest

- (id)initWithSignedPreKeyRecord:(SignedPreKeyRecord *)signedRecord
{
    self = [super initWithURL:[NSURL URLWithString:textSecureSignedKeysAPI]];
    if (!self) {
        return nil;
    }

    self.HTTPMethod = @"PUT";

    NSDictionary *serializedKeyRegistrationParameters = [self dictionaryFromSignedPreKey:signedRecord];

    self.parameters = [serializedKeyRegistrationParameters mutableCopy];

    return self;
}

- (NSDictionary *)dictionaryFromSignedPreKey:(SignedPreKeyRecord *)preKey
{
    return @{
        @"keyId" : [NSNumber numberWithInt:preKey.Id],
        @"publicKey" : [[preKey.keyPair.publicKey prependKeyType] base64EncodedStringWithOptions:0],
        @"signature" : [preKey.signature base64EncodedStringWithOptions:0]
    };
}

@end
