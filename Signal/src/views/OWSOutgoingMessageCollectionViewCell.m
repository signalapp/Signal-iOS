//  Created by Michael Kirk on 9/28/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSOutgoingMessageCollectionViewCell.h"
#import "OWSExpirationTimerView.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingMessageCollectionViewCell ()

@property (strong, nonatomic) IBOutlet OWSExpirationTimerView *expirationTimerView;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *expirationTimerViewWidthConstraint;

@end

@implementation OWSOutgoingMessageCollectionViewCell

- (void)awakeFromNib
{
    [super awakeFromNib];
    self.expirationTimerViewWidthConstraint.constant = 0.0;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.mediaView.alpha = 1.0;
    self.expirationTimerViewWidthConstraint.constant = 0.0f;
}

// pragma mark - OWSExpirableMessageView

- (void)startExpirationTimerWithExpiresAtSeconds:(uint64_t)expiresAtSeconds
                          initialDurationSeconds:(uint32_t)initialDurationSeconds
{
    self.expirationTimerViewWidthConstraint.constant = OWSExpirableMessageViewTimerWidth;
    [self.expirationTimerView startTimerWithExpiresAtSeconds:expiresAtSeconds
                                      initialDurationSeconds:initialDurationSeconds];
}

- (void)stopExpirationTimer
{
    [self.expirationTimerView stopTimer];
}

@end

NS_ASSUME_NONNULL_END
