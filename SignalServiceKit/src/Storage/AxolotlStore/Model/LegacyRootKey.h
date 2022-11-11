//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

@interface LegacyRootKey : NSObject <NSSecureCoding>

- (instancetype)initWithData:(NSData *)data;

@property (nonatomic, readonly) NSData *keyData;

@end
