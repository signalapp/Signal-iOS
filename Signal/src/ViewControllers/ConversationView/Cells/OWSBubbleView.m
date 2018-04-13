//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleView.h"
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

@property (nonatomic, readonly) NSMutableArray<id<OWSBubbleViewPartner>> *partnerViews;

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

    _partnerViews = [NSMutableArray new];

    return self;
}

- (void)setIsOutgoing:(BOOL)isOutgoing
{
    BOOL didChange = _isOutgoing != isOutgoing;

    _isOutgoing = isOutgoing;

    if (didChange) {
        [self updateLayers];
    }
}

- (void)setHideTail:(BOOL)hideTail
{
    BOOL didChange = _hideTail != hideTail;

    _hideTail = hideTail;

    if (didChange) {
        [self updateLayers];
    }
}

- (void)setIsTruncated:(BOOL)isTruncated
{
    BOOL didChange = _isTruncated != isTruncated;

    _isTruncated = isTruncated;

    if (didChange) {
        [self updateLayers];
    }
}

- (void)setFrame:(CGRect)frame
{
    // We only need to update our layers if the _size_ of this view
    // changes since the contents of the layers are in local coordinates.
    BOOL didChangeSize = !CGSizeEqualToSize(self.frame.size, frame.size);

    [super setFrame:frame];

    if (didChangeSize) {
        [self updateLayers];
    }

    // We always need to inform the "bubble stroke view" (if any) if our
    // frame/bounds/center changes. Its contents are not in local coordinates.
    [self updatePartnerViews];
}

- (void)setBounds:(CGRect)bounds
{
    // We only need to update our layers if the _size_ of this view
    // changes since the contents of the layers are in local coordinates.
    BOOL didChangeSize = !CGSizeEqualToSize(self.bounds.size, bounds.size);

    [super setBounds:bounds];

    if (didChangeSize) {
        [self updateLayers];
    }

    // We always need to inform the "bubble stroke view" (if any) if our
    // frame/bounds/center changes. Its contents are not in local coordinates.
    [self updatePartnerViews];
}

- (void)setCenter:(CGPoint)center
{
    [super setCenter:center];

    // We always need to inform the "bubble stroke view" (if any) if our
    // frame/bounds/center changes. Its contents are not in local coordinates.
    [self updatePartnerViews];
}

- (void)setBubbleColor:(nullable UIColor *)bubbleColor
{
    _bubbleColor = bubbleColor;

    if (!self.shapeLayer) {
        [self updateLayers];
    }

    // Prevent the shape layer from animating changes.
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];

    self.shapeLayer.fillColor = bubbleColor.CGColor;

    [CATransaction commit];
}

- (void)updateLayers
{
    if (!self.maskLayer) {
        return;
    }
    if (!self.shapeLayer) {
        return;
    }

    UIBezierPath *bezierPath = [self maskPath];

    // Prevent the shape layer from animating changes.
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];

    self.shapeLayer.fillColor = self.bubbleColor.CGColor;
    self.shapeLayer.path = bezierPath.CGPath;
    self.maskLayer.path = bezierPath.CGPath;

    [CATransaction commit];
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

    if (hideTail) {
        [bezierPath addQuadCurveToPoint:CGPointMake(bubbleRight - kBubbleHRounding, bubbleBottom)
                           controlPoint:CGPointMake(bubbleRight, bubbleBottom)];
    } else {
        // Thorn Tip
        CGPoint thornTip = CGPointMake(size.width + 1, size.height);
        CGPoint thornB = CGPointMake(bubbleRight, bubbleBottom - kBubbleVRounding);
        // Approximate intersection of the thorn and the bubble edge.
        CGPoint thornPrime
            = CGPointMake(bubbleRight - kBubbleHRounding * 0.25f, bubbleBottom - kBubbleVRounding * 0.25f);
        CGPoint thornPrimeA = CGPointMake(thornPrime.x, bubbleBottom - kBubbleVRounding * 0.08f);

        [bezierPath addQuadCurveToPoint:thornTip controlPoint:CGPointMake(thornB.x, bubbleBottom)];
        [bezierPath addQuadCurveToPoint:thornPrime controlPoint:thornPrimeA];
        [bezierPath addQuadCurveToPoint:CGPointMake(bubbleRight - kBubbleHRounding, bubbleBottom)
                           controlPoint:thornPrimeA];
    }

    [bezierPath addLineToPoint:CGPointMake(bubbleLeft + kBubbleHRounding, bubbleBottom)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleLeft, bubbleBottom - kBubbleVRounding)
                       controlPoint:CGPointMake(bubbleLeft, bubbleBottom)];
    [bezierPath addLineToPoint:CGPointMake(bubbleLeft, bubbleTop + kBubbleVRounding)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleLeft + kBubbleHRounding, bubbleTop)
                       controlPoint:CGPointMake(bubbleLeft, bubbleTop)];

    // Horizontal Flip If Necessary
    BOOL shouldFlip = isOutgoing == isRTL;
    if (shouldFlip) {
        CGAffineTransform flipTransform = CGAffineTransformMakeTranslation(size.width, 0.0);
        flipTransform = CGAffineTransformScale(flipTransform, -1.0, 1.0);
        [bezierPath applyTransform:flipTransform];
    }
    return bezierPath;
}

#pragma mark - Coordination

- (void)addPartnerView:(id<OWSBubbleViewPartner>)partnerView
{
    OWSAssert(self.partnerViews);

    [partnerView setBubbleView:self];

    [self.partnerViews addObject:partnerView];
}

- (void)clearPartnerViews
{
    OWSAssert(self.partnerViews);

    [self.partnerViews removeAllObjects];
}

- (void)updatePartnerViews
{
    [self layoutIfNeeded];

    for (id<OWSBubbleViewPartner> partnerView in self.partnerViews) {
        [partnerView updateLayers];
    }
}

+ (CGFloat)minWidth
{
    return (kBubbleHRounding * 2 + kBubbleThornSideInset);
}

@end

NS_ASSUME_NONNULL_END
