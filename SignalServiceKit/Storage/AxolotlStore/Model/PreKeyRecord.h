//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ECKeyPair;

@interface PreKeyRecord : NSObject <NSSecureCoding>

@property (nonatomic, readonly) int       Id;
@property (nonatomic, readonly) ECKeyPair *keyPair;
@property (nonatomic, readonly, nullable) NSDate *createdAt;

- (instancetype)initWithId:(int)identifier
                   keyPair:(ECKeyPair *)keyPair
                 createdAt:(NSDate *)createdAt;

- (void)setCreatedAtToNow;

@end

NS_ASSUME_NONNULL_END
