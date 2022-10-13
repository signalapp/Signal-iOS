//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Curve25519Kit/Curve25519.h>
#import <Foundation/Foundation.h>
#import <SignalServiceKit/PreKeyRecord.h>

NS_ASSUME_NONNULL_BEGIN

@interface SignedPreKeyRecord : PreKeyRecord <NSSecureCoding>

@property (nonatomic, readonly) NSData *signature;
@property (nonatomic, readonly) NSDate *generatedAt;
// Defaults to NO.  Should only be set after the service accepts this record.
@property (nonatomic, readonly) BOOL wasAcceptedByService;

- (instancetype)initWithId:(int)identifier keyPair:(ECKeyPair *)keyPair signature:(NSData*)signature generatedAt:(NSDate*)generatedAt;
- (instancetype)initWithId:(int)identifier keyPair:(ECKeyPair *)keyPair NS_UNAVAILABLE;

- (void)markAsAcceptedByService;

@end

NS_ASSUME_NONNULL_END
