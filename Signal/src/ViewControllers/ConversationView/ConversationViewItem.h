//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewLayout.h"
#import "OWSAudioPlayer.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OWSMessageCellType) {
    OWSMessageCellType_Unknown,
    OWSMessageCellType_TextMessage,
    OWSMessageCellType_OversizeTextMessage,
    OWSMessageCellType_StillImage,
    OWSMessageCellType_AnimatedImage,
    OWSMessageCellType_Audio,
    OWSMessageCellType_Video,
    OWSMessageCellType_GenericAttachment,
    OWSMessageCellType_DownloadingAttachment,
    OWSMessageCellType_ContactShare,
};

NSString *NSStringForOWSMessageCellType(OWSMessageCellType cellType);

#pragma mark -

@class ContactShareViewModel;
@class ConversationViewCell;
@class DisplayableText;
@class OWSAudioMessageView;
@class OWSQuotedReplyModel;
@class OWSUnreadIndicator;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSInteraction;
@class TSThread;
@class YapDatabaseReadTransaction;

// This is a ViewModel for cells in the conversation view.
//
// The lifetime of this class is the lifetime of that cell
// in the load window of the conversation view.
//
// Critically, this class implements ConversationViewLayoutItem
// and does caching of the cell's size.
@protocol ConversationViewItem <NSObject, ConversationViewLayoutItem, OWSAudioPlayerDelegate>

@property (nonatomic, readonly) TSInteraction *interaction;

@property (nonatomic, readonly, nullable) OWSQuotedReplyModel *quotedReply;

@property (nonatomic, readonly) BOOL isGroupThread;

@property (nonatomic, readonly) BOOL hasBodyText;

@property (nonatomic, readonly) BOOL isQuotedReply;
@property (nonatomic, readonly) BOOL hasQuotedAttachment;
@property (nonatomic, readonly) BOOL hasQuotedText;
@property (nonatomic, readonly) BOOL hasCellHeader;

@property (nonatomic, readonly) BOOL isExpiringMessage;

@property (nonatomic) BOOL shouldShowDate;
@property (nonatomic) BOOL shouldShowSenderAvatar;
@property (nonatomic, nullable) NSAttributedString *senderName;
@property (nonatomic) BOOL shouldHideFooter;
@property (nonatomic) BOOL isFirstInCluster;
@property (nonatomic) BOOL isLastInCluster;

@property (nonatomic, nullable) OWSUnreadIndicator *unreadIndicator;

- (ConversationViewCell *)dequeueCellForCollectionView:(UICollectionView *)collectionView
                                             indexPath:(NSIndexPath *)indexPath;

- (void)replaceInteraction:(TSInteraction *)interaction transaction:(YapDatabaseReadTransaction *)transaction;

- (void)clearCachedLayoutState;

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
@property (nonatomic, readonly) CGSize mediaSize;

@property (nonatomic, readonly, nullable) DisplayableText *displayableQuotedText;
@property (nonatomic, readonly, nullable) NSString *quotedAttachmentMimetype;
@property (nonatomic, readonly, nullable) NSString *quotedRecipientId;

// We don't want to try to load the media for this item (if any)
// if a load has previously failed.
@property (nonatomic) BOOL didCellMediaFailToLoad;

@property (nonatomic, readonly, nullable) ContactShareViewModel *contactShare;

@property (nonatomic, readonly, nullable) NSString *systemMessageText;

// NOTE: This property is only set for incoming messages.
@property (nonatomic, readonly, nullable) NSString *authorConversationColorName;

#pragma mark - MessageActions

@property (nonatomic, readonly) BOOL hasBodyTextActionContent;
@property (nonatomic, readonly) BOOL hasMediaActionContent;

- (void)copyMediaAction;
- (void)copyTextAction;
- (void)shareMediaAction;
- (void)shareTextAction;
- (void)saveMediaAction;
- (void)deleteAction;

- (BOOL)canSaveMedia;

@end

@interface ConversationInteractionViewItem
    : NSObject <ConversationViewItem, ConversationViewLayoutItem, OWSAudioPlayerDelegate>

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithInteraction:(TSInteraction *)interaction
                      isGroupThread:(BOOL)isGroupThread
                        transaction:(YapDatabaseReadTransaction *)transaction
                  conversationStyle:(ConversationStyle *)conversationStyle;

@end

NS_ASSUME_NONNULL_END
