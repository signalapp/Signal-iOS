//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleView.h"
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

const CGFloat kOWSMessageCellCornerRadius = 18;

const CGFloat kBubbleTextHInset = 10.f;
const CGFloat kBubbleTextTopInset = 8.f;
const CGFloat kBubbleTextBottomInset = 6.f;

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
    [CATransaction setDisableActions:YES];

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
    [CATransaction setDisableActions:YES];

    self.shapeLayer.fillColor = self.bubbleColor.CGColor;
    self.shapeLayer.path = bezierPath.CGPath;
    self.maskLayer.path = bezierPath.CGPath;

    [CATransaction commit];
}

- (UIBezierPath *)maskPath
{
    return [self.class maskPathForSize:self.bounds.size];
}

+ (UIBezierPath *)maskPathForSize:(CGSize)size
{
    CGRect bounds = CGRectZero;
    bounds.size = size;
    UIBezierPath *bezierPath = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:kOWSMessageCellCornerRadius];
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
    return (kOWSMessageCellCornerRadius * 2);
}

@end

NS_ASSUME_NONNULL_END
