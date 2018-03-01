//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSRegisterPrekeysRequest.h"
#import "TSConstants.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <AxolotlKit/PreKeyRecord.h>
#import <AxolotlKit/SignedPreKeyStore.h>
#import <Curve25519Kit/Curve25519.h>

@implementation TSRegisterPrekeysRequest

- (id)initWithPrekeyArray:(NSArray *)prekeys
              identityKey:(NSData *)identityKeyPublic
       signedPreKeyRecord:(SignedPreKeyRecord *)signedRecord
         preKeyLastResort:(PreKeyRecord *)lastResort {
    self            = [super initWithURL:[NSURL URLWithString:textSecureKeysAPI]];
    if (!self) {
        return nil;
    }

    self.HTTPMethod = @"PUT";

    NSString *publicIdentityKey          = [[identityKeyPublic prependKeyType] base64EncodedStringWithOptions:0];
    NSMutableArray *serializedPrekeyList = [NSMutableArray array];

    for (PreKeyRecord *preKey in prekeys) {
        [serializedPrekeyList addObject:[self dictionaryFromPreKey:preKey]];
    }

    NSDictionary *serializedKeyRegistrationParameters = @{
        @"preKeys" : serializedPrekeyList,
        @"lastResortKey" : [self dictionaryFromPreKey:lastResort],
        @"signedPreKey" : [self dictionaryFromSignedPreKey:signedRecord],
        @"identityKey" : publicIdentityKey
    };

    self.parameters = [serializedKeyRegistrationParameters mutableCopy];

    return self;
}


- (NSDictionary *)dictionaryFromPreKey:(PreKeyRecord *)preKey {
    return @{
        @"keyId" : [NSNumber numberWithInt:preKey.Id],
        @"publicKey" : [[preKey.keyPair.publicKey prependKeyType] base64EncodedStringWithOptions:0],
    };
}

- (NSDictionary *)dictionaryFromSignedPreKey:(SignedPreKeyRecord *)preKey {
    return @{
        @"keyId" : [NSNumber numberWithInt:preKey.Id],
        @"publicKey" : [[preKey.keyPair.publicKey prependKeyType] base64EncodedStringWithOptions:0],
        @"signature" : [preKey.signature base64EncodedStringWithOptions:0]
    };
}

@end
