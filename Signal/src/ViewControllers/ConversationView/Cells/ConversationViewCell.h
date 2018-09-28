//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;
@class ConversationViewCell;
@class OWSContactOffersInteraction;
@class OWSContactsManager;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSCall;
@class TSErrorMessage;
@class TSInteraction;
@class TSInvalidIdentityKeyErrorMessage;
@class TSMessage;
@class TSOutgoingMessage;
@class TSQuotedMessage;

@protocol ConversationViewItem;

@protocol ConversationViewCellDelegate <NSObject>

- (void)conversationCell:(ConversationViewCell *)cell didLongpressTextViewItem:(id<ConversationViewItem>)viewItem;
- (void)conversationCell:(ConversationViewCell *)cell didLongpressMediaViewItem:(id<ConversationViewItem>)viewItem;
- (void)conversationCell:(ConversationViewCell *)cell didLongpressQuoteViewItem:(id<ConversationViewItem>)viewItem;
- (void)conversationCell:(ConversationViewCell *)cell
    didLongpressSystemMessageViewItem:(id<ConversationViewItem>)viewItem;

#pragma mark - System Cell

- (void)tappedNonBlockingIdentityChangeForRecipientId:(nullable NSString *)signalId;
- (void)tappedInvalidIdentityKeyErrorMessage:(TSInvalidIdentityKeyErrorMessage *)errorMessage;
- (void)tappedCorruptedMessage:(TSErrorMessage *)message;
- (void)resendGroupUpdateForErrorMessage:(TSErrorMessage *)message;
- (void)showFingerprintWithRecipientId:(NSString *)recipientId;
- (void)showConversationSettings;
- (void)handleCallTap:(TSCall *)call;

#pragma mark - Offers

- (void)tappedUnknownContactBlockOfferMessage:(OWSContactOffersInteraction *)interaction;
- (void)tappedAddToContactsOfferMessage:(OWSContactOffersInteraction *)interaction;
- (void)tappedAddToProfileWhitelistOfferMessage:(OWSContactOffersInteraction *)interaction;

#pragma mark - Formatting

- (NSAttributedString *)attributedContactOrProfileNameForPhoneIdentifier:(NSString *)recipientId;

#pragma mark - Caching

- (NSCache *)cellMediaCache;

#pragma mark - Messages

- (void)didTapFailedOutgoingMessage:(TSOutgoingMessage *)message;

#pragma mark - Contacts

- (OWSContactsManager *)contactsManager;

@end

#pragma mark -

// TODO: Consider making this a protocol.
@interface ConversationViewCell : UICollectionViewCell

@property (nonatomic, nullable, weak) id<ConversationViewCellDelegate> delegate;

@property (nonatomic, nullable) id<ConversationViewItem> viewItem;

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

@property (nonatomic, nullable) ConversationStyle *conversationStyle;

- (void)loadForDisplay;

- (CGSize)cellSize;

@end

NS_ASSUME_NONNULL_END
