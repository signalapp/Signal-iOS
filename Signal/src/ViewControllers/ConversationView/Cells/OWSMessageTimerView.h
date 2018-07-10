//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageTimerView : UIView

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;

- (instancetype)initWithExpiration:(uint64_t)expirationTimestamp
            initialDurationSeconds:(uint32_t)initialDurationSeconds NS_DESIGNATED_INITIALIZER;

+ (CGSize)measureSize;

@end

NS_ASSUME_NONNULL_END
