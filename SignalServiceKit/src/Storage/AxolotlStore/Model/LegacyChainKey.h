//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SignalServiceKit/LegacyMessageKeys.h>

NS_ASSUME_NONNULL_BEGIN

@interface LegacyChainKey : NSObject <NSSecureCoding>

@property (nonatomic, readonly) int index;
@property (nonatomic, readonly) NSData *key;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithData:(NSData *)chainKey index:(int)index NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
