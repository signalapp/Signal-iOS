//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewItem.h"
#import "OWSAudioMessageView.h"
#import "OWSContactOffersCell.h"
#import "OWSMessageCell.h"
#import "OWSMessageHeaderView.h"
#import "OWSSystemMessageCell.h"
#import "Signal-Swift.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <SignalMessaging/NSString+OWS.h>
#import <SignalMessaging/OWSUnreadIndicator.h>
#import <SignalServiceKit/NSData+Image.h>
#import <SignalServiceKit/OWSContact.h>
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
        case OWSMessageCellType_ContactShare:
            return @"OWSMessageCellType_ContactShare";
    }
}

#pragma mark -

@interface ConversationInteractionViewItem ()

@property (nonatomic, nullable) NSValue *cachedCellSize;

#pragma mark - OWSAudioPlayerDelegate

@property (nonatomic) AudioPlaybackState audioPlaybackState;
@property (nonatomic) CGFloat audioProgressSeconds;
@property (nonatomic) CGFloat audioDurationSeconds;

#pragma mark - View State

@property (nonatomic) BOOL hasViewState;
@property (nonatomic) OWSMessageCellType messageCellType;
@property (nonatomic, nullable) DisplayableText *displayableBodyText;
@property (nonatomic, nullable) DisplayableText *displayableQuotedText;
@property (nonatomic, nullable) OWSQuotedReplyModel *quotedReply;
@property (nonatomic, nullable) TSAttachmentStream *attachmentStream;
@property (nonatomic, nullable) TSAttachmentPointer *attachmentPointer;
@property (nonatomic, nullable) ContactShareViewModel *contactShare;
@property (nonatomic) CGSize mediaSize;
@property (nonatomic, nullable) NSString *systemMessageText;
@property (nonatomic, nullable) TSThread *incomingMessageAuthorThread;
@property (nonatomic, nullable) NSString *authorConversationColorName;
@property (nonatomic, nullable) ConversationStyle *conversationStyle;

@end

#pragma mark -

@implementation ConversationInteractionViewItem

@synthesize shouldShowDate = _shouldShowDate;
@synthesize shouldShowSenderAvatar = _shouldShowSenderAvatar;
@synthesize unreadIndicator = _unreadIndicator;
@synthesize didCellMediaFailToLoad = _didCellMediaFailToLoad;
@synthesize interaction = _interaction;
@synthesize isFirstInCluster = _isFirstInCluster;
@synthesize isGroupThread = _isGroupThread;
@synthesize isLastInCluster = _isLastInCluster;
@synthesize lastAudioMessageView = _lastAudioMessageView;
@synthesize senderName = _senderName;
@synthesize shouldHideFooter = _shouldHideFooter;

- (instancetype)initWithInteraction:(TSInteraction *)interaction
                      isGroupThread:(BOOL)isGroupThread
                        transaction:(YapDatabaseReadTransaction *)transaction
                  conversationStyle:(ConversationStyle *)conversationStyle
{
    OWSAssertDebug(interaction);
    OWSAssertDebug(transaction);
    OWSAssertDebug(conversationStyle);

    self = [super init];

    if (!self) {
        return self;
    }

    _interaction = interaction;
    _isGroupThread = isGroupThread;
    _conversationStyle = conversationStyle;

    [self updateAuthorConversationColorNameWithTransaction:transaction];

    [self ensureViewState:transaction];

    return self;
}

- (void)replaceInteraction:(TSInteraction *)interaction transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(interaction);

    _interaction = interaction;

    self.hasViewState = NO;
    self.messageCellType = OWSMessageCellType_Unknown;
    self.displayableBodyText = nil;
    self.attachmentStream = nil;
    self.attachmentPointer = nil;
    self.mediaSize = CGSizeZero;
    self.displayableQuotedText = nil;
    self.quotedReply = nil;
    self.systemMessageText = nil;

    [self updateAuthorConversationColorNameWithTransaction:transaction];

    [self clearCachedLayoutState];

    [self ensureViewState:transaction];
}

- (void)updateAuthorConversationColorNameWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    if (self.interaction.interactionType != OWSInteractionType_IncomingMessage) {
        _authorConversationColorName = nil;
        return;
    }

    TSIncomingMessage *incomingMessage = (TSIncomingMessage *)self.interaction;
    _authorConversationColorName =
        [TSContactThread conversationColorNameForRecipientId:incomingMessage.authorId transaction:transaction];
}

- (BOOL)hasBodyText
{
    return _displayableBodyText != nil;
}

- (BOOL)hasQuotedText
{
    return _displayableQuotedText != nil;
}

- (BOOL)hasQuotedAttachment
{
    return self.quotedAttachmentMimetype.length > 0;
}

- (BOOL)isQuotedReply
{
    return self.hasQuotedAttachment || self.hasQuotedText;
}

- (BOOL)isExpiringMessage
{
    if (self.interaction.interactionType != OWSInteractionType_OutgoingMessage
        && self.interaction.interactionType != OWSInteractionType_IncomingMessage) {
        return NO;
    }

    TSMessage *message = (TSMessage *)self.interaction;
    return message.isExpiringMessage;
}

- (BOOL)hasCellHeader
{
    return self.shouldShowDate || self.unreadIndicator;
}

- (void)setShouldShowDate:(BOOL)shouldShowDate
{
    if (_shouldShowDate == shouldShowDate) {
        return;
    }

    _shouldShowDate = shouldShowDate;

    [self clearCachedLayoutState];
}

- (void)setShouldShowSenderAvatar:(BOOL)shouldShowSenderAvatar
{
    if (_shouldShowSenderAvatar == shouldShowSenderAvatar) {
        return;
    }

    _shouldShowSenderAvatar = shouldShowSenderAvatar;

    [self clearCachedLayoutState];
}

- (void)setSenderName:(nullable NSAttributedString *)senderName
{
    if ([NSObject isNullableObject:senderName equalTo:_senderName]) {
        return;
    }

    _senderName = senderName;

    [self clearCachedLayoutState];
}

- (void)setShouldHideFooter:(BOOL)shouldHideFooter
{
    if (_shouldHideFooter == shouldHideFooter) {
        return;
    }

    _shouldHideFooter = shouldHideFooter;

    [self clearCachedLayoutState];
}

- (void)setUnreadIndicator:(nullable OWSUnreadIndicator *)unreadIndicator
{
    if ([NSObject isNullableObject:_unreadIndicator equalTo:unreadIndicator]) {
        return;
    }

    _unreadIndicator = unreadIndicator;

    [self clearCachedLayoutState];
}

- (void)clearCachedLayoutState
{
    self.cachedCellSize = nil;
}

- (CGSize)cellSize
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.conversationStyle);

    if (!self.cachedCellSize) {
        ConversationViewCell *_Nullable measurementCell = [self measurementCell];
        measurementCell.viewItem = self;
        measurementCell.conversationStyle = self.conversationStyle;
        CGSize cellSize = [measurementCell cellSize];
        self.cachedCellSize = [NSValue valueWithCGSize:cellSize];
        [measurementCell prepareForReuse];
    }
    return [self.cachedCellSize CGSizeValue];
}

- (nullable ConversationViewCell *)measurementCell
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.interaction);

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
                OWSFailDebug(@"Unknown interaction type.");
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
            case OWSInteractionType_Offer:
                measurementCell = [OWSContactOffersCell new];
                break;
        }

        OWSAssertDebug(measurementCell);
        measurementCellCache[cellCacheKey] = measurementCell;
    }

    return measurementCell;
}

- (CGFloat)vSpacingWithPreviousLayoutItem:(id<ConversationViewItem>)previousLayoutItem
{
    OWSAssertDebug(previousLayoutItem);

    if (self.hasCellHeader) {
        return OWSMessageHeaderViewDateHeaderVMargin;
    }

    // "Bubble Collapse".  Adjacent messages with the same author should be close together.
    if (self.interaction.interactionType == OWSInteractionType_IncomingMessage
        && previousLayoutItem.interaction.interactionType == OWSInteractionType_IncomingMessage) {
        TSIncomingMessage *incomingMessage = (TSIncomingMessage *)self.interaction;
        TSIncomingMessage *previousIncomingMessage = (TSIncomingMessage *)previousLayoutItem.interaction;
        if ([incomingMessage.authorId isEqualToString:previousIncomingMessage.authorId]) {
            return 2.f;
        }
    } else if (self.interaction.interactionType == OWSInteractionType_OutgoingMessage
        && previousLayoutItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        return 2.f;
    }

    return 12.f;
}

- (ConversationViewCell *)dequeueCellForCollectionView:(UICollectionView *)collectionView
                                             indexPath:(NSIndexPath *)indexPath
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(collectionView);
    OWSAssertDebug(indexPath);
    OWSAssertDebug(self.interaction);

    switch (self.interaction.interactionType) {
        case OWSInteractionType_Unknown:
            OWSFailDebug(@"Unknown interaction type.");
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
        case OWSInteractionType_Offer:
            return [collectionView dequeueReusableCellWithReuseIdentifier:[OWSContactOffersCell cellReuseIdentifier]
                                                             forIndexPath:indexPath];
    }
}

#pragma mark - OWSAudioPlayerDelegate

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

#pragma mark - Displayable Text

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

- (DisplayableText *)displayableBodyTextForText:(NSString *)text interactionId:(NSString *)interactionId
{
    OWSAssertDebug(text);
    OWSAssertDebug(interactionId.length > 0);

    NSString *displayableTextCacheKey = [@"body-" stringByAppendingString:interactionId];

    return [self displayableTextForCacheKey:displayableTextCacheKey
                                  textBlock:^{
                                      return text;
                                  }];
}

- (DisplayableText *)displayableBodyTextForOversizeTextAttachment:(TSAttachmentStream *)attachmentStream
                                                    interactionId:(NSString *)interactionId
{
    OWSAssertDebug(attachmentStream);
    OWSAssertDebug(interactionId.length > 0);

    NSString *displayableTextCacheKey = [@"oversize-body-" stringByAppendingString:interactionId];

    return [self displayableTextForCacheKey:displayableTextCacheKey
                                  textBlock:^{
                                      NSData *textData =
                                          [NSData dataWithContentsOfURL:attachmentStream.originalMediaURL];
                                      NSString *text =
                                          [[NSString alloc] initWithData:textData encoding:NSUTF8StringEncoding];
                                      return text;
                                  }];
}

- (DisplayableText *)displayableQuotedTextForText:(NSString *)text interactionId:(NSString *)interactionId
{
    OWSAssertDebug(text);
    OWSAssertDebug(interactionId.length > 0);

    NSString *displayableTextCacheKey = [@"quoted-" stringByAppendingString:interactionId];

    return [self displayableTextForCacheKey:displayableTextCacheKey
                                  textBlock:^{
                                      return text;
                                  }];
}

- (DisplayableText *)displayableTextForCacheKey:(NSString *)displayableTextCacheKey
                                      textBlock:(NSString * (^_Nonnull)(void))textBlock
{
    OWSAssertDebug(displayableTextCacheKey.length > 0);

    DisplayableText *_Nullable displayableText = [[self displayableTextCache] objectForKey:displayableTextCacheKey];
    if (!displayableText) {
        NSString *text = textBlock();
        displayableText = [DisplayableText displayableText:text];
        [[self displayableTextCache] setObject:displayableText forKey:displayableTextCacheKey];
    }
    return displayableText;
}

#pragma mark - View State

- (nullable TSAttachment *)firstAttachmentIfAnyOfMessage:(TSMessage *)message
                                             transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

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
    OWSAssertDebug(transaction);
    OWSAssertDebug(!self.hasViewState);

    switch (self.interaction.interactionType) {
        case OWSInteractionType_Unknown:
        case OWSInteractionType_Offer:
            return;
        case OWSInteractionType_Error:
        case OWSInteractionType_Info:
        case OWSInteractionType_Call:
            self.systemMessageText = [self systemMessageTextWithTransaction:transaction];
            OWSAssertDebug(self.systemMessageText.length > 0);
            return;
        case OWSInteractionType_IncomingMessage:
        case OWSInteractionType_OutgoingMessage:
            break;
        default:
            OWSFailDebug(@"Unknown interaction type.");
            return;
    }

    OWSAssertDebug([self.interaction isKindOfClass:[TSOutgoingMessage class]] ||
        [self.interaction isKindOfClass:[TSIncomingMessage class]]);

    self.hasViewState = YES;

    TSMessage *message = (TSMessage *)self.interaction;
    if (message.contactShare) {
        self.contactShare =
            [[ContactShareViewModel alloc] initWithContactShareRecord:message.contactShare transaction:transaction];
        self.messageCellType = OWSMessageCellType_ContactShare;
        return;
    }
    TSAttachment *_Nullable attachment = [self firstAttachmentIfAnyOfMessage:message transaction:transaction];
    if (attachment) {
        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
            self.attachmentStream = (TSAttachmentStream *)attachment;

            if ([attachment.contentType isEqualToString:OWSMimeTypeOversizeTextMessage]) {
                self.messageCellType = OWSMessageCellType_OversizeTextMessage;
                self.displayableBodyText = [self displayableBodyTextForOversizeTextAttachment:self.attachmentStream
                                                                                interactionId:message.uniqueId];
            } else if ([self.attachmentStream isAnimated] || [self.attachmentStream isImage] ||
                [self.attachmentStream isVideo]) {
                if ([self.attachmentStream isAnimated]) {
                    if (![self.attachmentStream isValidImage]) {
                        OWSLogWarn(@"Treating invalid image as generic attachment.");
                        self.messageCellType = OWSMessageCellType_GenericAttachment;
                        return;
                    }

                    self.messageCellType = OWSMessageCellType_AnimatedImage;
                } else if ([self.attachmentStream isImage]) {
                    if (![self.attachmentStream isValidImage]) {
                        OWSLogWarn(@"Treating invalid image as generic attachment.");
                        self.messageCellType = OWSMessageCellType_GenericAttachment;
                        return;
                    }

                    self.messageCellType = OWSMessageCellType_StillImage;
                } else if ([self.attachmentStream isVideo]) {
                    if (![self.attachmentStream isValidVideo]) {
                        OWSLogWarn(@"Treating invalid video as generic attachment.");
                        self.messageCellType = OWSMessageCellType_GenericAttachment;
                        return;
                    }

                    self.messageCellType = OWSMessageCellType_Video;
                } else {
                    OWSFailDebug(@"unexpected attachment type.");
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
            OWSFailDebug(@"Unknown attachment type");
        }
    }

    // Ignore message body for oversize text attachments.
    if (message.body.length > 0) {
        if (self.hasBodyText) {
            OWSFailDebug(@"oversize text message has unexpected caption.");
        }

        // If we haven't already assigned an attachment type at this point, message.body isn't a caption,
        // it's a stand-alone text message.
        if (self.messageCellType == OWSMessageCellType_Unknown) {
            OWSAssertDebug(message.attachmentIds.count == 0);
            self.messageCellType = OWSMessageCellType_TextMessage;
        }
        self.displayableBodyText = [self displayableBodyTextForText:message.body interactionId:message.uniqueId];
        OWSAssertDebug(self.displayableBodyText);
    }

    if (self.messageCellType == OWSMessageCellType_Unknown) {
        // Messages of unknown type (including messages with missing attachments)
        // are rendered like empty text messages, but without any interactivity.
        OWSLogWarn(@"Treating unknown message as empty text message: %@ %llu", message.class, message.timestamp);
        self.messageCellType = OWSMessageCellType_TextMessage;
        self.displayableBodyText = [[DisplayableText alloc] initWithFullText:@"" displayText:@"" isTextTruncated:NO];
    }

    if (message.quotedMessage) {
        self.quotedReply =
            [OWSQuotedReplyModel quotedReplyWithQuotedMessage:message.quotedMessage transaction:transaction];

        if (self.quotedReply.body.length > 0) {
            self.displayableQuotedText =
                [self displayableQuotedTextForText:self.quotedReply.body interactionId:message.uniqueId];
        }
    }
}

- (NSString *)systemMessageTextWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    switch (self.interaction.interactionType) {
        case OWSInteractionType_Error: {
            TSErrorMessage *errorMessage = (TSErrorMessage *)self.interaction;
            return [errorMessage previewTextWithTransaction:transaction];
        }
        case OWSInteractionType_Info: {
            TSInfoMessage *infoMessage = (TSInfoMessage *)self.interaction;
            if ([infoMessage isKindOfClass:[OWSVerificationStateChangeMessage class]]) {
                OWSVerificationStateChangeMessage *verificationMessage
                    = (OWSVerificationStateChangeMessage *)infoMessage;
                BOOL isVerified = verificationMessage.verificationState == OWSVerificationStateVerified;
                NSString *displayName =
                    [Environment.shared.contactsManager displayNameForPhoneIdentifier:verificationMessage.recipientId];
                NSString *titleFormat = (isVerified
                        ? (verificationMessage.isLocalChange
                                  ? NSLocalizedString(@"VERIFICATION_STATE_CHANGE_FORMAT_VERIFIED_LOCAL",
                                        @"Format for info message indicating that the verification state was verified "
                                        @"on "
                                        @"this device. Embeds {{user's name or phone number}}.")
                                  : NSLocalizedString(@"VERIFICATION_STATE_CHANGE_FORMAT_VERIFIED_OTHER_DEVICE",
                                        @"Format for info message indicating that the verification state was verified "
                                        @"on "
                                        @"another device. Embeds {{user's name or phone number}}."))
                        : (verificationMessage.isLocalChange
                                  ? NSLocalizedString(@"VERIFICATION_STATE_CHANGE_FORMAT_NOT_VERIFIED_LOCAL",
                                        @"Format for info message indicating that the verification state was "
                                        @"unverified on "
                                        @"this device. Embeds {{user's name or phone number}}.")
                                  : NSLocalizedString(@"VERIFICATION_STATE_CHANGE_FORMAT_NOT_VERIFIED_OTHER_DEVICE",
                                        @"Format for info message indicating that the verification state was "
                                        @"unverified on "
                                        @"another device. Embeds {{user's name or phone number}}.")));
                return [NSString stringWithFormat:titleFormat, displayName];
            } else {
                return [infoMessage previewTextWithTransaction:transaction];
            }
        }
        case OWSInteractionType_Call: {
            TSCall *call = (TSCall *)self.interaction;
            return [call previewTextWithTransaction:transaction];
        }
        default:
            OWSFailDebug(@"not a system message.");
            return nil;
    }
}

- (nullable NSString *)quotedAttachmentMimetype
{
    return self.quotedReply.contentType;
}

- (nullable NSString *)quotedRecipientId
{
    return self.quotedReply.authorId;
}

- (OWSMessageCellType)messageCellType
{
    OWSAssertIsOnMainThread();

    return _messageCellType;
}

- (nullable DisplayableText *)displayableBodyText
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.hasViewState);

    OWSAssertDebug(_displayableBodyText);
    OWSAssertDebug(_displayableBodyText.displayText);
    OWSAssertDebug(_displayableBodyText.fullText);

    return _displayableBodyText;
}

- (nullable TSAttachmentStream *)attachmentStream
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.hasViewState);

    return _attachmentStream;
}

- (nullable TSAttachmentPointer *)attachmentPointer
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.hasViewState);

    return _attachmentPointer;
}

- (CGSize)mediaSize
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.hasViewState);

    return _mediaSize;
}

- (nullable DisplayableText *)displayableQuotedText
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.hasViewState);

    OWSAssertDebug(_displayableQuotedText);
    OWSAssertDebug(_displayableQuotedText.displayText);
    OWSAssertDebug(_displayableQuotedText.fullText);

    return _displayableQuotedText;
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
            OWSAssertDebug(self.displayableBodyText);
            [UIPasteboard.generalPasteboard setString:self.displayableBodyText.fullText];
            break;
        }
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFailDebug(@"Can't copy not-yet-downloaded attachment");
            break;
        }
        case OWSMessageCellType_Unknown: {
            OWSFailDebug(@"No text to copy");
            break;
        }
        case OWSMessageCellType_ContactShare: {
            // TODO: Implement copy contact.
            OWSFailDebug(@"Not implemented yet");
            break;
        }
    }
}

- (void)copyMediaAction
{
    switch (self.messageCellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
        case OWSMessageCellType_ContactShare: {
            OWSFailDebug(@"No media to copy");
            break;
        }
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
        case OWSMessageCellType_GenericAttachment: {
            NSString *utiType = [MIMETypeUtil utiTypeForMIMEType:self.attachmentStream.contentType];
            if (!utiType) {
                OWSFailDebug(@"Unknown MIME type: %@", self.attachmentStream.contentType);
                utiType = (NSString *)kUTTypeGIF;
            }
            NSData *data = [NSData dataWithContentsOfURL:[self.attachmentStream originalMediaURL]];
            if (!data) {
                OWSFailDebug(@"Could not load attachment data");
                return;
            }
            [UIPasteboard.generalPasteboard setData:data forPasteboardType:utiType];
            break;
        }
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFailDebug(@"Can't copy not-yet-downloaded attachment");
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
            OWSAssertDebug(self.displayableBodyText);
            [AttachmentSharing showShareUIForText:self.displayableBodyText.fullText];
            break;
        }
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFailDebug(@"Can't share not-yet-downloaded attachment");
            break;
        }
        case OWSMessageCellType_Unknown: {
            OWSFailDebug(@"No text to share");
            break;
        }
        case OWSMessageCellType_ContactShare: {
            OWSFailDebug(@"share contact not implemented.");
            break;
        }
    }
}

- (void)shareMediaAction
{
    switch (self.messageCellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
        case OWSMessageCellType_ContactShare:
            OWSFailDebug(@"No media to share.");
            break;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
        case OWSMessageCellType_GenericAttachment:
            [AttachmentSharing showShareUIForAttachment:self.attachmentStream];
            break;
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFailDebug(@"Can't share not-yet-downloaded attachment");
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
        case OWSMessageCellType_ContactShare:
            return NO;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
            return YES;
        case OWSMessageCellType_Audio:
            return NO;
        case OWSMessageCellType_Video:
            return UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(self.attachmentStream.originalFilePath);
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
        case OWSMessageCellType_ContactShare:
            OWSFailDebug(@"Cannot save text data.");
            break;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage: {
            NSData *data = [NSData dataWithContentsOfURL:[self.attachmentStream originalMediaURL]];
            if (!data) {
                OWSFailDebug(@"Could not load image data");
                return;
            }
            ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
            [library writeImageDataToSavedPhotosAlbum:data
                                             metadata:nil
                                      completionBlock:^(NSURL *assetURL, NSError *error) {
                                          if (error) {
                                              OWSLogWarn(@"Error Saving image to photo album: %@", error);
                                          }
                                      }];
            break;
        }
        case OWSMessageCellType_Audio:
            OWSFailDebug(@"Cannot save media data.");
            break;
        case OWSMessageCellType_Video:
            if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(self.attachmentStream.originalFilePath)) {
                UISaveVideoAtPathToSavedPhotosAlbum(self.attachmentStream.originalFilePath, self, nil, nil);
            } else {
                OWSFailDebug(@"Could not save incompatible video data.");
            }
            break;
        case OWSMessageCellType_GenericAttachment:
            OWSFailDebug(@"Cannot save media data.");
            break;
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFailDebug(@"Can't save not-yet-downloaded attachment");
            break;
        }
    }
}

- (void)deleteAction
{
    [self.interaction remove];
}

- (BOOL)hasBodyTextActionContent
{
    return self.hasBodyText && self.displayableBodyText.fullText.length > 0;
}

- (BOOL)hasMediaActionContent
{
    switch (self.messageCellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
        case OWSMessageCellType_ContactShare:
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
