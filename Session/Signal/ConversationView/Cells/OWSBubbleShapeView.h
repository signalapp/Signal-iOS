//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleView.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSBubbleView;

// While rendering message bubbles, we often need to render
// into a subregion of the bubble that reflects the intersection
// of some subview (e.g. a media view) and the bubble shape
// (including its rounding).
//
// This view serves three different roles:
//
// * Drawing: Filling and/or stroking a subregion of the bubble shape.
// * Shadows: Casting a shadow over a subregion of the bubble shape.
// * Clipping: Clipping subviews to subregion of the bubble shape.
@interface OWSBubbleShapeView : UIView <OWSBubbleViewPartner>

@property (nonatomic, nullable) UIColor *fillColor;
@property (nonatomic, nullable) UIColor *strokeColor;
@property (nonatomic) CGFloat strokeThickness;

@property (nonatomic, nullable) UIColor *innerShadowColor;
@property (nonatomic) CGFloat innerShadowRadius;
@property (nonatomic) float innerShadowOpacity;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initDraw NS_DESIGNATED_INITIALIZER;
- (instancetype)initShadow NS_DESIGNATED_INITIALIZER;
- (instancetype)initClip NS_DESIGNATED_INITIALIZER;
- (instancetype)initInnerShadowWithColor:(UIColor *)color
                                  radius:(CGFloat)radius
                                 opacity:(float)opacity NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
