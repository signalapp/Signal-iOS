//  Created by Michael Kirk on 9/29/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class OWSExpirationTimerView;

static const CGFloat OWSExpirableMessageViewTimerWidth = 10.0f;

@protocol OWSExpirableMessageView

@property (strong, nonatomic, readonly) IBOutlet OWSExpirationTimerView *expirationTimerView;
@property (strong, nonatomic, readonly) IBOutlet NSLayoutConstraint *expirationTimerViewWidthConstraint;

- (void)startExpirationTimerWithExpiresAtSeconds:(uint64_t)expiresAtSeconds
                          initialDurationSeconds:(uint32_t)initialDurationSeconds;

@end

NS_ASSUME_NONNULL_END
