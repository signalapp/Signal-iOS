//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ConversationScrollButton.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalUtilitiesKit/Theme.h>
#import "Session-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface ConversationScrollButton ()

@property (nonatomic) NSString *iconText;
@property (nonatomic) UILabel *iconLabel;
@property (nonatomic) UIView *circleView;

@end

#pragma mark -

@implementation ConversationScrollButton

- (nullable instancetype)initWithIconText:(NSString *)iconText
{
    self = [super initWithFrame:CGRectZero];
    if (!self) {
        return self;
    }

    self.iconText = iconText;

    [self createContents];

    return self;
}

+ (CGFloat)circleSize
{
    return ScaleFromIPhone5To7Plus(35.f, 40.f);
}

+ (CGFloat)buttonSize
{
    return self.circleSize + 2 * 15.f;
}

- (void)createContents
{
    UILabel *iconLabel = [UILabel new];
    self.iconLabel = iconLabel;
    iconLabel.userInteractionEnabled = NO;

    const CGFloat circleSize = self.class.circleSize;
    UIView *circleView = [UIView new];
    self.circleView = circleView;
    circleView.userInteractionEnabled = NO;
    circleView.layer.cornerRadius = circleSize * 0.5f;
    circleView.layer.borderColor = [LKColors.text colorWithAlphaComponent:LKValues.composeViewTextFieldBorderOpacity].CGColor;
    circleView.layer.borderWidth = LKValues.composeViewTextFieldBorderThickness;
    [circleView autoSetDimension:ALDimensionWidth toSize:circleSize];
    [circleView autoSetDimension:ALDimensionHeight toSize:circleSize];

    [self addSubview:circleView];
    [self addSubview:iconLabel];
    [circleView autoCenterInSuperview];
    [iconLabel autoCenterInSuperview];

    [self updateColors];
}

- (void)setHasUnreadMessages:(BOOL)hasUnreadMessages
{
    _hasUnreadMessages = hasUnreadMessages;

    [self updateColors];
}

- (void)updateColors
{
    UIColor *foregroundColor = LKColors.text;
    UIColor *backgroundColor = LKColors.composeViewBackground;

    const CGFloat circleSize = self.class.circleSize;
    self.circleView.backgroundColor = backgroundColor;
    self.iconLabel.attributedText =
        [[NSAttributedString alloc] initWithString:self.iconText
                                        attributes:@{
                                            NSFontAttributeName : [UIFont ows_fontAwesomeFont:circleSize * 0.75f],
                                            NSForegroundColorAttributeName : foregroundColor,
                                            NSBaselineOffsetAttributeName : @(-0.5f),
                                        }];
}

@end

NS_ASSUME_NONNULL_END
