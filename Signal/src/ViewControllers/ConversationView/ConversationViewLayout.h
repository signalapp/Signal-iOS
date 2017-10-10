//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ConversationViewLayoutAlignment) {
    ConversationViewLayoutAlignment_Incoming,
    ConversationViewLayoutAlignment_Outgoing,
    ConversationViewLayoutAlignment_FullWidth,
    ConversationViewLayoutAlignment_Center,
};

@protocol ConversationViewLayoutItem <NSObject>

// TODO: Perhaps maxMessageWidth should be an implementation detail of the
//       message cells.
- (CGSize)cellSizeForViewWidth:(int)viewWidth maxMessageWidth:(int)maxMessageWidth;

- (ConversationViewLayoutAlignment)layoutAlignment;

@end

#pragma mark -

@protocol ConversationViewLayoutDelegate <NSObject>

- (NSArray<id<ConversationViewLayoutItem>> *)layoutItems;

@end

#pragma mark -

@interface ConversationViewLayout : UICollectionViewLayout

@property (nonatomic, weak) id<ConversationViewLayoutDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
