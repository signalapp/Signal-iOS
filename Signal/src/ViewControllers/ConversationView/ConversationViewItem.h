//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewLayout.h"
#import "OWSAudioPlayer.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OWSMessageCellType) {
    OWSMessageCellType_Unknown,
    OWSMessageCellType_TextOnlyMessage,
    OWSMessageCellType_Audio,
    OWSMessageCellType_GenericAttachment,
    OWSMessageCellType_ContactShare,
    OWSMessageCellType_MediaMessage,
    OWSMessageCellType_OversizeTextDownloading,
    OWSMessageCellType_StickerMessage,
    OWSMessageCellType_PerMessageExpiration,
};

NSString *NSStringForOWSMessageCellType(OWSMessageCellType cellType);

#pragma mark -

typedef NS_ENUM(NSUInteger, PerMessageExpirationState) {
    PerMessageExpirationState_Unknown = 0,
    PerMessageExpirationState_IncomingExpired,
    PerMessageExpirationState_IncomingDownloading,
    PerMessageExpirationState_IncomingFailed,
    PerMessageExpirationState_IncomingAvailable,
    PerMessageExpirationState_IncomingInvalidContent,
    PerMessageExpirationState_OutgoingSending,
    PerMessageExpirationState_OutgoingFailed,
    PerMessageExpirationState_OutgoingSent,
};

@class ContactShareViewModel;
@class ConversationViewCell;
@class DisplayableText;
@class OWSAudioMessageView;
@class OWSLinkPreview;
@class OWSQuotedReplyModel;
@class OWSUnreadIndicator;
@class SDSAnyReadTransaction;
@class StickerInfo;
@class TSAttachment;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSInteraction;
@class TSThread;
@class YapDatabaseReadTransaction;

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

@property (nonatomic, readonly) BOOL isGroupThread;

@property (nonatomic, readonly) BOOL hasBodyText;

@property (nonatomic, readonly) BOOL isQuotedReply;
@property (nonatomic, readonly) BOOL hasQuotedAttachment;
@property (nonatomic, readonly) BOOL hasQuotedText;
@property (nonatomic, readonly) BOOL hasCellHeader;

@property (nonatomic, readonly) BOOL hasPerConversationExpiration;
@property (nonatomic, readonly) BOOL hasPerMessageExpiration;

@property (nonatomic) BOOL shouldShowDate;
@property (nonatomic) BOOL shouldShowSenderAvatar;
@property (nonatomic, nullable) NSAttributedString *senderName;
@property (nonatomic) BOOL shouldHideFooter;
@property (nonatomic) BOOL isFirstInCluster;
@property (nonatomic) BOOL isLastInCluster;

@property (nonatomic, nullable) OWSUnreadIndicator *unreadIndicator;

- (ConversationViewCell *)dequeueCellForCollectionView:(UICollectionView *)collectionView
                                             indexPath:(NSIndexPath *)indexPath;

- (void)replaceInteraction:(TSInteraction *)interaction transaction:(SDSAnyReadTransaction *)transaction;

- (void)clearCachedLayoutState;

@property (nonatomic, readonly) BOOL hasCachedLayoutState;

#pragma mark - Audio Playback

@property (nonatomic, weak) OWSAudioMessageView *lastAudioMessageView;

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
@property (nonatomic, readonly, nullable) NSString *quotedRecipientId;

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
@property (nonatomic, readonly) PerMessageExpirationState perMessageExpirationState;

@property (nonatomic, readonly, nullable) NSString *systemMessageText;

// NOTE: This property is only set for incoming messages.
@property (nonatomic, readonly, nullable) NSString *authorConversationColorName;

#pragma mark - MessageActions

@property (nonatomic, readonly) BOOL hasBodyTextActionContent;
@property (nonatomic, readonly) BOOL hasMediaActionContent;

- (void)copyMediaAction;
- (void)copyTextAction;
- (void)shareMediaAction;
- (void)saveMediaAction;
- (void)deleteAction;

- (BOOL)canCopyMedia;
- (BOOL)canSaveMedia;

// For view items that correspond to interactions, this is the interaction's unique id.
// For other view views (like the typing indicator), this is a unique, stable string.
- (NSString *)itemId;

- (nullable TSAttachmentStream *)firstValidAlbumAttachment;

- (BOOL)mediaAlbumHasFailedAttachment;

@end

#pragma mark -

@interface ConversationInteractionViewItem
    : NSObject <ConversationViewItem, ConversationViewLayoutItem, OWSAudioPlayerDelegate>

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithInteraction:(TSInteraction *)interaction
                      isGroupThread:(BOOL)isGroupThread
                        transaction:(SDSAnyReadTransaction *)transaction
                  conversationStyle:(ConversationStyle *)conversationStyle;

@end

NS_ASSUME_NONNULL_END
