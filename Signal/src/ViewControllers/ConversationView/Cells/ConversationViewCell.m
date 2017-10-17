//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
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
}

- (void)loadForDisplay:(int)contentWidth
{
    OWSFail(@"%@ This method should be overridden.", self.logTag);
}

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth
{
    OWSFail(@"%@ This method should be overridden.", self.logTag);
    return CGSizeZero;
}

#pragma mark - Logging

+ (NSString *)logTag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)logTag
{
    return self.class.logTag;
}

@end

NS_ASSUME_NONNULL_END
