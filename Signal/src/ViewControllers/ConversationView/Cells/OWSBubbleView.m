//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleView.h"
#import "OWSBubbleStrokeView.h"
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

const CGFloat kOWSMessageCellCornerRadius = 17;

const CGFloat kBubbleVRounding = kOWSMessageCellCornerRadius;
const CGFloat kBubbleHRounding = kOWSMessageCellCornerRadius;
const CGFloat kBubbleThornSideInset = 5.f;
const CGFloat kBubbleThornVInset = 0;
const CGFloat kBubbleTextHInset = 10.f;
const CGFloat kBubbleTextVInset = 10.f;

@interface OWSBubbleView ()

@property (nonatomic) CAShapeLayer *maskLayer;
@property (nonatomic) CAShapeLayer *shapeLayer;

@end

#pragma mark -

@implementation OWSBubbleView

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.shapeLayer = [CAShapeLayer new];
    [self.layer addSublayer:self.shapeLayer];

    self.maskLayer = [CAShapeLayer new];
    self.layer.mask = self.maskLayer;

    return self;
}

- (void)setIsOutgoing:(BOOL)isOutgoing
{
    BOOL didChange = _isOutgoing != isOutgoing;

    _isOutgoing = isOutgoing;

    if (didChange || !self.shapeLayer) {
        [self updateLayers];
    }
}

- (void)setHideTail:(BOOL)hideTail
{
    BOOL didChange = _hideTail != hideTail;

    _hideTail = hideTail;

    if (didChange || !self.shapeLayer) {
        [self updateLayers];
    }
}

- (void)setIsTruncated:(BOOL)isTruncated
{
    BOOL didChange = _isTruncated != isTruncated;

    _isTruncated = isTruncated;

    if (didChange || !self.shapeLayer) {
        [self updateLayers];
    }
}

- (void)setFrame:(CGRect)frame
{
    // We only need to update our layers if the _size_ of this view
    // changes since the contents of the layers are in local coordinates.
    BOOL didChangeSize = !CGSizeEqualToSize(self.frame.size, frame.size);

    [super setFrame:frame];

    if (didChangeSize || !self.shapeLayer) {
        [self updateLayers];
    }

    // We always need to inform the "bubble stroke view" (if any) if our
    // frame/bounds/center changes. Its contents are not in local coordinates.
    [self.bubbleStrokeView updateLayers];
}

- (void)setBounds:(CGRect)bounds
{
    // We only need to update our layers if the _size_ of this view
    // changes since the contents of the layers are in local coordinates.
    BOOL didChangeSize = !CGSizeEqualToSize(self.bounds.size, bounds.size);

    [super setBounds:bounds];

    if (didChangeSize || !self.shapeLayer) {
        [self updateLayers];
    }

    // We always need to inform the "bubble stroke view" (if any) if our
    // frame/bounds/center changes. Its contents are not in local coordinates.
    [self.bubbleStrokeView updateLayers];
}

- (void)setCenter:(CGPoint)center
{
    [super setCenter:center];

    // We always need to inform the "bubble stroke view" (if any) if our
    // frame/bounds/center changes. Its contents are not in local coordinates.
    [self.bubbleStrokeView updateLayers];
}

- (void)setBubbleColor:(nullable UIColor *)bubbleColor
{
    _bubbleColor = bubbleColor;

    if (!self.shapeLayer) {
        [self updateLayers];
    }
    self.shapeLayer.fillColor = bubbleColor.CGColor;
}

- (void)updateLayers
{
    OWSAssert(self.maskLayer);
    OWSAssert(self.shapeLayer);

    UIBezierPath *bezierPath = [self maskPath];

    self.shapeLayer.fillColor = self.bubbleColor.CGColor;
    self.shapeLayer.path = bezierPath.CGPath;
    self.maskLayer.path = bezierPath.CGPath;
}

- (UIBezierPath *)maskPath
{
    return [self.class maskPathForSize:self.bounds.size
                            isOutgoing:self.isOutgoing
                              hideTail:self.hideTail
                           isTruncated:self.isTruncated
                                 isRTL:self.isRTL];
}

+ (UIBezierPath *)maskPathForSize:(CGSize)size
                       isOutgoing:(BOOL)isOutgoing
                         hideTail:(BOOL)hideTail
                      isTruncated:(BOOL)isTruncated
                            isRTL:(BOOL)isRTL
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

    if (!hideTail) {
        // Thorn Tip
        CGPoint thornTip = CGPointMake(size.width + 1, size.height);
        CGPoint thornA = CGPointMake(bubbleRight - kBubbleHRounding * 0.5f, bubbleBottom - kBubbleVRounding);
        CGPoint thornB = CGPointMake(bubbleRight, bubbleBottom - kBubbleVRounding);
        [bezierPath moveToPoint:thornTip];
        [bezierPath addQuadCurveToPoint:thornA controlPoint:CGPointMake(thornA.x, bubbleBottom)];
        [bezierPath addLineToPoint:thornB];
        [bezierPath addQuadCurveToPoint:thornTip controlPoint:CGPointMake(thornB.x, bubbleBottom)];
        [bezierPath addLineToPoint:thornTip];
    }

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
