//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSRegisterSignedPrekeyRequest.h"
#import "TSConstants.h"

#import <Curve25519Kit/Curve25519.h>
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <AxolotlKit/PreKeyRecord.h>
#import <AxolotlKit/SignedPreKeyStore.h>

@implementation TSRegisterSignedPrekeyRequest

- (id)initWithSignedPreKeyRecord:(SignedPreKeyRecord *)signedRecord
{
    self = [super initWithURL:[NSURL URLWithString:textSecureSignedKeysAPI]];
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
