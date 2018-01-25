//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewItem.h"
#import "OWSAudioMessageView.h"
#import "OWSContactOffersCell.h"
#import "OWSMessageCell.h"
#import "OWSSystemMessageCell.h"
#import "OWSUnreadIndicatorCell.h"
#import "Signal-Swift.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <SignalMessaging/NSString+OWS.h>
#import <SignalServiceKit/TSInteraction.h>

NS_ASSUME_NONNULL_BEGIN

NSString *NSStringForOWSMessageCellType(OWSMessageCellType cellType)
{
    switch (cellType) {
        case OWSMessageCellType_TextMessage:
            return @"OWSMessageCellType_TextMessage";
        case OWSMessageCellType_OversizeTextMessage:
            return @"OWSMessageCellType_OversizeTextMessage";
        case OWSMessageCellType_StillImage:
            return @"OWSMessageCellType_StillImage";
        case OWSMessageCellType_AnimatedImage:
            return @"OWSMessageCellType_AnimatedImage";
        case OWSMessageCellType_Audio:
            return @"OWSMessageCellType_Audio";
        case OWSMessageCellType_Video:
            return @"OWSMessageCellType_Video";
        case OWSMessageCellType_GenericAttachment:
            return @"OWSMessageCellType_GenericAttachment";
        case OWSMessageCellType_DownloadingAttachment:
            return @"OWSMessageCellType_DownloadingAttachment";
        case OWSMessageCellType_Unknown:
            return @"OWSMessageCellType_Unknown";
    }
}

#pragma mark -

@interface ConversationViewItem ()

@property (nonatomic, nullable) NSValue *cachedCellSize;

#pragma mark - OWSAudioAttachmentPlayerDelegate

@property (nonatomic) AudioPlaybackState audioPlaybackState;
@property (nonatomic) CGFloat audioProgressSeconds;
@property (nonatomic) CGFloat audioDurationSeconds;

#pragma mark - View State

@property (nonatomic) BOOL hasViewState;
@property (nonatomic) OWSMessageCellType messageCellType;
@property (nonatomic, nullable) DisplayableText *displayableText;
@property (nonatomic, nullable) TSAttachmentStream *attachmentStream;
@property (nonatomic, nullable) TSAttachmentPointer *attachmentPointer;
@property (nonatomic) CGSize mediaSize;
@property (nonatomic) BOOL hasText;

@end

#pragma mark -

@implementation ConversationViewItem

- (instancetype)initWithInteraction:(TSInteraction *)interaction
                      isGroupThread:(BOOL)isGroupThread
                        transaction:(YapDatabaseReadTransaction *)transaction
{
    self = [super init];

    if (!self) {
        return self;
    }

    _interaction = interaction;
    _isGroupThread = isGroupThread;
    self.row = NSNotFound;
    self.previousRow = NSNotFound;

    [self ensureViewState:transaction];

    return self;
}

- (void)replaceInteraction:(TSInteraction *)interaction transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(interaction);

    _interaction = interaction;

    self.hasViewState = NO;
    self.messageCellType = OWSMessageCellType_Unknown;
    self.displayableText = nil;
    self.attachmentStream = nil;
    self.attachmentPointer = nil;
    self.mediaSize = CGSizeZero;

    [self clearCachedLayoutState];

    [self ensureViewState:transaction];
}

- (void)setShouldShowDate:(BOOL)shouldShowDate
{
    if (_shouldShowDate == shouldShowDate) {
        return;
    }

    _shouldShowDate = shouldShowDate;

    [self clearCachedLayoutState];
}

- (void)setShouldHideRecipientStatus:(BOOL)shouldHideRecipientStatus
{
    if (_shouldHideRecipientStatus == shouldHideRecipientStatus) {
        return;
    }

    _shouldHideRecipientStatus = shouldHideRecipientStatus;

    [self clearCachedLayoutState];
}

- (void)clearCachedLayoutState
{
    self.cachedCellSize = nil;
}

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth
{
    OWSAssertIsOnMainThread();

    if (!self.cachedCellSize) {
        ConversationViewCell *_Nullable measurementCell = [self measurementCell];
        measurementCell.viewItem = self;
        CGSize cellSize = [measurementCell cellSizeForViewWidth:viewWidth contentWidth:contentWidth];
        self.cachedCellSize = [NSValue valueWithCGSize:cellSize];
        [measurementCell prepareForReuse];
    }
    return [self.cachedCellSize CGSizeValue];
}

- (ConversationViewLayoutAlignment)layoutAlignment
{
    switch (self.interaction.interactionType) {
        case OWSInteractionType_Unknown:
            OWSFail(@"%@ Unknown interaction type: %@", self.logTag, self.interaction.debugDescription);
            return ConversationViewLayoutAlignment_Center;
        case OWSInteractionType_IncomingMessage:
            return ConversationViewLayoutAlignment_Incoming;
        case OWSInteractionType_OutgoingMessage:
            return ConversationViewLayoutAlignment_Outgoing;
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
    OWSAssertIsOnMainThread();
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
                OWSFail(@"%@ Unknown interaction type.", self.logTag);
                return nil;
            case OWSInteractionType_IncomingMessage:
            case OWSInteractionType_OutgoingMessage:
                measurementCell = [OWSMessageCell new];
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
    OWSAssertIsOnMainThread();
    OWSAssert(collectionView);
    OWSAssert(indexPath);
    OWSAssert(self.interaction);

    switch (self.interaction.interactionType) {
        case OWSInteractionType_Unknown:
            OWSFail(@"%@ Unknown interaction type.", self.logTag);
            return nil;
        case OWSInteractionType_IncomingMessage:
        case OWSInteractionType_OutgoingMessage:
            return [collectionView dequeueReusableCellWithReuseIdentifier:[OWSMessageCell cellReuseIdentifier]
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
    OWSAssertIsOnMainThread();

    self.audioProgressSeconds = progress;

    [self.lastAudioMessageView updateContents];
}

#pragma mark - View State

// TODO: Now that we're caching the displayable text on the view items,
//       I don't think we need this cache any more.
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

- (DisplayableText *)displayableTextForText:(NSString *)text interactionId:(NSString *)interactionId
{
    OWSAssert(text);
    OWSAssert(interactionId.length > 0);

    return [self displayableTextForInteractionId:interactionId
                                       textBlock:^{
                                           return text;
                                       }];
}

- (DisplayableText *)displayableTextForAttachmentStream:(TSAttachmentStream *)attachmentStream
                                          interactionId:(NSString *)interactionId
{
    OWSAssert(attachmentStream);
    OWSAssert(interactionId.length > 0);

    return [self displayableTextForInteractionId:interactionId
                                       textBlock:^{
                                           NSData *textData = [NSData dataWithContentsOfURL:attachmentStream.mediaURL];
                                           NSString *text =
                                               [[NSString alloc] initWithData:textData encoding:NSUTF8StringEncoding];
                                           return text;
                                       }];
}

- (DisplayableText *)displayableTextForInteractionId:(NSString *)interactionId
                                           textBlock:(NSString * (^_Nonnull)(void))textBlock
{
    OWSAssert(interactionId.length > 0);

    DisplayableText *_Nullable displayableText = [[self displayableTextCache] objectForKey:interactionId];
    if (!displayableText) {
        NSString *text = textBlock();

        // Only show up to N characters of text.
        const NSUInteger kMaxTextDisplayLength = 1024;
        NSString *_Nullable fullText = [DisplayableText displayableText:text];
        BOOL isTextTruncated = NO;
        if (!fullText) {
            fullText = @"";
        }
        NSString *_Nullable displayText = fullText;
        if (displayText.length > kMaxTextDisplayLength) {
            // Trim whitespace before _AND_ after slicing the snipper from the string.
            NSString *snippet = [[displayText substringWithRange:NSMakeRange(0, kMaxTextDisplayLength)] ows_stripped];
            displayText = [NSString stringWithFormat:NSLocalizedString(@"OVERSIZE_TEXT_DISPLAY_FORMAT",
                                                         @"A display format for oversize text messages."),
                                    snippet];
            isTextTruncated = YES;
        }
        if (!displayText) {
            displayText = @"";
        }

        displayableText =
            [[DisplayableText alloc] initWithFullText:fullText displayText:displayText isTextTruncated:isTextTruncated];

        [[self displayableTextCache] setObject:displayableText forKey:interactionId];
    }
    return displayableText;
}

- (nullable TSAttachment *)firstAttachmentIfAnyOfMessage:(TSMessage *)message
                                             transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(transaction);

    if (message.attachmentIds.count == 0) {
        return nil;
    }
    NSString *_Nullable attachmentId = message.attachmentIds.firstObject;
    if (attachmentId.length == 0) {
        return nil;
    }
    return [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
}

- (void)ensureViewState:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertIsOnMainThread();
    OWSAssert(transaction);
    OWSAssert(!self.hasViewState);

    if (![self.interaction isKindOfClass:[TSOutgoingMessage class]]
        && ![self.interaction isKindOfClass:[TSIncomingMessage class]]) {
        // Only text & attachment messages have "view state".
        return;
    }

    self.hasViewState = YES;

    TSMessage *message = (TSMessage *)self.interaction;
    TSAttachment *_Nullable attachment = [self firstAttachmentIfAnyOfMessage:message transaction:transaction];
    if (attachment) {
        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
            self.attachmentStream = (TSAttachmentStream *)attachment;

            if ([attachment.contentType isEqualToString:OWSMimeTypeOversizeTextMessage]) {
                self.messageCellType = OWSMessageCellType_OversizeTextMessage;
                self.displayableText =
                    [self displayableTextForAttachmentStream:self.attachmentStream interactionId:message.uniqueId];
                self.hasText = YES;
            } else if ([self.attachmentStream isAnimated] || [self.attachmentStream isImage] ||
                [self.attachmentStream isVideo]) {
                if ([self.attachmentStream isAnimated]) {
                    self.messageCellType = OWSMessageCellType_AnimatedImage;
                } else if ([self.attachmentStream isImage]) {
                    self.messageCellType = OWSMessageCellType_StillImage;
                } else if ([self.attachmentStream isVideo]) {
                    self.messageCellType = OWSMessageCellType_Video;
                } else {
                    OWSFail(@"%@ unexpected attachment type.", self.logTag);
                    self.messageCellType = OWSMessageCellType_GenericAttachment;
                    return;
                }
                self.mediaSize = [self.attachmentStream imageSize];
                if (self.mediaSize.width <= 0 || self.mediaSize.height <= 0) {
                    self.messageCellType = OWSMessageCellType_GenericAttachment;
                }
            } else if ([self.attachmentStream isAudio]) {
                CGFloat audioDurationSeconds = [self.attachmentStream audioDurationSeconds];
                if (audioDurationSeconds > 0) {
                    self.audioDurationSeconds = audioDurationSeconds;
                    self.messageCellType = OWSMessageCellType_Audio;
                } else {
                    self.messageCellType = OWSMessageCellType_GenericAttachment;
                }
            } else {
                self.messageCellType = OWSMessageCellType_GenericAttachment;
            }
        } else if ([attachment isKindOfClass:[TSAttachmentPointer class]]) {
            self.messageCellType = OWSMessageCellType_DownloadingAttachment;
            self.attachmentPointer = (TSAttachmentPointer *)attachment;
        } else {
            OWSFail(@"%@ Unknown attachment type", self.logTag);
        }
    }

    if (message.body.length > 0) {
        self.hasText = YES;
        // If we haven't already assigned an attachment type at this point, message.body isn't a caption,
        // it's a stand-alone text message.
        if (self.messageCellType == OWSMessageCellType_Unknown) {
            OWSAssert(message.attachmentIds.count == 0);
            self.messageCellType = OWSMessageCellType_TextMessage;
        }
        self.displayableText = [self displayableTextForText:message.body interactionId:message.uniqueId];
            OWSAssert(self.displayableText);
    }

    if (self.messageCellType == OWSMessageCellType_Unknown) {
        // Messages of unknown type (including messages with missing attachments)
        // are rendered like empty text messages, but without any interactivity.
        DDLogWarn(@"%@ Treating unknown message as empty text message: %@", self.logTag, message.description);
        self.messageCellType = OWSMessageCellType_TextMessage;
        self.hasText = YES;
        self.displayableText = [[DisplayableText alloc] initWithFullText:@"" displayText:@"" isTextTruncated:NO];
    }
}

- (OWSMessageCellType)messageCellType
{
    OWSAssertIsOnMainThread();

    return _messageCellType;
}

- (nullable DisplayableText *)displayableText
{
    OWSAssertIsOnMainThread();
    OWSAssert(self.hasViewState);

    OWSAssert(_displayableText);
    OWSAssert(_displayableText.displayText);
    OWSAssert(_displayableText.fullText);

    return _displayableText;
}

- (nullable TSAttachmentStream *)attachmentStream
{
    OWSAssertIsOnMainThread();
    OWSAssert(self.hasViewState);

    return _attachmentStream;
}

- (nullable TSAttachmentPointer *)attachmentPointer
{
    OWSAssertIsOnMainThread();
    OWSAssert(self.hasViewState);

    return _attachmentPointer;
}

- (CGSize)mediaSize
{
    OWSAssertIsOnMainThread();
    OWSAssert(self.hasViewState);

    return _mediaSize;
}

#pragma mark - UIMenuController

- (NSArray<UIMenuItem *> *)textMenuControllerItems
{
    return @[
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_COPY_ACTION",
                                              @"Short name for edit menu item to copy contents of media message.")
                                   action:self.copyTextActionSelector],
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SHARE_ACTION",
                                              @"Short name for edit menu item to share contents of media message.")
                                   action:self.shareTextActionSelector],
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_MESSAGE_METADATA_ACTION",
                                              @"Short name for edit menu item to show message metadata.")
                                   action:self.metadataActionSelector],
        // FIXME: when deleting a caption, users will be surprised that it also deletes the attachment.
        // We either need to implement a way to remove the caption separate from the attachment
        // or make a design change which clarifies that the whole message is getting deleted.
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_DELETE_ACTION",
                                                            @"Short name for edit menu item to delete contents of media message.")
                                                            action:self.deleteActionSelector]
    ];
}
- (NSArray<UIMenuItem *> *)mediaMenuControllerItems
{
    return @[
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SHARE_ACTION",
                                              @"Short name for edit menu item to share contents of media message.")
                                   action:self.shareMediaActionSelector],
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_MESSAGE_METADATA_ACTION",
                                              @"Short name for edit menu item to show message metadata.")
                                   action:self.metadataActionSelector],
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_COPY_ACTION",
                                              @"Short name for edit menu item to copy contents of media message.")
                                   action:self.copyMediaActionSelector],
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_DELETE_ACTION",
                                              @"Short name for edit menu item to delete contents of media message.")
                                   action:self.deleteActionSelector],
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SAVE_ACTION",
                                              @"Short name for edit menu item to save contents of media message.")
                                   action:self.saveMediaActionSelector],
    ];
}

- (SEL)copyTextActionSelector
{
    return NSSelectorFromString(@"copyTextAction:");
}

- (SEL)copyMediaActionSelector
{
    return NSSelectorFromString(@"copyMediaAction:");
}

- (SEL)saveMediaActionSelector
{
    return NSSelectorFromString(@"saveMediaAction:");
}

- (SEL)shareTextActionSelector
{
    return NSSelectorFromString(@"shareTextAction:");
}

- (SEL)shareMediaActionSelector
{
    return NSSelectorFromString(@"shareMediaAction:");
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
    if (action == self.copyTextActionSelector) {
        return [self hasTextActionContent];
    } else if (action == self.copyMediaActionSelector) {
        return [self hasMediaActionContent];
    } else if (action == self.saveMediaActionSelector) {
        return [self canSaveMedia];
    } else if (action == self.shareTextActionSelector) {
        return [self hasTextActionContent];
    } else if (action == self.shareMediaActionSelector) {
        return [self hasMediaActionContent];
    } else if (action == self.deleteActionSelector) {
        return YES;
    } else if (action == self.metadataActionSelector) {
        return YES;
    } else {
        return NO;
    }
}

- (void)copyTextAction
{
    switch (self.messageCellType) {
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
        case OWSMessageCellType_GenericAttachment: {
            OWSAssert(self.displayableText);
            [UIPasteboard.generalPasteboard setString:self.displayableText.fullText];
            break;
        }
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFail(@"%@ Can't copy not-yet-downloaded attachment", self.logTag);
            break;
        }
        case OWSMessageCellType_Unknown: {
            OWSFail(@"%@ No text to copy", self.logTag);
            break;
        }
    }
}

- (void)copyMediaAction
{
    switch (self.messageCellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage: {
            OWSFail(@"%@ No media to copy", self.logTag);
            break;
        }
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
        case OWSMessageCellType_GenericAttachment: {
            NSString *utiType = [MIMETypeUtil utiTypeForMIMEType:self.attachmentStream.contentType];
            if (!utiType) {
                OWSFail(@"%@ Unknown MIME type: %@", self.logTag, self.attachmentStream.contentType);
                utiType = (NSString *)kUTTypeGIF;
            }
            NSData *data = [NSData dataWithContentsOfURL:[self.attachmentStream mediaURL]];
            if (!data) {
                OWSFail(@"%@ Could not load attachment data: %@", self.logTag, [self.attachmentStream mediaURL]);
                return;
            }
            [UIPasteboard.generalPasteboard setData:data forPasteboardType:utiType];
            break;
        }
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFail(@"%@ Can't copy not-yet-downloaded attachment", self.logTag);
            break;
        }
    }
}

- (void)shareTextAction
{
    switch (self.messageCellType) {
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
        case OWSMessageCellType_GenericAttachment: {
            OWSAssert(self.displayableText);
            [AttachmentSharing showShareUIForText:self.displayableText.fullText];
            break;
        }
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFail(@"%@ Can't share not-yet-downloaded attachment", self.logTag);
            break;
        }
        case OWSMessageCellType_Unknown: {
            OWSFail(@"%@ No text to share", self.logTag)
        }
    }
}

- (void)shareMediaAction
{
    switch (self.messageCellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            OWSFail(@"No media to share.");
            break;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
        case OWSMessageCellType_GenericAttachment:
            [AttachmentSharing showShareUIForAttachment:self.attachmentStream];
            break;
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFail(@"%@ Can't share not-yet-downloaded attachment", self.logTag);
            break;
        }
    }
}

- (BOOL)canSaveMedia
{
    switch (self.messageCellType) {
        case OWSMessageCellType_Unknown:
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

- (void)saveMediaAction
{
    switch (self.messageCellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            OWSFail(@"%@ Cannot save text data.", self.logTag);
            break;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage: {
            NSData *data = [NSData dataWithContentsOfURL:[self.attachmentStream mediaURL]];
            if (!data) {
                OWSFail(@"%@ Could not load image data: %@", self.logTag, [self.attachmentStream mediaURL]);
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
            OWSFail(@"%@ Cannot save media data.", self.logTag);
            break;
        case OWSMessageCellType_Video:
            if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(self.attachmentStream.mediaURL.path)) {
                UISaveVideoAtPathToSavedPhotosAlbum(self.attachmentStream.mediaURL.path, self, nil, nil);
            } else {
                OWSFail(@"%@ Could not save incompatible video data.", self.logTag);
            }
            break;
        case OWSMessageCellType_GenericAttachment:
            OWSFail(@"%@ Cannot save media data.", self.logTag);
            break;
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFail(@"%@ Can't save not-yet-downloaded attachment", self.logTag);
            break;
        }
    }
}

- (void)deleteAction
{
    [self.interaction remove];
}

- (BOOL)hasTextActionContent
{
    return self.hasText && self.displayableText.fullText.length > 0;
}

- (BOOL)hasMediaActionContent
{
    switch (self.messageCellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            return NO;
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

@end

NS_ASSUME_NONNULL_END
