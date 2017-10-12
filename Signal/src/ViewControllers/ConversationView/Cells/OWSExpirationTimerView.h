//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kExpirationTimerViewSize;

@interface OWSExpirationTimerView : UIView

- (void)startTimerWithExpiration:(uint64_t)expirationTimestamp initialDurationSeconds:(uint32_t)initialDurationSeconds;

- (void)stopTimer;

@end

NS_ASSUME_NONNULL_END
