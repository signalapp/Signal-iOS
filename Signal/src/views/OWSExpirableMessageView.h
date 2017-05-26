//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSExpirationTimerView;

static const CGFloat OWSExpirableMessageViewTimerWidth = 10.0f;

@protocol OWSExpirableMessageView

@property (strong, nonatomic, readonly) IBOutlet OWSExpirationTimerView *expirationTimerView;
@property (strong, nonatomic, readonly) IBOutlet NSLayoutConstraint *expirationTimerViewWidthConstraint;

- (void)startExpirationTimerWithExpiresAtSeconds:(double)expiresAtSeconds
                          initialDurationSeconds:(uint32_t)initialDurationSeconds;

- (void)stopExpirationTimer;

@end

NS_ASSUME_NONNULL_END
