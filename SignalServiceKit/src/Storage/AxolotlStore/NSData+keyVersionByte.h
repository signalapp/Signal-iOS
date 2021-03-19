//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSData (keyVersionByte)

- (instancetype)prependKeyType;

- (instancetype)throws_removeKeyType NS_SWIFT_UNAVAILABLE("throws objc exceptions");
- (nullable instancetype)removeKeyTypeAndReturnError:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
