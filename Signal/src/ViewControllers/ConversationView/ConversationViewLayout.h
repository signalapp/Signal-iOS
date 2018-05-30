//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ConversationViewLayoutAlignment) {
    // We use incoming/outgoing, not left/right to support RTL.
    ConversationViewLayoutAlignment_Incoming,
    ConversationViewLayoutAlignment_Outgoing,
    ConversationViewLayoutAlignment_FullWidth,
    ConversationViewLayoutAlignment_Center,
};

@protocol ConversationViewLayoutItem <NSObject>

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth;

- (ConversationViewLayoutAlignment)layoutAlignment;

@end

#pragma mark -

@protocol ConversationViewLayoutDelegate <NSObject>

- (NSArray<id<ConversationViewLayoutItem>> *)layoutItems;

- (CGFloat)layoutHeaderHeight;

@end

#pragma mark -

// A new lean and efficient layout for conversation view designed to
// handle our edge cases (e.g. full-width unread indicators, etc.).
@interface ConversationViewLayout : UICollectionViewLayout

@property (nonatomic, weak) id<ConversationViewLayoutDelegate> delegate;
@property (nonatomic, readonly) BOOL hasLayout;
@property (nonatomic, readonly) BOOL hasEverHadLayout;
@property (nonatomic, readonly) int contentWidth;

@end

NS_ASSUME_NONNULL_END
