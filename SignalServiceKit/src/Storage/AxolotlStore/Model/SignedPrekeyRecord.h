//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>
#import <SignalServiceKit/PreKeyRecord.h>

NS_ASSUME_NONNULL_BEGIN

@class ECKeyPair;

@interface SignedPreKeyRecord : PreKeyRecord <NSSecureCoding>

@property (nonatomic, readonly) NSData *signature;
@property (nonatomic, readonly) NSDate *generatedAt;

- (instancetype)initWithId:(int)identifier keyPair:(ECKeyPair *)keyPair signature:(NSData*)signature generatedAt:(NSDate*)generatedAt;
- (instancetype)initWithId:(int)identifier keyPair:(ECKeyPair *)keyPair NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
