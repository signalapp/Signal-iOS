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
};

NSString *NSStringForOWSMessageCellType(OWSMessageCellType cellType);

#pragma mark -

@class ConversationViewCell;
@class DisplayableText;
@class OWSAudioMessageView;
@class OWSQuotedReplyModel;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSInteraction;
@class YapDatabaseReadTransaction;

// This is a ViewModel for cells in the conversation view.
//
// The lifetime of this class is the lifetime of that cell
// in the load window of the conversation view.
//
// Critically, this class implements ConversationViewLayoutItem
// and does caching of the cell's size.
@interface ConversationViewItem : NSObject <ConversationViewLayoutItem, OWSAudioPlayerDelegate>

@property (nonatomic, readonly) TSInteraction *interaction;
@property (nonatomic, readonly, nullable) OWSQuotedReplyModel *quotedReply;

@property (nonatomic, readonly) BOOL isGroupThread;

@property (nonatomic, readonly) BOOL hasBodyText;

// TODO drive these off of the quotedReply?
@property (nonatomic, readonly) BOOL isQuotedReply;
@property (nonatomic, readonly) BOOL hasQuotedAttachment;
@property (nonatomic, readonly) BOOL hasQuotedText;

@property (nonatomic) BOOL shouldShowDate;
@property (nonatomic) BOOL shouldHideRecipientStatus;
@property (nonatomic) BOOL shouldHideBubbleTail;

@property (nonatomic) NSInteger row;
// During updates, we sometimes need the previous row index
// (before this update) of this item.
//
// If NSNotFound, this view item was just created in the
// previous update.
@property (nonatomic) NSInteger previousRow;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithInteraction:(TSInteraction *)interaction
                      isGroupThread:(BOOL)isGroupThread
                        transaction:(YapDatabaseReadTransaction *)transaction;

- (ConversationViewCell *)dequeueCellForCollectionView:(UICollectionView *)collectionView
                                             indexPath:(NSIndexPath *)indexPath;

- (void)replaceInteraction:(TSInteraction *)interaction transaction:(YapDatabaseReadTransaction *)transaction;

- (void)clearCachedLayoutState;

#pragma mark - Audio Playback

@property (nonatomic, weak) OWSAudioMessageView *lastAudioMessageView;

@property (nonatomic, readonly) CGFloat audioDurationSeconds;

- (CGFloat)audioProgressSeconds;

#pragma mark - View State Caching

// These methods only apply to text & attachment messages.
- (OWSMessageCellType)messageCellType;
- (nullable DisplayableText *)displayableBodyText;
- (nullable TSAttachmentStream *)attachmentStream;
- (nullable TSAttachmentPointer *)attachmentPointer;
- (CGSize)mediaSize;

- (nullable DisplayableText *)displayableQuotedText;
- (nullable NSString *)quotedAttachmentMimetype;
- (nullable NSString *)quotedRecipientId;

// We don't want to try to load the media for this item (if any)
// if a load has previously failed.
@property (nonatomic) BOOL didCellMediaFailToLoad;

#pragma mark - UIMenuController

- (NSArray<UIMenuItem *> *)textMenuControllerItems;
- (NSArray<UIMenuItem *> *)mediaMenuControllerItems;

- (BOOL)canPerformAction:(SEL)action;
- (void)copyMediaAction;
- (void)copyTextAction;
- (void)shareMediaAction;
- (void)shareTextAction;
- (void)saveMediaAction;
- (void)deleteAction;
- (SEL)metadataActionSelector;

@end

NS_ASSUME_NONNULL_END
