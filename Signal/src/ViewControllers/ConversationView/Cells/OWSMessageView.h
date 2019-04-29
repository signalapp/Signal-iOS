//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;

@protocol ConversationViewItem;

typedef NS_ENUM(NSUInteger, OWSMessageGestureLocation) {
    // Message text, etc.
    OWSMessageGestureLocation_Default,
    OWSMessageGestureLocation_OversizeText,
    OWSMessageGestureLocation_Media,
    OWSMessageGestureLocation_QuotedReply,
    OWSMessageGestureLocation_LinkPreview,
    OWSMessageGestureLocation_Sticker,
};

// A base class for views that can be used to render message cell contents.
@interface OWSMessageView : UIView

@property (nonatomic, nullable) id<ConversationViewItem> viewItem;

@property (nonatomic) ConversationStyle *conversationStyle;

@property (nonatomic) NSCache *cellMediaCache;

- (void)configureViews;

- (void)loadContent;
- (void)unloadContent;

- (CGSize)measureSize;

- (void)prepareForReuse;

+ (UIFont *)senderNameFont;
+ (NSDictionary *)senderNamePrimaryAttributes;
+ (NSDictionary *)senderNameSecondaryAttributes;

#pragma mark - Gestures

- (OWSMessageGestureLocation)gestureLocationForLocation:(CGPoint)locationInMessageBubble;

// This only needs to be called when we use the cell _outside_ the context
// of a conversation view message cell.
- (void)addTapGestureHandler;

- (void)handleTapGesture:(UITapGestureRecognizer *)sender;

@end

NS_ASSUME_NONNULL_END
