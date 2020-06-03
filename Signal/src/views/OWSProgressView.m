//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSProgressView.h"
#import <SignalMessaging/UIView+OWS.h>
#import <SignalServiceKit/OWSMath.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSProgressView ()

@property (nonatomic) CAShapeLayer *borderLayer;
@property (nonatomic) CAShapeLayer *progressLayer;

@end

#pragma mark -

@implementation OWSProgressView

- (id)init
{
    self = [super init];
    if (self) {
        [self initCommon];
    }

    return self;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self initCommon];
    }
    return self;
}

- (void)initCommon
{
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    self.color = [UIColor whiteColor];

    // Prevent the shape layer from animating changes.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    self.borderLayer = [CAShapeLayer new];
    [self.layer addSublayer:self.borderLayer];

    self.progressLayer = [CAShapeLayer new];
    [self.layer addSublayer:self.progressLayer];

    [CATransaction commit];

    [self setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisVertical];
    [self setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisVertical];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self update];
}

- (void)setProgress:(CGFloat)progress
{
    if (_progress != progress) {
        _progress = progress;
        [self update];
    }
}

- (void)setColor:(UIColor *)color
{
    if (![_color isEqual:color]) {
        _color = color;
        [self update];
    }
}

- (void)update
{
    // Prevent the shape layer from animating changes.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    CGFloat borderThickness = MAX(CGHairlineWidth(), self.bounds.size.height * 0.1f);
    CGFloat cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5f;

    // Add the outer border.
    UIBezierPath *borderPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:cornerRadius];
    self.borderLayer.path = borderPath.CGPath;
    self.borderLayer.strokeColor = self.color.CGColor;
    self.borderLayer.lineWidth = borderThickness;
    self.borderLayer.fillColor = [UIColor clearColor].CGColor;

    // Add the inner progress.
    CGRect progressRect = self.bounds;
    progressRect.size.width = cornerRadius * 2;
    CGFloat baseProgress = borderThickness * 2;
    CGFloat minProgress = baseProgress;
    CGFloat maxProgress = MAX(0, self.bounds.size.width - baseProgress);
    progressRect.size.width = CGFloatLerp(minProgress, maxProgress, CGFloatClamp01(self.progress));
    UIBezierPath *progressPath = [UIBezierPath bezierPathWithRoundedRect:progressRect cornerRadius:cornerRadius];
    self.progressLayer.path = progressPath.CGPath;
    self.progressLayer.fillColor = self.color.CGColor;

    [CATransaction commit];
}

+ (CGSize)defaultSize
{
    return CGSizeMake(150, 16);
}

- (CGSize)sizeThatFits:(CGSize)size
{
    return OWSProgressView.defaultSize;
}

- (CGSize)intrinsicContentSize
{
    return CGSizeMake(UIViewNoIntrinsicMetric, 16);
}

@end

NS_ASSUME_NONNULL_END
