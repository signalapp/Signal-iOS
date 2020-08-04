//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ConversationScrollButton.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/Theme.h>

NS_ASSUME_NONNULL_BEGIN

@interface ConversationScrollButton ()

@property (nonatomic) NSString *iconName;
@property (nonatomic) UIImageView *iconView;
@property (nonatomic) UIView *circleView;

@property (nonatomic) UIView *unreadBadge;
@property (nonatomic) UILabel *unreadLabel;

@end

#pragma mark -

@implementation ConversationScrollButton

- (nullable instancetype)initWithIconName:(NSString *)iconName
{
    self = [super initWithFrame:CGRectZero];
    if (!self) {
        return self;
    }

    self.iconName = iconName;

    [self createContents];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(themeDidChange:)
                                               name:ThemeDidChangeNotification
                                             object:nil];

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

- (void)themeDidChange:(NSNotification *)notification
{
    [self updateColors];
}

- (void)createContents
{
    UIImageView *iconView = [UIImageView new];
    self.iconView = iconView;
    iconView.userInteractionEnabled = NO;

    const CGFloat circleSize = self.class.circleSize;
    UIView *circleView = [[OWSCircleView alloc] initWithDiameter:circleSize];
    self.circleView = circleView;
    circleView.userInteractionEnabled = NO;
    circleView.layer.shadowOffset = CGSizeMake(0, 4.f);
    circleView.layer.shadowRadius = 4.f;
    circleView.layer.shadowOpacity = 0.5f;

    UIView *unreadBadge = [UIView new];
    self.unreadBadge = unreadBadge;
    unreadBadge.userInteractionEnabled = NO;
    unreadBadge.layer.cornerRadius = 8;
    unreadBadge.clipsToBounds = YES;

    UILabel *unreadCountLabel = [UILabel new];
    self.unreadLabel = unreadCountLabel;
    unreadCountLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    unreadCountLabel.textColor = UIColor.ows_whiteColor;
    unreadCountLabel.textAlignment = NSTextAlignmentCenter;

    [unreadBadge addSubview:unreadCountLabel];
    [unreadCountLabel autoPinHeightToSuperview];
    [unreadCountLabel autoPinWidthToSuperviewWithMargin:3];

    [self addSubview:circleView];
    [circleView autoHCenterInSuperview];
    [circleView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    [circleView addSubview:iconView];
    [iconView autoCenterInSuperview];

    [self addSubview:unreadBadge];

    [unreadBadge autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:circleView withOffset:8];
    [unreadBadge autoHCenterInSuperview];
    [unreadBadge autoSetDimension:ALDimensionHeight toSize:16];
    [unreadBadge autoSetDimension:ALDimensionWidth toSize:16 relation:NSLayoutRelationGreaterThanOrEqual];
    [unreadBadge autoMatchDimension:ALDimensionWidth
                        toDimension:ALDimensionWidth
                             ofView:self
                         withOffset:0
                           relation:NSLayoutRelationLessThanOrEqual];
    [unreadBadge autoPinEdgeToSuperviewEdge:ALEdgeTop];

    [self updateColors];
}

- (void)setUnreadCount:(NSUInteger)unreadCount
{
    _unreadCount = unreadCount;

    self.unreadLabel.text = [NSString stringWithFormat:@"%lu", unreadCount];
    self.unreadBadge.hidden = unreadCount < 1;

    [self updateColors];
}

- (void)updateColors
{
    self.unreadBadge.backgroundColor = Theme.accentBlueColor;
    self.circleView.layer.shadowColor
        = (Theme.isDarkThemeEnabled ? Theme.darkThemeWashColor : Theme.primaryTextColor).CGColor;
    self.circleView.backgroundColor = Theme.backgroundColor;
    [self.iconView setTemplateImageName:self.iconName tintColor:Theme.accentBlueColor];
}

@end

NS_ASSUME_NONNULL_END
