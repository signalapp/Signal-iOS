//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSMessageAdapter.h"
#import "AttachmentSharing.h"
#import "OWSCall.h"
#import "OWSContactOffersInteraction.h"
#import "Signal-Swift.h"
#import "TSAttachmentPointer.h"
#import "TSAttachmentStream.h"
#import "TSCall.h"
#import "TSContactThread.h"
#import "TSContentAdapters.h"
#import "TSErrorMessage.h"
#import "TSGenericAttachmentAdapter.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSOutgoingMessage.h"
#import "TSUnreadIndicatorInteraction.h"
#import <MobileCoreServices/MobileCoreServices.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSMessageAdapter ()

// ---

@property (nonatomic, retain) TSContactThread *thread;

// OR for groups

@property (nonatomic, copy) NSString *senderId;
@property (nonatomic, copy) NSString *senderDisplayName;

// for InfoMessages

@property TSInfoMessageType infoMessageType;

// for ErrorMessages

@property TSErrorMessageType errorMessageType;

// for outgoing Messages only

@property NSInteger outgoingMessageStatus;

// for MediaMessages

@property JSQMediaItem<OWSMessageEditing> *mediaItem;


// -- Redeclaring properties from OWSMessageData protocol to synthesize variables
@property (nonatomic) TSMessageAdapterType messageType;
@property (nonatomic) BOOL isExpiringMessage;
@property (nonatomic) BOOL shouldStartExpireTimer;
@property (nonatomic) double expiresAtSeconds;
@property (nonatomic) uint32_t expiresInSeconds;

@property (nonatomic) NSString *messageBody;

@property (nonatomic) NSString *interactionUniqueId;

@end

#pragma mark -

@implementation TSMessageAdapter

- (instancetype)initWithInteraction:(TSInteraction *)interaction
{
    self = [super init];
    if (!self) {
        return self;
    }

    _interaction = interaction;

    self.interactionUniqueId = interaction.uniqueId;

    if ([interaction isKindOfClass:[TSMessage class]]) {
        TSMessage *message = (TSMessage *)interaction;
        _isExpiringMessage = message.isExpiringMessage;
        _expiresAtSeconds = message.expiresAt / 1000.0;
        _expiresInSeconds = message.expiresInSeconds;
        _shouldStartExpireTimer = message.shouldStartExpireTimer;
    } else {
        _isExpiringMessage = NO;
    }

    return self;
}

+ (NSCache *)displayableTextCache
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

+ (id<OWSMessageData>)messageViewDataWithInteraction:(TSInteraction *)interaction inThread:(TSThread *)thread contactsManager:(id<ContactsManagerProtocol>)contactsManager
{
    TSMessageAdapter *adapter = [[TSMessageAdapter alloc] initWithInteraction:interaction];

    if ([thread isKindOfClass:[TSContactThread class]]) {
        adapter.thread = (TSContactThread *)thread;
        if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
            NSString *contactId       = ((TSContactThread *)thread).contactIdentifier;
            adapter.senderId          = contactId;
            adapter.senderDisplayName = [contactsManager displayNameForPhoneIdentifier:contactId];
            adapter.messageType       = TSIncomingMessageAdapter;
        } else {
            adapter.senderId          = ME_MESSAGE_IDENTIFIER;
            adapter.senderDisplayName = NSLocalizedString(@"ME_STRING", @"");
            adapter.messageType       = TSOutgoingMessageAdapter;
        }
    } else if ([thread isKindOfClass:[TSGroupThread class]]) {
        if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
            TSIncomingMessage *message = (TSIncomingMessage *)interaction;
            adapter.senderId           = message.authorId;
            adapter.senderDisplayName = [contactsManager displayNameForPhoneIdentifier:message.authorId];
            adapter.messageType        = TSIncomingMessageAdapter;
        } else {
            adapter.senderId          = ME_MESSAGE_IDENTIFIER;
            adapter.senderDisplayName = NSLocalizedString(@"ME_STRING", @"");
            adapter.messageType       = TSOutgoingMessageAdapter;
        }
    } else {
        OWSFail(@"%@ Unknown thread type: %@", self.tag, [thread class]);
    }

    if ([interaction isKindOfClass:[TSIncomingMessage class]] ||
        [interaction isKindOfClass:[TSOutgoingMessage class]]) {
        TSMessage *message  = (TSMessage *)interaction;
        adapter.messageBody = [[DisplayableTextFilter new] displayableText:message.body];

        if ([message hasAttachments]) {
            for (NSString *attachmentID in message.attachmentIds) {
                TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentID];

                BOOL isIncomingAttachment = [interaction isKindOfClass:[TSIncomingMessage class]];

                if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                    TSAttachmentStream *stream = (TSAttachmentStream *)attachment;
                    if ([attachment.contentType isEqualToString:OWSMimeTypeOversizeTextMessage]) {
                        NSString *displayableText = [[self displayableTextCache] objectForKey:interaction.uniqueId];
                        if (!displayableText) {
                            NSData *textData = [NSData dataWithContentsOfURL:stream.mediaURL];
                            NSString *fullText = [[NSString alloc] initWithData:textData encoding:NSUTF8StringEncoding];
                            // Only show up to 2kb of text.
                            const NSUInteger kMaxTextDisplayLength = 2 * 1024;
                            displayableText = [[DisplayableTextFilter new] displayableText:fullText];
                            if (displayableText.length > kMaxTextDisplayLength) {
                                // Trim whitespace before _AND_ after slicing the snipper from the string.
                                NSString *snippet = [[[displayableText
                                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                                    substringWithRange:NSMakeRange(0, kMaxTextDisplayLength)]
                                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                                displayableText =
                                    [NSString stringWithFormat:NSLocalizedString(@"OVERSIZE_TEXT_DISPLAY_FORMAT",
                                                                   @"A display format for oversize text messages."),
                                              snippet];
                            }
                            if (!displayableText) {
                                displayableText = @"";
                            }
                            [[self displayableTextCache] setObject:displayableText forKey:interaction.uniqueId];
                        }
                        adapter.messageBody = displayableText;
                    } else if ([stream isAnimated]) {
                        adapter.mediaItem =
                            [[TSAnimatedAdapter alloc] initWithAttachment:stream incoming:isIncomingAttachment];
                        adapter.mediaItem.appliesMediaViewMaskAsOutgoing = !isIncomingAttachment;
                        break;
                    } else if ([stream isImage]) {
                        adapter.mediaItem =
                            [[TSPhotoAdapter alloc] initWithAttachment:stream incoming:isIncomingAttachment];
                        adapter.mediaItem.appliesMediaViewMaskAsOutgoing = !isIncomingAttachment;
                        break;
                    } else if ([stream isVideo] || [stream isAudio]) {
                        adapter.mediaItem = [[TSVideoAttachmentAdapter alloc]
                            initWithAttachment:stream
                                      incoming:[interaction isKindOfClass:[TSIncomingMessage class]]];
                        adapter.mediaItem.appliesMediaViewMaskAsOutgoing = !isIncomingAttachment;
                        break;
                    } else {
                        adapter.mediaItem = [[TSGenericAttachmentAdapter alloc]
                            initWithAttachment:stream
                                      incoming:[interaction isKindOfClass:[TSIncomingMessage class]]];
                        adapter.mediaItem.appliesMediaViewMaskAsOutgoing = !isIncomingAttachment;
                        break;
                    }
                } else if ([attachment isKindOfClass:[TSAttachmentPointer class]]) {
                    TSAttachmentPointer *pointer = (TSAttachmentPointer *)attachment;
                    adapter.mediaItem =
                        [[AttachmentPointerAdapter alloc] initWithAttachmentPointer:pointer
                                                                         isIncoming:isIncomingAttachment];
                } else {
                    DDLogError(@"We retrieved an attachment that doesn't have a known type : %@",
                               NSStringFromClass([attachment class]));
                }
            }
        } else {
            NSString *displayableText = [[self displayableTextCache] objectForKey:interaction.uniqueId];
            if (!displayableText) {
                displayableText = [[DisplayableTextFilter new] displayableText:message.body];
                if (!displayableText) {
                    displayableText = @"";
                }
                [[self displayableTextCache] setObject:displayableText forKey:interaction.uniqueId];
            }
            adapter.messageBody = displayableText;
        }
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        TSCall *callRecord = (TSCall *)interaction;
        return [[OWSCall alloc] initWithCallRecord:callRecord];
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        TSInfoMessage *infoMessage = (TSInfoMessage *)interaction;
        adapter.infoMessageType    = infoMessage.messageType;
        adapter.messageBody        = infoMessage.description;
        adapter.messageType        = TSInfoMessageAdapter;
    } else if ([interaction isKindOfClass:[TSUnreadIndicatorInteraction class]]) {
        adapter.messageType = TSUnreadIndicatorAdapter;
    } else if ([interaction isKindOfClass:[OWSContactOffersInteraction class]]) {
        adapter.messageType = OWSContactOffersAdapter;
    } else if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        TSErrorMessage *errorMessage = (TSErrorMessage *)interaction;
        adapter.errorMessageType = errorMessage.errorType;
        adapter.messageBody          = errorMessage.description;
        adapter.messageType          = TSErrorMessageAdapter;
    } else {
        OWSFail(@"%@ Unknown interaction type: %@", self.tag, [interaction class]);
    }

    if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
        adapter.outgoingMessageStatus = ((TSOutgoingMessage *)interaction).messageState;
    }

    OWSAssert(adapter.date);
    return adapter;
}

- (NSString *)senderId {
    if (_senderId) {
        return _senderId;
    } else {
        return ME_MESSAGE_IDENTIFIER;
    }
}

- (NSDate *)date {
    return self.interaction.dateForSorting;
}

#pragma mark - OWSMessageEditing Protocol

+ (SEL)messageMetadataSelector
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    return @selector(showMessageMetadata:);
#pragma clang diagnostic pop
}

- (BOOL)canPerformEditingAction:(SEL)action
{
    if ([self attachmentStream] && ![self attachmentStream].isUploaded) {
        return NO;
    }

    // Deletes are always handled by TSMessageAdapter
    if (action == @selector(delete:)) {
        return YES;
    } else if (action == [TSMessageAdapter messageMetadataSelector]) {
        return ([self.interaction isKindOfClass:[TSIncomingMessage class]] ||
            [self.interaction isKindOfClass:[TSOutgoingMessage class]]);
    }

    // Delegate other actions for media items
    if ([self attachmentStream] && action == NSSelectorFromString(@"share:")) {
        return YES;
    } else if (self.isMediaMessage) {
        return [self.mediaItem canPerformEditingAction:action];
    } else if (self.messageType == TSInfoMessageAdapter || self.messageType == TSErrorMessageAdapter) {
        return NO;
    } else {
        // Text message - no media attachment
        if (action == @selector(copy:)) {
            return YES;
        }
    }
    return NO;
}

- (void)performEditingAction:(SEL)action
{
    // Deletes are always handled by TSMessageAdapter
    if (action == @selector(delete:)) {
        DDLogDebug(@"Deleting interaction with uniqueId: %@", self.interaction.uniqueId);
        [self.interaction remove];
        return;
    } else if (action == NSSelectorFromString(@"share:")) {
        TSAttachmentStream *stream = [self attachmentStream];
        OWSAssert(stream);
        if (stream) {
            [AttachmentSharing showShareUIForAttachment:stream];
        }
        return;
    } else if (action == [TSMessageAdapter messageMetadataSelector]) {
        OWSFail(@"Conversation view should handle message metadata events.");
        return;
    }

    // Delegate other actions for media items
    if (self.isMediaMessage) {
        [self.mediaItem performEditingAction:action];
        return;
    } else {
        // Text message - no media attachment
        if (action == @selector(copy:)) {
            UIPasteboard.generalPasteboard.string = self.messageBody;
            return;
        }
    }

    // Shouldn't get here, as only supported actions should be exposed via canPerformEditingAction
    NSString *actionString = NSStringFromSelector(action);
    OWSFail(@"'%@' action unsupported for TSInteraction: uniqueId=%@, mediaType=%@",
        actionString,
        self.interaction.uniqueId,
        [self.mediaItem class]);
}

- (TSAttachmentStream *)attachmentStream
{
    if (![self.interaction isKindOfClass:[TSMessage class]]) {
        return nil;
    }

    TSMessage *message = (TSMessage *)self.interaction;

    if (![message hasAttachments]) {
        return nil;
    }
    OWSAssert(message.attachmentIds.count <= 1);
    NSString *attachmentID = message.attachmentIds[0];
    TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentID];

    if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
        return nil;
    }

    TSAttachmentStream *stream = (TSAttachmentStream *)attachment;
    return stream;
}

- (BOOL)isMediaMessage {
    return _mediaItem ? YES : NO;
}

- (id<JSQMessageMediaData>)media {
    return _mediaItem;
}

- (NSString *)text {
    return self.messageBody;
}

- (NSUInteger)messageHash
{
    OWSAssert(self.interactionUniqueId);

    // messageHash is used as a key in the "message bubble size" cache,
    // so  messageHash's value must change whenever the message's bubble size
    // changes.  Incoming messages change size after their attachment's been
    // downloaded, so we use the mediaItem's class (which will be nil before
    // the attachment is downloaded) to reflect attachment status.
    return self.interactionUniqueId.hash ^ [self.mediaItem class].description.hash;
}

- (NSInteger)messageState {
    return self.outgoingMessageStatus;
}

- (CGFloat)mediaViewAlpha
{
    return (CGFloat)(self.isMediaBeingSent ? 0.75 : 1);
}

- (BOOL)isMediaBeingSent
{
    if ([self.interaction isKindOfClass:[TSOutgoingMessage class]]) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.interaction;
        if (outgoingMessage.hasAttachments && outgoingMessage.messageState == TSOutgoingMessageStateAttemptingOut) {
            return YES;
        }
    }
    return NO;
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
