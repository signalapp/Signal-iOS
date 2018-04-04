//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationViewCell;
@class ConversationViewItem;
@class OWSContactOffersInteraction;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSInteraction;
@class TSMessage;
@class TSOutgoingMessage;

@protocol ConversationViewCellDelegate <NSObject>

- (void)didTapImageViewItem:(ConversationViewItem *)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIView *)imageView;
- (void)didTapVideoViewItem:(ConversationViewItem *)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIView *)imageView;
- (void)didTapAudioViewItem:(ConversationViewItem *)viewItem attachmentStream:(TSAttachmentStream *)attachmentStream;
- (void)didTapTruncatedTextMessage:(ConversationViewItem *)conversationItem;
- (void)didTapFailedIncomingAttachment:(ConversationViewItem *)viewItem
                     attachmentPointer:(TSAttachmentPointer *)attachmentPointer;
- (void)didTapFailedOutgoingMessage:(TSOutgoingMessage *)message;
- (void)didPanWithGestureRecognizer:(UIPanGestureRecognizer *)gestureRecognizer
                           viewItem:(ConversationViewItem *)conversationItem;

- (void)showMetadataViewForViewItem:(ConversationViewItem *)conversationItem;
- (void)conversationCell:(ConversationViewCell *)cell didTapReplyForViewItem:(ConversationViewItem *)conversationItem;

#pragma mark - System Cell

// TODO: We might want to decompose this method.
- (void)didTapSystemMessageWithInteraction:(TSInteraction *)interaction;

#pragma mark - Offers

- (void)tappedUnknownContactBlockOfferMessage:(OWSContactOffersInteraction *)interaction;
- (void)tappedAddToContactsOfferMessage:(OWSContactOffersInteraction *)interaction;
- (void)tappedAddToProfileWhitelistOfferMessage:(OWSContactOffersInteraction *)interaction;

#pragma mark - Formatting

- (NSAttributedString *)attributedContactOrProfileNameForPhoneIdentifier:(NSString *)recipientId;

#pragma mark - Caching

- (NSCache *)cellMediaCache;

@end

#pragma mark -

// TODO: Consider making this a protocol.
@interface ConversationViewCell : UICollectionViewCell

@property (nonatomic, nullable, weak) id<ConversationViewCellDelegate> delegate;

@property (nonatomic, nullable) ConversationViewItem *viewItem;

// Cells are prefetched but expensive cells (e.g. media) should only load
// when visible and unload when no longer visible.  Non-visible cells can
// cache their contents on their ConversationViewItem, but that cache may
// be evacuated before the cell becomes visible again.
//
// ConversationViewController also uses this property to evacuate the cell's
// meda views when:
//
// * App enters background.
// * Users enters another view (e.g. conversation settings view, call screen, etc.).
@property (nonatomic) BOOL isCellVisible;

// The width of the collection view.
@property (nonatomic) int contentWidth;

- (void)loadForDisplay;

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth;

@end

NS_ASSUME_NONNULL_END
