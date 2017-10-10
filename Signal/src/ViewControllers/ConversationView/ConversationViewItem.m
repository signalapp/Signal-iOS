//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewItem.h"
#import "OWSAudioMessageView.h"
#import "OWSContactOffersCell.h"
#import "OWSIncomingMessageCell.h"
#import "OWSOutgoingMessageCell.h"
#import "OWSSystemMessageCell.h"
#import "OWSUnreadIndicatorCell.h"
#import "Signal-Swift.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <SignalServiceKit/TSInteraction.h>

NS_ASSUME_NONNULL_BEGIN

@interface ConversationViewItem ()

@property (nonatomic, nullable) NSValue *cachedCellSize;

#pragma mark - OWSAudioAttachmentPlayerDelegate

@property (nonatomic) AudioPlaybackState audioPlaybackState;
@property (nonatomic) CGFloat audioProgressSeconds;

#pragma mark - View State

@property (nonatomic) BOOL hasViewState;
@property (nonatomic) OWSMessageCellType messageCellType;
@property (nonatomic, nullable) NSString *textMessage;
@property (nonatomic, nullable) TSAttachmentStream *attachmentStream;
@property (nonatomic, nullable) TSAttachmentPointer *attachmentPointer;
@property (nonatomic) CGSize contentSize;

@end

#pragma mark -

@implementation ConversationViewItem

- (instancetype)initWithTSInteraction:(TSInteraction *)interaction
{
    self = [super init];

    if (!self) {
        return self;
    }

    _interaction = interaction;

    return self;
}

- (void)replaceInteraction:(TSInteraction *)interaction
{
    OWSAssert(interaction);

    _interaction = interaction;

    [self clearCachedLayoutState];
}

- (void)setShouldShowDate:(BOOL)shouldShowDate
{
    if (_shouldShowDate == shouldShowDate) {
        return;
    }

    _shouldShowDate = shouldShowDate;

    [self clearCachedLayoutState];
}

- (void)clearCachedLayoutState
{
    self.cachedCellSize = nil;
}

- (CGSize)cellSizeForViewWidth:(int)viewWidth maxMessageWidth:(int)maxMessageWidth
{
    OWSAssert([NSThread isMainThread]);

    CGSize cellSize = CGSizeZero;
    if (!self.cachedCellSize) {
        ConversationViewCell *_Nullable measurementCell = [self measurementCell];
        measurementCell.viewItem = self;
        cellSize = [measurementCell cellSizeForViewWidth:viewWidth maxMessageWidth:maxMessageWidth];
        self.cachedCellSize = [NSValue valueWithCGSize:cellSize];
        [measurementCell prepareForReuse];

        //        DDLogError(@"cellSizeForViewWidth: %@ %@", self.interaction.uniqueId, self.interaction.description);
        //        DDLogError(@"\t fresh cellSize: %@", NSStringFromCGSize(cellSize));
    } else {
        cellSize = [self.cachedCellSize CGSizeValue];
        //        DDLogError(@"cellSizeForViewWidth: %@ %@", self.interaction.uniqueId, self.interaction.description);
        //        DDLogError(@"\t cached cellSize: %@", NSStringFromCGSize(cellSize));
    }
    return cellSize;
}

- (ConversationViewLayoutAlignment)layoutAlignment
{
    switch (self.interaction.interactionType) {
        case OWSInteractionType_Unknown:
            return ConversationViewLayoutAlignment_Center;
        case OWSInteractionType_IncomingMessage:
            return ConversationViewLayoutAlignment_Incoming;
            break;
        case OWSInteractionType_OutgoingMessage:
            return ConversationViewLayoutAlignment_Outgoing;
            break;
        case OWSInteractionType_Error:
        case OWSInteractionType_Info:
        case OWSInteractionType_Call:
            return ConversationViewLayoutAlignment_Center;
        case OWSInteractionType_UnreadIndicator:
            return ConversationViewLayoutAlignment_FullWidth;
        case OWSInteractionType_Offer:
            return ConversationViewLayoutAlignment_Center;
    }
}

- (nullable ConversationViewCell *)measurementCell
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(self.interaction);

    // For performance reasons, we cache one instance of each kind of
    // cell and uses these cells for measurement.
    static NSMutableDictionary<NSNumber *, ConversationViewCell *> *measurementCellCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        measurementCellCache = [NSMutableDictionary new];
    });

    NSNumber *cellCacheKey = @(self.interaction.interactionType);
    ConversationViewCell *_Nullable measurementCell = measurementCellCache[cellCacheKey];
    if (!measurementCell) {
        switch (self.interaction.interactionType) {
            case OWSInteractionType_Unknown:
                OWSFail(@"%@ Unknown interaction type.", self.tag);
                return nil;
            case OWSInteractionType_IncomingMessage:
                measurementCell = [OWSIncomingMessageCell new];
                break;
            case OWSInteractionType_OutgoingMessage:
                measurementCell = [OWSOutgoingMessageCell new];
                break;
            case OWSInteractionType_Error:
            case OWSInteractionType_Info:
            case OWSInteractionType_Call:
                measurementCell = [OWSSystemMessageCell new];
                break;
            case OWSInteractionType_UnreadIndicator:
                measurementCell = [OWSUnreadIndicatorCell new];
                break;
            case OWSInteractionType_Offer:
                measurementCell = [OWSContactOffersCell new];
                break;
        }

        OWSAssert(measurementCell);
        measurementCellCache[cellCacheKey] = measurementCell;
    }

    return measurementCell;
}

- (ConversationViewCell *)dequeueCellForCollectionView:(UICollectionView *)collectionView
                                             indexPath:(NSIndexPath *)indexPath
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(collectionView);
    OWSAssert(indexPath);
    OWSAssert(self.interaction);

    switch (self.interaction.interactionType) {
        case OWSInteractionType_Unknown:
            OWSFail(@"%@ Unknown interaction type.", self.tag);
            return nil;
        case OWSInteractionType_IncomingMessage:
            return [collectionView dequeueReusableCellWithReuseIdentifier:[OWSIncomingMessageCell cellReuseIdentifier]
                                                             forIndexPath:indexPath];
        case OWSInteractionType_OutgoingMessage:
            return [collectionView dequeueReusableCellWithReuseIdentifier:[OWSOutgoingMessageCell cellReuseIdentifier]
                                                             forIndexPath:indexPath];
        case OWSInteractionType_Error:
        case OWSInteractionType_Info:
        case OWSInteractionType_Call:
            return [collectionView dequeueReusableCellWithReuseIdentifier:[OWSSystemMessageCell cellReuseIdentifier]
                                                             forIndexPath:indexPath];
        case OWSInteractionType_UnreadIndicator:
            return [collectionView dequeueReusableCellWithReuseIdentifier:[OWSUnreadIndicatorCell cellReuseIdentifier]
                                                             forIndexPath:indexPath];
        case OWSInteractionType_Offer:
            return [collectionView dequeueReusableCellWithReuseIdentifier:[OWSContactOffersCell cellReuseIdentifier]
                                                             forIndexPath:indexPath];
    }
}

#pragma mark - OWSAudioAttachmentPlayerDelegate

- (void)setAudioPlaybackState:(AudioPlaybackState)audioPlaybackState
{
    _audioPlaybackState = audioPlaybackState;

    [self.lastAudioMessageView updateContents];
}

- (void)setAudioProgress:(CGFloat)progress duration:(CGFloat)duration
{
    OWSAssert([NSThread isMainThread]);

    self.audioProgressSeconds = progress;
    if (duration > 0) {
        self.audioDurationSeconds = @(duration);
    }

    [self.lastAudioMessageView updateContents];
}

#pragma mark - View State

- (NSCache *)displayableTextCache
{
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        // Cache the results for up to 1,000 messages.
        cache.countLimit = 1000;
    });
    return cache;
}

- (NSString *)displayableTextForText:(NSString *)text interactionId:(NSString *)interactionId
{
    OWSAssert(text);
    OWSAssert(interactionId.length > 0);

    NSString *_Nullable displayableText = [[self displayableTextCache] objectForKey:interactionId];
    if (!displayableText) {
        // Only show up to 2kb of text.
        const NSUInteger kMaxTextDisplayLength = 2 * 1024;
        displayableText = [[DisplayableTextFilter new] displayableText:text];
        if (displayableText.length > kMaxTextDisplayLength) {
            // Trim whitespace before _AND_ after slicing the snipper from the string.
            NSString *snippet =
                [[[displayableText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                    substringWithRange:NSMakeRange(0, kMaxTextDisplayLength)]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            displayableText = [NSString stringWithFormat:NSLocalizedString(@"OVERSIZE_TEXT_DISPLAY_FORMAT",
                                                             @"A display format for oversize text messages."),
                                        snippet];
        }
        if (!displayableText) {
            displayableText = @"";
        }
        [[self displayableTextCache] setObject:displayableText forKey:interactionId];
    }
    return displayableText;
}

- (NSString *)displayableTextForAttachmentStream:(TSAttachmentStream *)attachmentStream
                                   interactionId:(NSString *)interactionId
{
    OWSAssert(attachmentStream);
    OWSAssert(interactionId.length > 0);

    NSString *_Nullable displayableText = [[self displayableTextCache] objectForKey:interactionId];
    if (displayableText) {
        return displayableText;
    }

    NSData *textData = [NSData dataWithContentsOfURL:attachmentStream.mediaURL];
    NSString *text = [[NSString alloc] initWithData:textData encoding:NSUTF8StringEncoding];
    return [self displayableTextForText:text interactionId:interactionId];
}

- (void)ensureViewState
{
    OWSAssert([self.interaction isKindOfClass:[TSMessage class]]);

    if (self.hasViewState) {
        return;
    }
    self.hasViewState = YES;

    TSMessage *interaction = (TSMessage *)self.interaction;
    if (interaction.body.length > 0) {
        self.messageCellType = OWSMessageCellType_TextMessage;
        // TODO: This can be expensive.  Should we cache it on the view item?
        self.textMessage = [self displayableTextForText:interaction.body interactionId:interaction.uniqueId];
        return;
    } else {
        NSString *_Nullable attachmentId = interaction.attachmentIds.firstObject;
        if (attachmentId.length > 0) {
            TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentId];
            if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                self.attachmentStream = (TSAttachmentStream *)attachment;

                if ([attachment.contentType isEqualToString:OWSMimeTypeOversizeTextMessage]) {
                    self.messageCellType = OWSMessageCellType_OversizeTextMessage;
                    // TODO: This can be expensive.  Should we cache it on the view item?
                    self.textMessage = [self displayableTextForAttachmentStream:self.attachmentStream
                                                                  interactionId:interaction.uniqueId];
                    return;
                } else if ([self.attachmentStream isAnimated] || [self.attachmentStream isImage] ||
                    [self.attachmentStream isVideo]) {
                    if ([self.attachmentStream isAnimated]) {
                        self.messageCellType = OWSMessageCellType_AnimatedImage;
                    } else if ([self.attachmentStream isImage]) {
                        self.messageCellType = OWSMessageCellType_StillImage;
                    } else if ([self.attachmentStream isVideo]) {
                        self.messageCellType = OWSMessageCellType_Video;
                    } else {
                        OWSFail(@"%@ unexpected attachment type.", self.tag);
                        self.messageCellType = OWSMessageCellType_GenericAttachment;
                        return;
                    }
                    self.contentSize = [self.attachmentStream imageSizeWithoutTransaction];
                    if (self.contentSize.width <= 0 || self.contentSize.height <= 0) {
                        self.messageCellType = OWSMessageCellType_GenericAttachment;
                    }
                    return;
                } else if ([self.attachmentStream isAudio]) {
                    self.messageCellType = OWSMessageCellType_Audio;
                    return;
                } else {
                    self.messageCellType = OWSMessageCellType_GenericAttachment;
                    return;
                }
            } else if ([attachment isKindOfClass:[TSAttachmentPointer class]]) {
                self.messageCellType = OWSMessageCellType_DownloadingAttachment;
                self.attachmentPointer = (TSAttachmentPointer *)attachment;
                return;
            }
        }
    }

    OWSFail(@"%@ Unknown cell type", self.tag);

    self.messageCellType = OWSMessageCellType_Unknown;
}

- (OWSMessageCellType)messageCellType
{
    OWSAssert([NSThread isMainThread]);

    [self ensureViewState];

    return _messageCellType;
}

- (nullable NSString *)textMessage
{
    OWSAssert([NSThread isMainThread]);

    [self ensureViewState];

    return _textMessage;
}

- (nullable TSAttachmentStream *)attachmentStream
{
    OWSAssert([NSThread isMainThread]);

    [self ensureViewState];

    return _attachmentStream;
}

- (nullable TSAttachmentPointer *)attachmentPointer
{
    OWSAssert([NSThread isMainThread]);

    [self ensureViewState];

    return _attachmentPointer;
}

- (CGSize)contentSize
{
    OWSAssert([NSThread isMainThread]);

    [self ensureViewState];

    return _contentSize;
}

#pragma mark - UIMenuController

- (NSArray<UIMenuItem *> *)menuControllerItems
{
    return @[
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SHARE_ACTION",
                                              @"Short name for edit menu item to share contents of media message.")
                                   action:self.shareActionSelector],
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_MESSAGE_METADATA_ACTION",
                                              @"Short name for edit menu item to show message metadata.")
                                   action:self.metadataActionSelector],
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_COPY_ACTION",
                                              @"Short name for edit menu item to copy contents of media message.")
                                   action:self.copyActionSelector],
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_DELETE_ACTION",
                                              @"Short name for edit menu item to delete contents of media message.")
                                   action:self.deleteActionSelector],
        // TODO: Do we want a save action?
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SAVE_ACTION",
                                              @"Short name for edit menu item to save contents of media message.")
                                   action:self.saveActionSelector],
    ];
}

- (SEL)copyActionSelector
{
    return NSSelectorFromString(@"copyAction:");
}

- (SEL)saveActionSelector
{
    return NSSelectorFromString(@"saveAction:");
}

- (SEL)shareActionSelector
{
    return NSSelectorFromString(@"shareAction:");
}

- (SEL)deleteActionSelector
{
    return NSSelectorFromString(@"deleteAction:");
}

- (SEL)metadataActionSelector
{
    return NSSelectorFromString(@"metadataAction:");
}

// We only use custom actions in UIMenuController.
- (BOOL)canPerformAction:(SEL)action
{
    if (action == self.copyActionSelector) {
        return [self hasActionContent];
    } else if (action == self.saveActionSelector) {
        return [self canSave];
    } else if (action == self.shareActionSelector) {
        return [self hasActionContent];
    } else if (action == self.deleteActionSelector) {
        return YES;
    } else if (action == self.metadataActionSelector) {
        return YES;
    } else {
        return NO;
    }
}

- (void)copyAction
{
    switch (self.messageCellType) {
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            [UIPasteboard.generalPasteboard setString:self.textMessage];
            break;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
        case OWSMessageCellType_GenericAttachment: {
            NSString *utiType = [MIMETypeUtil utiTypeForMIMEType:self.attachmentStream.contentType];
            if (!utiType) {
                OWSFail(@"%@ Unknown MIME type: %@", self.tag, self.attachmentStream.contentType);
                utiType = (NSString *)kUTTypeGIF;
            }
            NSData *data = [NSData dataWithContentsOfURL:[self.attachmentStream mediaURL]];
            if (!data) {
                OWSFail(@"%@ Could not load attachment data: %@", self.tag, [self.attachmentStream mediaURL]);
                return;
            }
            [UIPasteboard.generalPasteboard setData:data forPasteboardType:utiType];
            break;
        }
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFail(@"%@ Can't copy not-yet-downloaded attachment", self.tag);
            break;
        }
    }
}

- (void)shareAction
{
    switch (self.messageCellType) {
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            [AttachmentSharing showShareUIForText:self.textMessage];
            break;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
        case OWSMessageCellType_GenericAttachment:
            [AttachmentSharing showShareUIForAttachment:self.attachmentStream];
            break;
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFail(@"%@ Can't share not-yet-downloaded attachment", self.tag);
            break;
        }
    }
}

- (BOOL)canSave
{
    switch (self.messageCellType) {
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            return NO;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
            return YES;
        case OWSMessageCellType_Audio:
            return NO;
        case OWSMessageCellType_Video:
            return UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(self.attachmentStream.mediaURL.path);
        case OWSMessageCellType_GenericAttachment:
            return NO;
        case OWSMessageCellType_DownloadingAttachment: {
            return NO;
        }
    }
}

- (void)saveAction
{
    switch (self.messageCellType) {
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            OWSFail(@"%@ Cannot save text data.", [self tag]);
            break;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage: {
            NSData *data = [NSData dataWithContentsOfURL:[self.attachmentStream mediaURL]];
            if (!data) {
                OWSFail(@"%@ Could not load image data: %@", [self tag], [self.attachmentStream mediaURL]);
                return;
            }
            ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
            [library writeImageDataToSavedPhotosAlbum:data
                                             metadata:nil
                                      completionBlock:^(NSURL *assetURL, NSError *error) {
                                          if (error) {
                                              DDLogWarn(@"Error Saving image to photo album: %@", error);
                                          }
                                      }];
            break;
        }
        case OWSMessageCellType_Audio:
            OWSFail(@"%@ Cannot save media data.", [self tag]);
            break;
        case OWSMessageCellType_Video:
            if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(self.attachmentStream.mediaURL.path)) {
                UISaveVideoAtPathToSavedPhotosAlbum(self.attachmentStream.mediaURL.path, self, nil, nil);
            } else {
                OWSFail(@"%@ Could not save incompatible video data.", [self tag]);
            }
            break;
        case OWSMessageCellType_GenericAttachment:
            OWSFail(@"%@ Cannot save media data.", [self tag]);
            break;
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFail(@"%@ Can't save not-yet-downloaded attachment", self.tag);
            break;
        }
    }
}

- (void)deleteAction
{
    [self.interaction remove];
}

- (BOOL)hasActionContent
{
    switch (self.messageCellType) {
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            return self.textMessage.length > 0;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
        case OWSMessageCellType_GenericAttachment:
            return self.attachmentStream != nil;
        case OWSMessageCellType_DownloadingAttachment: {
            return NO;
        }
    }
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
