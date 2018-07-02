//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleView.h"

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kOWSMessageCellCornerRadius_Large;
extern const CGFloat kOWSMessageCellCornerRadius_Small;

@class OWSBubbleView;

@protocol OWSBubbleViewPartner <NSObject>

- (void)updateLayers;

- (void)setBubbleView:(OWSBubbleView *)bubbleView;

@end

#pragma mark -

@interface OWSBubbleView : UIView

@property (nonatomic, nullable) UIColor *bubbleColor;

@property (nonatomic) BOOL useSmallCorners_Top;
@property (nonatomic) BOOL useSmallCorners_Bottom;

- (UIBezierPath *)maskPath;

#pragma mark - Coordination

- (void)addPartnerView:(id<OWSBubbleViewPartner>)view;

- (void)clearPartnerViews;

- (void)updatePartnerViews;

- (CGFloat)minWidth;

@end

NS_ASSUME_NONNULL_END
