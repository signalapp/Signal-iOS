//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewCell.h"
#import "ConversationViewItem.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ConversationViewCell

- (void)prepareForReuse
{
    [super prepareForReuse];

    self.viewItem = nil;
    self.delegate = nil;
    self.isCellVisible = NO;
    self.contentWidth = 0;
}

- (void)loadForDisplayWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSFail(@"%@ This method should be overridden.", self.logTag);
}

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth
{
    OWSFail(@"%@ This method should be overridden.", self.logTag);
    return CGSizeZero;
}

- (void)setIsCellVisible:(BOOL)isCellVisible
{
    _isCellVisible = isCellVisible;

    if (isCellVisible) {
        [self layoutIfNeeded];
    }
}

@end

NS_ASSUME_NONNULL_END
