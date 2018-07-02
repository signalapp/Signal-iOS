//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleView.h"
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

const CGFloat kOWSMessageCellCornerRadius_Large = 16;
const CGFloat kOWSMessageCellCornerRadius_Small = 2;

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

    self.layoutMargins = UIEdgeInsetsZero;

    self.shapeLayer = [CAShapeLayer new];
    [self.layer addSublayer:self.shapeLayer];

    self.maskLayer = [CAShapeLayer new];
    self.layer.mask = self.maskLayer;

    _partnerViews = [NSMutableArray new];

    return self;
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

    [self updateLayers];

    // Prevent the shape layer from animating changes.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    self.shapeLayer.fillColor = bubbleColor.CGColor;

    [CATransaction commit];
}

- (void)setUseSmallCorners_Top:(BOOL)useSmallCorners_Top
{
    _useSmallCorners_Top = useSmallCorners_Top;

    [self updateLayers];
}

- (void)setUseSmallCorners_Bottom:(BOOL)useSmallCorners_Bottom
{
    _useSmallCorners_Bottom = useSmallCorners_Bottom;

    [self updateLayers];
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
    [CATransaction setDisableActions:YES];

    self.shapeLayer.fillColor = self.bubbleColor.CGColor;
    self.shapeLayer.path = bezierPath.CGPath;
    self.maskLayer.path = bezierPath.CGPath;

    [CATransaction commit];
}

- (UIBezierPath *)maskPath
{
    return [self.class maskPathForSize:self.bounds.size
                   useSmallCorners_Top:self.useSmallCorners_Top
                useSmallCorners_Bottom:self.useSmallCorners_Bottom];
}

+ (UIBezierPath *)maskPathForSize:(CGSize)size
              useSmallCorners_Top:(BOOL)useSmallCorners_Top
           useSmallCorners_Bottom:(BOOL)useSmallCorners_Bottom
{
    CGRect bounds = CGRectZero;
    bounds.size = size;

    UIBezierPath *bezierPath = [UIBezierPath new];

    CGFloat bubbleLeft = 0.f;
    CGFloat bubbleRight = size.width;
    CGFloat bubbleTop = 0.f;
    CGFloat bubbleBottom = size.height;
    CGFloat topRounding = (useSmallCorners_Top ? kOWSMessageCellCornerRadius_Small : kOWSMessageCellCornerRadius_Large);
    CGFloat bottomRounding
        = (useSmallCorners_Bottom ? kOWSMessageCellCornerRadius_Small : kOWSMessageCellCornerRadius_Large);

    [bezierPath moveToPoint:CGPointMake(bubbleLeft + topRounding, bubbleTop)];
    [bezierPath addLineToPoint:CGPointMake(bubbleRight - topRounding, bubbleTop)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleRight, bubbleTop + topRounding)
                       controlPoint:CGPointMake(bubbleRight, bubbleTop)];
    [bezierPath addLineToPoint:CGPointMake(bubbleRight, bubbleBottom - bottomRounding)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleRight - bottomRounding, bubbleBottom)
                       controlPoint:CGPointMake(bubbleRight, bubbleBottom)];
    [bezierPath addLineToPoint:CGPointMake(bubbleLeft + bottomRounding, bubbleBottom)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleLeft, bubbleBottom - bottomRounding)
                       controlPoint:CGPointMake(bubbleLeft, bubbleBottom)];
    [bezierPath addLineToPoint:CGPointMake(bubbleLeft, bubbleTop + topRounding)];
    [bezierPath addQuadCurveToPoint:CGPointMake(bubbleLeft + topRounding, bubbleTop)
                       controlPoint:CGPointMake(bubbleLeft, bubbleTop)];

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

- (CGFloat)minWidth
{
    if (self.useSmallCorners_Top && self.useSmallCorners_Bottom) {
        return (kOWSMessageCellCornerRadius_Small * 2);
    } else {
        return (kOWSMessageCellCornerRadius_Large * 2);
    }
}

@end

NS_ASSUME_NONNULL_END
