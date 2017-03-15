//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSProgressView.h"

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
    self.backgroundColor = [UIColor clearColor];
    self.color = [UIColor whiteColor];

    self.borderLayer = [CAShapeLayer new];
    self.borderLayer.fillColor = self.color.CGColor;
    [self.layer addSublayer:self.borderLayer];

    self.progressLayer = [CAShapeLayer new];
    self.progressLayer.fillColor = self.color.CGColor;
    [self.layer addSublayer:self.progressLayer];

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
    CGFloat kBorderThickness = self.bounds.size.height * 0.15f;
    CGFloat kOuterRadius = self.bounds.size.height * 0.3f;
    CGFloat kInnerRadius = kOuterRadius - kBorderThickness;
    // We want to slightly overlap the border with the progress
    // to achieve a clean effect.
    CGFloat kProgressInset = kBorderThickness - 0.5f;

    UIBezierPath *borderPath = [UIBezierPath new];

    // Add the outer border.
    [borderPath appendPath:[UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:kOuterRadius]];
    [borderPath
        appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds, kBorderThickness, kBorderThickness)
                                              cornerRadius:kInnerRadius]];

    self.borderLayer.path = borderPath.CGPath;
    self.borderLayer.fillColor = self.color.CGColor;
    self.borderLayer.fillRule = kCAFillRuleEvenOdd;

    UIBezierPath *progressPath = [UIBezierPath new];

    // Add the inner progress.
    CGRect progressRect = CGRectInset(self.bounds, kProgressInset, kProgressInset);
    progressRect.size.width *= MAX(0.f, MIN(1.f, self.progress));
    [progressPath appendPath:[UIBezierPath bezierPathWithRect:progressRect]];

    self.progressLayer.path = progressPath.CGPath;
    self.progressLayer.fillColor = self.color.CGColor;
}

- (CGSize)sizeThatFits:(CGSize)size
{
    return CGSizeMake(150, 16);
}

- (CGSize)intrinsicContentSize
{
    return CGSizeMake(UIViewNoIntrinsicMetric, 16);
}

@end
