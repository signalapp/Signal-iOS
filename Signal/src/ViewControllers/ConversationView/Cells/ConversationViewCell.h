//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;
@class ConversationViewCell;
@class OWSContactsManager;
@class SignalServiceAddress;
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

- (void)conversationCell:(ConversationViewCell *)cell
            shouldAllowReply:(BOOL)shouldAllowReply
    didLongpressTextViewItem:(id<ConversationViewItem>)viewItem;
- (void)conversationCell:(ConversationViewCell *)cell
             shouldAllowReply:(BOOL)shouldAllowReply
    didLongpressMediaViewItem:(id<ConversationViewItem>)viewItem;
- (void)conversationCell:(ConversationViewCell *)cell
             shouldAllowReply:(BOOL)shouldAllowReply
    didLongpressQuoteViewItem:(id<ConversationViewItem>)viewItem;
- (void)conversationCell:(ConversationViewCell *)cell
    didLongpressSystemMessageViewItem:(id<ConversationViewItem>)viewItem;
- (void)conversationCell:(ConversationViewCell *)cell
        shouldAllowReply:(BOOL)shouldAllowReply
     didLongpressSticker:(id<ConversationViewItem>)viewItem;
- (void)conversationCell:(ConversationViewCell *)cell didReplyToItem:(id<ConversationViewItem>)viewItem;
- (void)conversationCell:(ConversationViewCell *)cell didTapAvatar:(id<ConversationViewItem>)viewItem;
- (BOOL)conversationCell:(ConversationViewCell *)cell shouldAllowReplyForItem:(id<ConversationViewItem>)viewItem;
- (void)conversationCell:(ConversationViewCell *)cell didChangeLongpress:(id<ConversationViewItem>)viewItem;
- (void)conversationCell:(ConversationViewCell *)cell didEndLongpress:(id<ConversationViewItem>)viewItem;
- (void)conversationCell:(ConversationViewCell *)cell didTapReactions:(id<ConversationViewItem>)viewItem;
- (BOOL)conversationCellHasPendingMessageRequest:(ConversationViewCell *)cell;

#pragma mark - Selection

@property (nonatomic, readonly) BOOL isShowingSelectionUI;
- (BOOL)isViewItemSelected:(id<ConversationViewItem>)viewItem;
- (void)conversationCell:(ConversationViewCell *)cell didSelectViewItem:(id<ConversationViewItem>)viewItem;
- (void)conversationCell:(ConversationViewCell *)cell didDeselectViewItem:(id<ConversationViewItem>)viewItem;

#pragma mark - System Cell

- (void)tappedNonBlockingIdentityChangeForAddress:(nullable SignalServiceAddress *)address;
- (void)tappedInvalidIdentityKeyErrorMessage:(TSInvalidIdentityKeyErrorMessage *)errorMessage;
- (void)tappedCorruptedMessage:(TSErrorMessage *)message;
- (void)resendGroupUpdateForErrorMessage:(TSErrorMessage *)message;
- (void)showFingerprintWithAddress:(SignalServiceAddress *)address;
- (void)showConversationSettings;
- (void)handleCallTap:(TSCall *)call;
- (void)updateSystemContactWithAddress:(SignalServiceAddress *)address
                 withNewNameComponents:(NSPersonNameComponents *)newNameComponents;

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

@class MessageSelectionView;

@protocol SelectableConversationCell <NSObject>

@property (nonatomic, readonly) MessageSelectionView *selectionView;

@end


NS_ASSUME_NONNULL_END
