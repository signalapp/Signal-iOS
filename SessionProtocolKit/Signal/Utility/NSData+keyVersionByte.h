//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (keyVersionByte)

- (instancetype)prependKeyType;

- (instancetype)throws_removeKeyType NS_SWIFT_UNAVAILABLE("throws objc exceptions");
- (nullable instancetype)removeKeyTypeAndReturnError:(NSError **)outError;

@end
