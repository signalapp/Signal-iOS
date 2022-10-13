//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

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

NS_ASSUME_NONNULL_END
