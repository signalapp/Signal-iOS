//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleView.h"
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

const CGFloat kOWSMessageCellCornerRadius_Large = 18;
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

- (void)setSharpCorners:(UIRectCorner)sharpCorners
{
    _sharpCorners = sharpCorners;

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
    return [self.class maskPathForSize:self.bounds.size sharpCorners:self.sharpCorners];
}

+ (UIBezierPath *)maskPathForSize:(CGSize)size sharpCorners:(UIRectCorner)sharpCorners
{
    CGRect bounds = CGRectZero;
    bounds.size = size;

    UIBezierPath *bezierPath = [UIBezierPath new];

    CGFloat bubbleLeft = 0.f;
    CGFloat bubbleRight = size.width;
    CGFloat bubbleTop = 0.f;
    CGFloat bubbleBottom = size.height;

    CGFloat topLeftRounding
        = (sharpCorners & UIRectCornerTopLeft) ? kOWSMessageCellCornerRadius_Small : kOWSMessageCellCornerRadius_Large;
    CGFloat topRightRounding
        = (sharpCorners & UIRectCornerTopRight) ? kOWSMessageCellCornerRadius_Small : kOWSMessageCellCornerRadius_Large;
    CGFloat bottomRightRounding = (sharpCorners & UIRectCornerBottomRight) ? kOWSMessageCellCornerRadius_Small
                                                                           : kOWSMessageCellCornerRadius_Large;
    CGFloat bottomLeftRounding = (sharpCorners & UIRectCornerBottomLeft) ? kOWSMessageCellCornerRadius_Small
                                                                         : kOWSMessageCellCornerRadius_Large;

    const CGFloat topAngle = 3.0f * M_PI_2;
    const CGFloat rightAngle = 0.0f;
    const CGFloat bottomAngle = M_PI_2;
    const CGFloat leftAngle = M_PI;

    // starting just to the right of the top left corner and working clockwise
    [bezierPath moveToPoint:CGPointMake(bubbleLeft + topLeftRounding, bubbleTop)];

    // top right corner
    [bezierPath addArcWithCenter:CGPointMake(bubbleRight - topRightRounding, bubbleTop + topRightRounding)
                          radius:topRightRounding
                      startAngle:topAngle
                        endAngle:rightAngle
                       clockwise:true];

    // bottom right corner
    [bezierPath addArcWithCenter:CGPointMake(bubbleRight - bottomRightRounding, bubbleBottom - bottomRightRounding)
                          radius:bottomRightRounding
                      startAngle:rightAngle
                        endAngle:bottomAngle
                       clockwise:true];

    // bottom left corner
    [bezierPath addArcWithCenter:CGPointMake(bubbleLeft + bottomLeftRounding, bubbleBottom - bottomLeftRounding)
                          radius:bottomLeftRounding
                      startAngle:bottomAngle
                        endAngle:leftAngle
                       clockwise:true];

    // top left corner
    [bezierPath addArcWithCenter:CGPointMake(bubbleLeft + topLeftRounding, bubbleTop + topLeftRounding)
                          radius:topLeftRounding
                      startAngle:leftAngle
                        endAngle:topAngle
                       clockwise:true];

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
    return (kOWSMessageCellCornerRadius_Large * 2);
}

@end

NS_ASSUME_NONNULL_END
