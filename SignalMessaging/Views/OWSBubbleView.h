//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kOWSMessageCellCornerRadius_Large;
extern const CGFloat kOWSMessageCellCornerRadius_Small;

typedef NS_OPTIONS(NSUInteger, OWSDirectionalRectCorner) {
    OWSDirectionalRectCornerTopLeading = 1 << 0,
    OWSDirectionalRectCornerTopTrailing = 1 << 1,
    OWSDirectionalRectCornerBottomLeading = 1 << 2,
    OWSDirectionalRectCornerBottomTrailing = 1 << 3,

    OWSDirectionalRectCornerAllCorners = OWSDirectionalRectCornerTopLeading | OWSDirectionalRectCornerTopTrailing
        | OWSDirectionalRectCornerBottomLeading | OWSDirectionalRectCornerBottomTrailing
};

@protocol OWSBubbleViewHost <NSObject>

@property (nonatomic, readonly) UIBezierPath *maskPath;
@property (nonatomic, readonly) UIView *bubbleReferenceView;

@end

#pragma mark -

@protocol OWSBubbleViewPartner <NSObject>

- (void)updateLayers;

- (void)setBubbleViewHost:(nullable id<OWSBubbleViewHost>)bubbleViewHost;

@end

#pragma mark -

@interface OWSBubbleView : UIView <OWSBubbleViewHost>

@property (nonatomic, nullable) UIColor *fillColor;
@property (nonatomic, nullable) NSArray<UIColor *> *fillGradientColors;
@property (nonatomic, nullable) UIColor *strokeColor;
@property (nonatomic) CGFloat strokeThickness;

@property (nonatomic) OWSDirectionalRectCorner sharpCorners;

@property (nonatomic) BOOL ensureSubviewsFillBounds;

@end

NS_ASSUME_NONNULL_END
