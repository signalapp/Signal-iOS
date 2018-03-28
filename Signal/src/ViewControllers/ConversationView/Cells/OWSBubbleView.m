//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleView.h"
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

// This approximates the curve of our message bubbles, which makes the animation feel a little smoother.
const CGFloat kOWSMessageCellCornerRadius = 17;

const CGFloat kBubbleVRounding = kOWSMessageCellCornerRadius;
const CGFloat kBubbleHRounding = kOWSMessageCellCornerRadius;
const CGFloat kBubbleThornSideInset = 5.f;
const CGFloat kBubbleThornVInset = 0;
const CGFloat kBubbleTextHInset = 10.f;
const CGFloat kBubbleTextVInset = 10.f;

@implementation OWSBubbleView

- (void)setIsOutgoing:(BOOL)isOutgoing
{
    BOOL didChange = _isOutgoing != isOutgoing;

    _isOutgoing = isOutgoing;

    if (didChange || !self.shapeLayer) {
        [self updateMask];
    }
}

- (void)setFrame:(CGRect)frame
{
    BOOL didChange = !CGSizeEqualToSize(self.frame.size, frame.size);

    [super setFrame:frame];

    if (didChange || !self.shapeLayer) {
        [self updateMask];
    }
}

- (void)setBounds:(CGRect)bounds
{
    BOOL didChange = !CGSizeEqualToSize(self.bounds.size, bounds.size);

    [super setBounds:bounds];

    if (didChange || !self.shapeLayer) {
        [self updateMask];
    }
}

- (void)setBubbleColor:(nullable UIColor *)bubbleColor
{
    _bubbleColor = bubbleColor;

    if (!self.shapeLayer) {
        [self updateMask];
    }
    self.shapeLayer.fillColor = bubbleColor.CGColor;
}

- (void)updateMask
{
    if (!self.shapeLayer) {
        self.shapeLayer = [CAShapeLayer new];
        [self.layer addSublayer:self.shapeLayer];
    }
    if (!self.maskLayer) {
        self.maskLayer = [CAShapeLayer new];
        self.layer.mask = self.maskLayer;
    }

    UIBezierPath *bezierPath =
        [self.class maskPathForSize:self.bounds.size isOutgoing:self.isOutgoing isRTL:self.isRTL];

    self.shapeLayer.fillColor = self.bubbleColor.CGColor;
    self.shapeLayer.path = bezierPath.CGPath;

    self.maskLayer.path = bezierPath.CGPath;
}

+ (UIBezierPath *)maskPathForSize:(CGSize)size isOutgoing:(BOOL)isOutgoing isRTL:(BOOL)isRTL
{
    UIBezierPath *bezierPath = [UIBezierPath new];

    CGFloat bubbleLeft = 0.f;
    CGFloat bubbleRight = size.width - kBubbleThornSideInset;
    CGFloat bubbleTop = 0.f;
    CGFloat bubbleBottom = size.height - kBubbleThornVInset;

    [bezierPath moveToPoint:CGPointMake(bubbleLeft + kBubbleHRounding, bubbleTop)];
    [bezierPath addLineToPoint:CGPointMake(bubbleRight - kBubbleHRounding, bubbleTop)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleRight, bubbleTop + kBubbleVRounding)
                       controlPoint:CGPointMake(bubbleRight, bubbleTop)];
    [bezierPath addLineToPoint:CGPointMake(bubbleRight, bubbleBottom - kBubbleVRounding)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleRight - kBubbleHRounding, bubbleBottom)
                       controlPoint:CGPointMake(bubbleRight, bubbleBottom)];
    [bezierPath addLineToPoint:CGPointMake(bubbleLeft + kBubbleHRounding, bubbleBottom)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleLeft, bubbleBottom - kBubbleVRounding)
                       controlPoint:CGPointMake(bubbleLeft, bubbleBottom)];
    [bezierPath addLineToPoint:CGPointMake(bubbleLeft, bubbleTop + kBubbleVRounding)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleLeft + kBubbleHRounding, bubbleTop)
                       controlPoint:CGPointMake(bubbleLeft, bubbleTop)];

    // Thorn Tip
    CGPoint thornTip = CGPointMake(size.width + 1, size.height);
    CGPoint thornA = CGPointMake(bubbleRight - kBubbleHRounding * 0.5f, bubbleBottom - kBubbleVRounding);
    CGPoint thornB = CGPointMake(bubbleRight, bubbleBottom - kBubbleVRounding);
    [bezierPath moveToPoint:thornTip];
    [bezierPath addQuadCurveToPoint:thornA controlPoint:CGPointMake(thornA.x, bubbleBottom)];
    [bezierPath addLineToPoint:thornB];
    [bezierPath addQuadCurveToPoint:thornTip controlPoint:CGPointMake(thornB.x, bubbleBottom)];
    [bezierPath addLineToPoint:thornTip];

    // Horizontal Flip If Necessary
    BOOL shouldFlip = isOutgoing == isRTL;
    if (shouldFlip) {
        CGAffineTransform flipTransform = CGAffineTransformMakeTranslation(size.width, 0.0);
        flipTransform = CGAffineTransformScale(flipTransform, -1.0, 1.0);
        [bezierPath applyTransform:flipTransform];
    }
    return bezierPath;
}

@end

NS_ASSUME_NONNULL_END
