//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSData (keyVersionByte)

- (instancetype)prependKeyType;

- (instancetype)throws_removeKeyType NS_SWIFT_UNAVAILABLE("throws objc exceptions");
- (nullable instancetype)removeKeyTypeAndReturnError:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
