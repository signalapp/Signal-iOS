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
@property (nonatomic) UIView *shadowView;

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

    UIView *shadowView = [[OWSCircleView alloc] initWithDiameter:circleSize];
    self.shadowView = shadowView;
    shadowView.userInteractionEnabled = NO;
    shadowView.layer.shadowOffset = CGSizeMake(0, 0);
    shadowView.layer.shadowRadius = 4;
    shadowView.layer.shadowOpacity = 0.05f;
    shadowView.layer.shadowColor = UIColor.blackColor.CGColor;

    UIView *circleView = [[OWSCircleView alloc] initWithDiameter:circleSize];
    self.circleView = circleView;
    circleView.userInteractionEnabled = NO;
    circleView.layer.shadowOffset = CGSizeMake(0, 4.f);
    circleView.layer.shadowRadius = 12.f;
    circleView.layer.shadowOpacity = 0.3f;
    circleView.layer.shadowColor = UIColor.blackColor.CGColor;

    UIView *unreadBadge = [UIView new];
    self.unreadBadge = unreadBadge;
    unreadBadge.userInteractionEnabled = NO;
    unreadBadge.layer.cornerRadius = 8;
    unreadBadge.clipsToBounds = YES;

    UILabel *unreadCountLabel = [UILabel new];
    self.unreadLabel = unreadCountLabel;
    unreadCountLabel.font = [UIFont systemFontOfSize:12];
    unreadCountLabel.textColor = UIColor.ows_whiteColor;
    unreadCountLabel.textAlignment = NSTextAlignmentCenter;

    [unreadBadge addSubview:unreadCountLabel];
    [unreadCountLabel autoPinHeightToSuperview];
    [unreadCountLabel autoPinWidthToSuperviewWithMargin:3];

    [self addSubview:shadowView];

    [self addSubview:circleView];
    [circleView autoHCenterInSuperview];
    [circleView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    [shadowView autoPinEdgesToEdgesOfView:circleView];

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
}

- (void)updateColors
{
    self.unreadBadge.backgroundColor = UIColor.ows_accentBlueColor;
    self.circleView.backgroundColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray65Color : UIColor.ows_gray02Color;
    [self.iconView setTemplateImageName:self.iconName
                              tintColor:Theme.isDarkThemeEnabled ? UIColor.ows_gray15Color : UIColor.ows_gray75Color];
}

@end

NS_ASSUME_NONNULL_END
