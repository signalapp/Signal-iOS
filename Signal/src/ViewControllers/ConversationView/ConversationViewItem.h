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

NSString *NSStringForOWSMessageCellType(OWSMessageCellType cellType);

#pragma mark -

@interface DisplayableText : NSObject

@property (nonatomic) NSString *fullText;

@property (nonatomic) NSString *displayText;

@property (nonatomic) BOOL isTextTruncated;

@end

#pragma mark -

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

@property (nonatomic, readonly) BOOL isGroupThread;

@property (nonatomic) BOOL shouldShowDate;
@property (nonatomic) BOOL shouldHideRecipientStatus;

@property (nonatomic) NSInteger row;
// During updates, we sometimes need the previous row index
// (before this update) of this item.
//
// If NSNotFound, this view item was just created in the
// previous update.
@property (nonatomic) NSInteger previousRow;

//@property (nonatomic, weak) ConversationViewCell *lastCell;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithTSInteraction:(TSInteraction *)interaction isGroupThread:(BOOL)isGroupThread;

- (ConversationViewCell *)dequeueCellForCollectionView:(UICollectionView *)collectionView
                                             indexPath:(NSIndexPath *)indexPath;

- (void)replaceInteraction:(TSInteraction *)interaction;

- (void)clearCachedLayoutState;

#pragma mark - Audio Playback

@property (nonatomic, weak) OWSAudioMessageView *lastAudioMessageView;

@property (nonatomic, nullable) NSNumber *audioDurationSeconds;

- (CGFloat)audioProgressSeconds;

#pragma mark - View State Caching

// These methods only apply to text & attachment messages.
- (OWSMessageCellType)messageCellType;
- (nullable DisplayableText *)displayableText;
- (nullable TSAttachmentStream *)attachmentStream;
- (nullable TSAttachmentPointer *)attachmentPointer;
- (CGSize)contentSize;

// We don't want to try to load the media for this item (if any)
// if a load has previously failed.
@property (nonatomic) BOOL didCellMediaFailToLoad;

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
