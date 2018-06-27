//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleView.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSBubbleView;

@interface OWSBubbleShapeView : UIView <OWSBubbleViewPartner>

@property (nonatomic, nullable) UIColor *fillColor;
@property (nonatomic, nullable) UIColor *strokeColor;
@property (nonatomic) CGFloat strokeThickness;

- (instancetype)init NS_UNAVAILABLE;

+ (OWSBubbleShapeView *)bubbleDrawView;
+ (OWSBubbleShapeView *)bubbleShadowView;
+ (OWSBubbleShapeView *)bubbleClipView;

@end

NS_ASSUME_NONNULL_END
