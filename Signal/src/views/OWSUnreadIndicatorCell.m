//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSUnreadIndicatorCell.h"
#import "OWSBezierPathView.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import <JSQMessagesViewController/UIView+JSQMessages.h>

@interface OWSUnreadIndicatorCell ()

@property (nonatomic) UILabel *label;
@property (nonatomic) OWSBezierPathView *leftPathView;
@property (nonatomic) OWSBezierPathView *rightPathView;

@end

#pragma mark -

@implementation OWSUnreadIndicatorCell

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)configure
{
    self.backgroundColor = [UIColor whiteColor];

    if (!self.label) {
        self.label = [UILabel new];
        self.label.text = NSLocalizedString(
            @"MESSAGES_VIEW_UNREAD_INDICATOR", @"Indicator that separates read from unread messages.");
        self.label.textColor = [UIColor ows_infoMessageBorderColor];
        self.label.font = [UIFont ows_mediumFontWithSize:12.f];
        [self.contentView addSubview:self.label];

        CGFloat kLineThickness = 0.5f;
        CGFloat kLineMargin = 5.f;
        ConfigureShapeLayerBlock configureShapeLayerBlock = ^(CAShapeLayer *layer, CGRect bounds) {
            OWSCAssert(layer);

            CGRect pathBounds
                = CGRectMake(0, (bounds.size.height - kLineThickness) * 0.5f, bounds.size.width, kLineThickness);
            pathBounds = CGRectInset(pathBounds, kLineMargin, 0);
            UIBezierPath *path = [UIBezierPath bezierPathWithRect:pathBounds];
            layer.path = path.CGPath;
            layer.fillColor = [[UIColor ows_infoMessageBorderColor] colorWithAlphaComponent:0.5f].CGColor;
        };

        self.leftPathView = [OWSBezierPathView new];
        self.leftPathView.configureShapeLayerBlock = configureShapeLayerBlock;
        [self.contentView addSubview:self.leftPathView];

        self.rightPathView = [OWSBezierPathView new];
        self.rightPathView.configureShapeLayerBlock = configureShapeLayerBlock;
        [self.contentView addSubview:self.rightPathView];
    }
}

- (void)layoutSubviews
{
    CGSize labelSize = [self.label sizeThatFits:CGSizeZero];
    self.label.frame = CGRectMake(round(self.bounds.origin.x + (self.bounds.size.width - labelSize.width) * 0.5f),
        round(self.bounds.origin.y + (self.bounds.size.height - labelSize.height) * 0.5f),
        labelSize.width,
        labelSize.height);
    self.leftPathView.frame = CGRectMake(0, 0, self.label.frame.origin.x, self.bounds.size.height);
    self.rightPathView.frame = CGRectMake(self.label.frame.origin.x + self.label.frame.size.width,
        0,
        self.bounds.size.width - (self.label.frame.origin.x + self.label.frame.size.width),
        self.bounds.size.height);
}

@end
