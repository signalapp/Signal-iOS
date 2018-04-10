//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleView.h"

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kOWSMessageCellCornerRadius;

extern const CGFloat kBubbleVRounding;
extern const CGFloat kBubbleHRounding;
extern const CGFloat kBubbleThornSideInset;
extern const CGFloat kBubbleThornVInset;
extern const CGFloat kBubbleTextHInset;
extern const CGFloat kBubbleTextVInset;

@class OWSBubbleView;

@protocol OWSBubbleViewPartner <NSObject>

- (void)updateLayers;

- (void)setBubbleView:(OWSBubbleView *)bubbleView;

@end

#pragma mark -

@interface OWSBubbleView : UIView

@property (nonatomic) BOOL isOutgoing;
@property (nonatomic) BOOL hideTail;
@property (nonatomic) BOOL isTruncated;

@property (nonatomic, nullable) UIColor *bubbleColor;

- (UIBezierPath *)maskPath;

#pragma mark - Coordination

- (void)addPartnerView:(id<OWSBubbleViewPartner>)view;

- (void)clearPartnerViews;

- (void)updatePartnerViews;

+ (CGFloat)minWidth;

@end

NS_ASSUME_NONNULL_END
