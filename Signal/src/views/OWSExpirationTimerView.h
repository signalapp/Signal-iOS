//  Created by Michael Kirk on 9/29/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSExpirationTimerView : UIView

- (void)startTimerWithExpiresAtSeconds:(uint64_t)expiresAtSeconds
                initialDurationSeconds:(uint32_t)initialDurationSeconds;

- (void)stopBlinking;

@end

NS_ASSUME_NONNULL_END
