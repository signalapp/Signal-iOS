//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSIncomingMessageCollectionViewCell.h"
#import "FLAnimatedImageView.h"
#import "OWSExpirationTimerView.h"
#import "UIColor+OWS.h"
#import <JSQMessagesViewController/JSQMediaItem.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSIncomingMessageCollectionViewCell ()

@property (strong, nonatomic) IBOutlet OWSExpirationTimerView *expirationTimerView;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *expirationTimerViewWidthConstraint;

@end

@implementation OWSIncomingMessageCollectionViewCell

- (void)awakeFromNib
{
    [super awakeFromNib];
    self.expirationTimerViewWidthConstraint.constant = 0.0;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.expirationTimerViewWidthConstraint.constant = 0.0f;

    [self.mediaAdapter setCellVisible:NO];
    [self.mediaAdapter clearCachedMediaViews];
    self.mediaAdapter = nil;
}

// pragma mark - OWSMessageCollectionViewCell

- (void)setCellVisible:(BOOL)isVisible
{
    [self.mediaAdapter setCellVisible:isVisible];
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
