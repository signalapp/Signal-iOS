//
//  TSRegisterPrekeys.m
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 10/17/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import "TSRegisterPrekeysRequest.h"

#import <25519/Curve25519.h>
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <AxolotlKit/PreKeyRecord.h>
#import <AxolotlKit/SignedPreKeyStore.h>

@implementation TSRegisterPrekeysRequest

- (id)initWithPrekeyArray:(NSArray *)prekeys
              identityKey:(NSData *)identityKeyPublic
       signedPreKeyRecord:(SignedPreKeyRecord *)signedRecord
         preKeyLastResort:(PreKeyRecord *)lastResort {
    self            = [super initWithURL:[NSURL URLWithString:textSecureKeysAPI]];
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
