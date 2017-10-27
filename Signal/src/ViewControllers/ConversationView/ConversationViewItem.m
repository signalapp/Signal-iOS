//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewItem.h"
#import "NSString+OWS.h"
#import "OWSAudioMessageView.h"
#import "OWSContactOffersCell.h"
#import "OWSMessageCell.h"
#import "OWSSystemMessageCell.h"
#import "OWSUnreadIndicatorCell.h"
#import "Signal-Swift.h"
#import <AssetsLibrary/AssetsLibrary.h>
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
    }
}

#pragma mark -

@interface ConversationViewItem ()

@property (nonatomic, nullable) NSValue *cachedCellSize;

#pragma mark - OWSAudioAttachmentPlayerDelegate

@property (nonatomic) AudioPlaybackState audioPlaybackState;
@property (nonatomic) CGFloat audioProgressSeconds;

#pragma mark - View State

@property (nonatomic) BOOL hasViewState;
@property (nonatomic) OWSMessageCellType messageCellType;
@property (nonatomic, nullable) DisplayableText *displayableText;
@property (nonatomic, nullable) TSAttachmentStream *attachmentStream;
@property (nonatomic, nullable) TSAttachmentPointer *attachmentPointer;
@property (nonatomic) CGSize contentSize;

@end

#pragma mark -

@implementation ConversationViewItem

- (instancetype)initWithTSInteraction:(TSInteraction *)interaction isGroupThread:(BOOL)isGroupThread
{
    self = [super init];

    if (!self) {
        return self;
    }

    _interaction = interaction;
    _isGroupThread = isGroupThread;
    self.row = NSNotFound;
    self.previousRow = NSNotFound;

    return self;
}

- (void)replaceInteraction:(TSInteraction *)interaction
{
    OWSAssert(interaction);

    _interaction = interaction;

    self.hasViewState = NO;
    self.messageCellType = OWSMessageCellType_Unknown;
    self.displayableText = nil;
    self.attachmentStream = nil;
    self.attachmentPointer = nil;
    self.contentSize = CGSizeZero;

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
    OWSAssert([NSThread isMainThread]);

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
            OWSFail(@"%@ Unknown interaction type: %@", self.tag, self.interaction.debugDescription);
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
    OWSAssert([NSThread isMainThread]);
    OWSAssert(collectionView);
    OWSAssert(indexPath);
    OWSAssert(self.interaction);

    switch (self.interaction.interactionType) {
        case OWSInteractionType_Unknown:
            OWSFail(@"%@ Unknown interaction type.", self.tag);
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
    OWSAssert([NSThread isMainThread]);

    self.audioProgressSeconds = progress;
    if (duration > 0) {
        self.audioDurationSeconds = @(duration);
    }

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
                                           textBlock:(NSString * (^_Nonnull)())textBlock
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

        NSNumber *_Nullable jumbomojiCount = [DisplayableText jumbomojiCountTo:fullText];

        displayableText = [[DisplayableText alloc] initWithFullText:fullText
                                                        displayText:displayText
                                                    isTextTruncated:isTextTruncated
                                                     jumbomojiCount:jumbomojiCount];

        [[self displayableTextCache] setObject:displayableText forKey:interactionId];
    }
    return displayableText;
}

- (nullable TSAttachment *)firstAttachmentIfAnyOfMessage:(TSMessage *)message
{
    if (message.attachmentIds.count == 0) {
        return nil;
    }
    NSString *_Nullable attachmentId = message.attachmentIds.firstObject;
    if (attachmentId.length == 0) {
        return nil;
    }
    return [TSAttachment fetchObjectWithUniqueID:attachmentId];
}

- (void)ensureViewState
{
    OWSAssert([self.interaction isKindOfClass:[TSOutgoingMessage class]] ||
        [self.interaction isKindOfClass:[TSIncomingMessage class]]);

    if (self.hasViewState) {
        return;
    }
    self.hasViewState = YES;

    TSMessage *message = (TSMessage *)self.interaction;
    TSAttachment *_Nullable attachment = [self firstAttachmentIfAnyOfMessage:message];
    if (attachment) {
        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
            self.attachmentStream = (TSAttachmentStream *)attachment;

            if ([attachment.contentType isEqualToString:OWSMimeTypeOversizeTextMessage]) {
                self.messageCellType = OWSMessageCellType_OversizeTextMessage;
                self.displayableText =
                    [self displayableTextForAttachmentStream:self.attachmentStream interactionId:message.uniqueId];
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
        } else {
            OWSFail(@"%@ Unknown attachment type", self.tag);
        }
    } else if (message.body != nil) {
        self.messageCellType = OWSMessageCellType_TextMessage;
        self.displayableText = [self displayableTextForText:message.body interactionId:message.uniqueId];
            OWSAssert(self.displayableText);
        return;
    } else {
        OWSFail(@"%@ Message has neither attachment nor body", self.tag);
    }

    DDLogVerbose(@"%@ message: %@", self.tag, message.description);
    OWSFail(@"%@ Unknown cell type", self.tag);

    self.messageCellType = OWSMessageCellType_Unknown;
}

- (OWSMessageCellType)messageCellType
{
    OWSAssert([NSThread isMainThread]);

    [self ensureViewState];

    return _messageCellType;
}

- (nullable DisplayableText *)displayableText
{
    OWSAssert([NSThread isMainThread]);

    [self ensureViewState];

    OWSAssert(_displayableText);
    OWSAssert(_displayableText.displayText);
    OWSAssert(_displayableText.fullText);

    return _displayableText;
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
            OWSAssert(self.displayableText);
            [UIPasteboard.generalPasteboard setString:self.displayableText.fullText];
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
            OWSAssert(self.displayableText);
            [AttachmentSharing showShareUIForText:self.displayableText.fullText];
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
            OWSAssert(self.displayableText);
            return self.displayableText.fullText.length > 0;
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
