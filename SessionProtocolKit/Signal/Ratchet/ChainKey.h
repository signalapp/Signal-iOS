//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Chain.h"
#import "MessageKeys.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ChainKey : NSObject <NSSecureCoding>

@property (nonatomic, readonly) int index;
@property (nonatomic, readonly) NSData *key;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithData:(NSData *)chainKey index:(int)index NS_DESIGNATED_INITIALIZER;

- (instancetype)nextChainKey;

- (MessageKeys *)throws_messageKeys NS_SWIFT_UNAVAILABLE("throws objc exceptions");

@end

NS_ASSUME_NONNULL_END
