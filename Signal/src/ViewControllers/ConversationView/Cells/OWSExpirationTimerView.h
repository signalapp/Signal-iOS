//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kExpirationTimerViewSize;

@interface OWSExpirationTimerView : UIView

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
- (instancetype)initWithExpiration:(uint64_t)expirationTimestamp
            initialDurationSeconds:(uint32_t)initialDurationSeconds NS_DESIGNATED_INITIALIZER;

- (void)ensureAnimations;

- (void)clearAnimations;

@end

NS_ASSUME_NONNULL_END
