//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ConversationHeaderView.h"
#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ConversationHeaderView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];

    if (self) {
        self.layoutMargins = UIEdgeInsetsZero;
    }

    return self;
}

- (void)setBounds:(CGRect)bounds
{
    [super setBounds:bounds];

    [self layoutSubviews];
}

- (void)setFrame:(CGRect)frame
{
    [super setFrame:frame];

    [self layoutSubviews];
}

- (void)setCenter:(CGPoint)center
{
    [super setCenter:center];

    [self layoutSubviews];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    // We need to manually resize and position the title views;
    // iOS AutoLayout doesn't work inside navigation bar items.
    const int kTitleVSpacing = 0.f;
    const int kTitleHMargin = 0.f;
    CGFloat titleHeight = ceil([self.titleLabel sizeThatFits:CGSizeZero].height);
    CGFloat subtitleHeight = ceil([self.subtitleLabel sizeThatFits:CGSizeZero].height);
    CGFloat contentHeight = titleHeight + kTitleVSpacing + subtitleHeight;
    CGFloat contentWidth = round(self.width - 2 * kTitleHMargin);

    CGFloat y = MAX(0, round((self.height - contentHeight) * 0.5f));
    self.titleLabel.frame = CGRectMake(kTitleHMargin, y, contentWidth, titleHeight);
    self.subtitleLabel.frame
        = CGRectMake(kTitleHMargin, ceil(y + titleHeight + kTitleVSpacing), contentWidth, subtitleHeight);
}

@end

NS_ASSUME_NONNULL_END
