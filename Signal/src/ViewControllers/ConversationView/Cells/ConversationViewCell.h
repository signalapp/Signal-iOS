//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
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
- (void)didTapVideoViewItem:(ConversationViewItem *)viewItem attachmentStream:(TSAttachmentStream *)attachmentStream;
- (void)didTapAudioViewItem:(ConversationViewItem *)viewItem attachmentStream:(TSAttachmentStream *)attachmentStream;
- (void)didTapOversizeTextMessage:(NSString *)displayableText attachmentStream:(TSAttachmentStream *)attachmentStream;
- (void)didTapFailedIncomingAttachment:(ConversationViewItem *)viewItem
                     attachmentPointer:(TSAttachmentPointer *)attachmentPointer;
- (void)didTapFailedOutgoingMessage:(TSOutgoingMessage *)message;

- (void)showMetadataViewForMessage:(TSMessage *)message;

#pragma mark - System Cell

// TODO: We might want to decompose this method.
- (void)didTapSystemMessageWithInteraction:(TSInteraction *)interaction;
- (void)didLongPressSystemMessageCell:(ConversationViewCell *)systemMessageCell fromView:(UIView *)fromView;

#pragma mark - Offers

- (void)tappedUnknownContactBlockOfferMessage:(OWSContactOffersInteraction *)interaction;
- (void)tappedAddToContactsOfferMessage:(OWSContactOffersInteraction *)interaction;
- (void)tappedAddToProfileWhitelistOfferMessage:(OWSContactOffersInteraction *)interaction;

#pragma mark - Formatting

- (NSAttributedString *)attributedContactOrProfileNameForPhoneIdentifier:(NSString *)recipientId;

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
@property (nonatomic) BOOL isCellVisible;

@property (nonatomic) int contentWidth;

- (void)loadForDisplay;

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth;

@end

NS_ASSUME_NONNULL_END
