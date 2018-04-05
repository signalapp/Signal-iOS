//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationViewItem;

typedef NS_ENUM(NSUInteger, OWSMessageGestureLocation) {
    // Message text, etc.
    OWSMessageGestureLocation_Default,
    OWSMessageGestureLocation_OversizeText,
    OWSMessageGestureLocation_Media,
    OWSMessageGestureLocation_QuotedReply,
};

@interface OWSMessageBubbleView : UIView

@property (nonatomic, nullable) ConversationViewItem *viewItem;

@property (nonatomic) int contentWidth;

@property (nonatomic) NSCache *cellMediaCache;

@property (nonatomic, nullable, readonly) UIView *lastBodyMediaView;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)configureViews;

- (void)loadContent;
- (void)unloadContent;

- (CGSize)sizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth;

- (void)prepareForReuse;

- (OWSMessageGestureLocation)gestureLocationForLocation:(CGPoint)locationInMessageBubble;

@end

NS_ASSUME_NONNULL_END
