//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewLayout.h"
#import "OWSAudioPlayer.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSInteger, OWSMessageCellType) {
    OWSMessageCellType_Unknown,
    OWSMessageCellType_TextOnlyMessage,
    OWSMessageCellType_Audio,
    OWSMessageCellType_GenericAttachment,
    OWSMessageCellType_ContactShare,
    OWSMessageCellType_MediaMessage,
    OWSMessageCellType_OversizeTextDownloading,
    OWSMessageCellType_StickerMessage,
    OWSMessageCellType_ViewOnce,
};

NSString *NSStringForOWSMessageCellType(OWSMessageCellType cellType);

#pragma mark -

typedef NS_ENUM(NSUInteger, ViewOnceMessageState) {
    ViewOnceMessageState_Unknown = 0,
    ViewOnceMessageState_IncomingExpired,
    ViewOnceMessageState_IncomingDownloading,
    ViewOnceMessageState_IncomingFailed,
    ViewOnceMessageState_IncomingAvailable,
    ViewOnceMessageState_IncomingInvalidContent,
    ViewOnceMessageState_OutgoingSending,
    ViewOnceMessageState_OutgoingFailed,
    ViewOnceMessageState_OutgoingSentExpired,
};

NSString *NSStringForViewOnceMessageState(ViewOnceMessageState value);

@class AudioMessageView;
@class ContactShareViewModel;
@class ConversationViewCell;
@class DisplayableText;
@class InteractionReactionState;
@class OWSLinkPreview;
@class OWSQuotedReplyModel;
@class SDSAnyReadTransaction;
@class SignalServiceAddress;
@class StickerInfo;
@class TSAttachment;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSGroupThread;
@class TSInteraction;
@class TSThread;

@interface ConversationMediaAlbumItem : NSObject

@property (nonatomic, readonly) TSAttachment *attachment;

// This property will only be set if the attachment is downloaded.
@property (nonatomic, readonly, nullable) TSAttachmentStream *attachmentStream;

// This property will be non-zero if the attachment is valid.
@property (nonatomic, readonly) CGSize mediaSize;

@property (nonatomic, readonly, nullable) NSString *caption;

@property (nonatomic, readonly) BOOL isFailedDownload;

@end

#pragma mark -

// This is a ViewModel for cells in the conversation view.
//
// The lifetime of this class is the lifetime of that cell
// in the load window of the conversation view.
//
// Critically, this class implements ConversationViewLayoutItem
// and does caching of the cell's size.
@protocol ConversationViewItem <NSObject, ConversationViewLayoutItem, OWSAudioPlayerDelegate>

@property (nonatomic, readonly) TSInteraction *interaction;

@property (nonatomic, readonly) TSThread *thread;
@property (nonatomic, readonly) BOOL isGroupThread;

@property (nonatomic, readonly) BOOL hasBodyText;

@property (nonatomic, readonly) BOOL isQuotedReply;
@property (nonatomic, readonly) BOOL hasQuotedAttachment;
@property (nonatomic, readonly) BOOL hasQuotedText;

@property (nonatomic, readonly) BOOL hasPerConversationExpiration;
@property (nonatomic, readonly) BOOL isViewOnceMessage;

@property (nonatomic, readonly) BOOL canShowDate;
@property (nonatomic) BOOL shouldShowSenderAvatar;
@property (nonatomic, nullable) NSAttributedString *senderName;
@property (nonatomic, nullable) NSString *senderUsername;
@property (nonatomic, nullable) NSString *senderProfileName;
@property (nonatomic, nullable) NSString *accessibilityAuthorName;
@property (nonatomic) BOOL shouldHideFooter;
@property (nonatomic) BOOL isFirstInCluster;
@property (nonatomic) BOOL isLastInCluster;

- (ConversationViewCell *)dequeueCellForCollectionView:(UICollectionView *)collectionView
                                             indexPath:(NSIndexPath *)indexPath;

- (void)replaceInteraction:(TSInteraction *)interaction transaction:(SDSAnyReadTransaction *)transaction;

- (void)clearCachedLayoutState;

#pragma mark - Needs Update

@property (nonatomic, readonly) BOOL needsUpdate;

- (void)clearNeedsUpdate;

#pragma mark - Audio Playback

@property (nonatomic, weak) AudioMessageView *lastAudioMessageView;

@property (nonatomic, readonly) CGFloat audioDurationSeconds;
@property (nonatomic, readonly) CGFloat audioProgressSeconds;

#pragma mark - View State Caching

// These methods only apply to text & attachment messages.
@property (nonatomic, readonly) OWSMessageCellType messageCellType;
@property (nonatomic, readonly, nullable) DisplayableText *displayableBodyText;
@property (nonatomic, readonly, nullable) TSAttachmentStream *attachmentStream;
@property (nonatomic, readonly, nullable) TSAttachmentPointer *attachmentPointer;
@property (nonatomic, readonly, nullable) NSArray<ConversationMediaAlbumItem *> *mediaAlbumItems;

@property (nonatomic, readonly, nullable) DisplayableText *displayableQuotedText;
@property (nonatomic, readonly, nullable) NSString *quotedAttachmentMimetype;
@property (nonatomic, readonly, nullable) SignalServiceAddress *quotedAuthorAddress;

// We don't want to try to load the media for this item (if any)
// if a load has previously failed.
@property (nonatomic) BOOL didCellMediaFailToLoad;

@property (nonatomic, readonly, nullable) OWSQuotedReplyModel *quotedReply;

@property (nonatomic, readonly, nullable) ContactShareViewModel *contactShare;

@property (nonatomic, readonly, nullable) OWSLinkPreview *linkPreview;
@property (nonatomic, readonly, nullable) TSAttachment *linkPreviewAttachment;

@property (nonatomic, readonly, nullable) StickerInfo *stickerInfo;
@property (nonatomic, readonly, nullable) TSAttachmentStream *stickerAttachment;
@property (nonatomic, readonly) BOOL isFailedSticker;
@property (nonatomic, readonly) ViewOnceMessageState viewOnceMessageState;

@property (nonatomic, readonly, nullable) NSString *systemMessageText;

// NOTE: This property is only set for incoming messages, typing indicators, and thread details.
@property (nonatomic, readonly, nullable) NSString *authorConversationColorName;

// NOTE: This property is only set for conversation thread details
@property (nonatomic, readonly, nullable) NSArray<NSString *> *mutualGroupNames;

@property (nonatomic, readonly, nullable) InteractionReactionState *reactionState;

#pragma mark - MessageActions

@property (nonatomic, readonly) BOOL hasBodyTextActionContent;
@property (nonatomic, readonly) BOOL hasMediaActionContent;

- (void)shareMediaAction:(nullable id)sender;
- (void)copyTextAction;
- (void)deleteAction;

- (BOOL)canShareMedia;
@property (nonatomic, readonly) BOOL canForwardMessage;

// For view items that correspond to interactions, this is the interaction's unique id.
// For other view views (like the typing indicator), this is a unique, stable string.
- (NSString *)itemId;

- (nullable TSAttachmentStream *)firstValidAlbumAttachment;

- (BOOL)mediaAlbumHasFailedAttachment;
- (BOOL)mediaAlbumHasPendingMessageRequestAttachment;

@end

#pragma mark -

@interface ConversationInteractionViewItem
    : NSObject <ConversationViewItem, ConversationViewLayoutItem, OWSAudioPlayerDelegate>

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithInteraction:(TSInteraction *)interaction
                             thread:(TSThread *)thread
                        transaction:(SDSAnyReadTransaction *)transaction
                  conversationStyle:(ConversationStyle *)conversationStyle;
@end

NS_ASSUME_NONNULL_END
