//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ConversationScrollButton.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/Theme.h>

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
    circleView.layer.shadowColor = Theme.middleGrayColor.CGColor;
    circleView.layer.shadowOffset = CGSizeMake(+1.f, +2.f);
    circleView.layer.shadowRadius = 1.5f;
    circleView.layer.shadowOpacity = 0.35f;
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
    UIColor *foregroundColor;
    UIColor *backgroundColor;
    if (self.hasUnreadMessages) {
        foregroundColor = UIColor.whiteColor;
        backgroundColor = UIColor.ows_materialBlueColor;
    } else if (Theme.isDarkThemeEnabled) {
        foregroundColor = UIColor.ows_materialBlueColor;
        backgroundColor = [UIColor colorWithWhite:0.25f alpha:1.f];
    } else {
        foregroundColor = UIColor.ows_materialBlueColor;
        backgroundColor = [UIColor colorWithWhite:0.95f alpha:1.f];
    }

    const CGFloat circleSize = self.class.circleSize;
    self.circleView.backgroundColor = backgroundColor;
    self.iconLabel.attributedText =
        [[NSAttributedString alloc] initWithString:self.iconText
                                        attributes:@{
                                            NSFontAttributeName : [UIFont ows_fontAwesomeFont:circleSize * 0.8f],
                                            NSForegroundColorAttributeName : foregroundColor,
                                            NSBaselineOffsetAttributeName : @(-0.5f),
                                        }];
}

@end

NS_ASSUME_NONNULL_END
