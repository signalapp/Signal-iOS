//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PreKeyRecord.h"
#import <Curve25519Kit/Curve25519.h>

@interface SignedPreKeyRecord : PreKeyRecord <NSSecureCoding>

@property (nonatomic, readonly) NSData *signature;
@property (nonatomic, readonly) NSDate *generatedAt;
// Defaults to NO.  Should only be set after the service accepts this record.
@property (nonatomic, readonly) BOOL wasAcceptedByService;

- (instancetype)initWithId:(int)identifier keyPair:(ECKeyPair *)keyPair signature:(NSData*)signature generatedAt:(NSDate*)generatedAt;
- (instancetype)initWithId:(int)identifier keyPair:(ECKeyPair *)keyPair NS_UNAVAILABLE;

- (void)markAsAcceptedByService;

@end
