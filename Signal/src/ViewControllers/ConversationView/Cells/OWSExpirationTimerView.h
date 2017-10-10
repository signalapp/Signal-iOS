//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSExpirationTimerView : UIView

- (void)startTimerWithExpiresAtSeconds:(double)expiresAtSeconds initialDurationSeconds:(uint32_t)initialDurationSeconds;

- (void)stopTimer;

@end

NS_ASSUME_NONNULL_END
