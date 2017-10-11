//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewLayout.h"
#import "OWSAudioAttachmentPlayer.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OWSMessageCellType) {
    OWSMessageCellType_TextMessage,
    OWSMessageCellType_OversizeTextMessage,
    OWSMessageCellType_StillImage,
    OWSMessageCellType_AnimatedImage,
    OWSMessageCellType_Audio,
    OWSMessageCellType_Video,
    OWSMessageCellType_GenericAttachment,
    OWSMessageCellType_DownloadingAttachment,
    // Treat invalid messages as empty text messages.
    OWSMessageCellType_Unknown = OWSMessageCellType_TextMessage,
};

@class ConversationViewCell;
@class OWSAudioMessageView;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSInteraction;

// This is a ViewModel for cells in the conversation view.
//
// The lifetime of this class is the lifetime of that cell
// in the load window of the conversation view.
//
// Critically, this class implements ConversationViewLayoutItem
// and does caching of the cell's size.
@interface ConversationViewItem : NSObject <ConversationViewLayoutItem, OWSAudioAttachmentPlayerDelegate>

@property (nonatomic, readonly) TSInteraction *interaction;

@property (nonatomic) BOOL shouldShowDate;

//@property (nonatomic, weak) ConversationViewCell *lastCell;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithTSInteraction:(TSInteraction *)interaction;

- (ConversationViewCell *)dequeueCellForCollectionView:(UICollectionView *)collectionView
                                             indexPath:(NSIndexPath *)indexPath;

- (void)replaceInteraction:(TSInteraction *)interaction;

- (void)clearCachedLayoutState;

#pragma mark - Audio Playback

@property (nonatomic, weak) OWSAudioMessageView *lastAudioMessageView;

@property (nonatomic, nullable) NSNumber *audioDurationSeconds;

- (CGFloat)audioProgressSeconds;

#pragma mark - Expiration

// TODO:
//@property (nonatomic, readonly) BOOL isExpiringMessage;
//@property (nonatomic, readonly) BOOL shouldStartExpireTimer;
//@property (nonatomic, readonly) double expiresAtSeconds;
//@property (nonatomic, readonly) uint32_t expiresInSeconds;

#pragma mark - View State Caching

// These methods only apply to text & attachment messages.
- (OWSMessageCellType)messageCellType;
- (nullable NSString *)textMessage;
- (nullable TSAttachmentStream *)attachmentStream;
- (nullable TSAttachmentPointer *)attachmentPointer;
- (CGSize)contentSize;

// TODO:
//// Cells will request that this adapter clear its cached media views,
//// but the adapter should only honor requests from the last cell to
//// use its views.
//- (void)setLastPresentingCell:(nullable id)cell;
//- (void)clearCachedMediaViewsIfLastPresentingCell:(id)cell;

#pragma mark - UIMenuController

- (NSArray<UIMenuItem *> *)menuControllerItems;
- (BOOL)canPerformAction:(SEL)action;
- (void)copyAction;
- (void)shareAction;
- (void)saveAction;
- (void)deleteAction;
- (SEL)metadataActionSelector;

@end

NS_ASSUME_NONNULL_END
