//
//  TSRegisterPrekeys.h
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 10/17/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"
@class TSECKeyPair;
@class SignedPreKeyRecord;
@class PreKeyRecord;

@interface TSRegisterPrekeysRequest : TSRequest

- (id)initWithPrekeyArray:(NSArray *)prekeys
              identityKey:(NSData *)identityKeyPublic
       signedPreKeyRecord:(SignedPreKeyRecord *)signedRecord
         preKeyLastResort:(PreKeyRecord *)lastResort;

@end
