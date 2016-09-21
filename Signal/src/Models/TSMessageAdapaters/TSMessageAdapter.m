//  TSMessageAdapter.m
//
//  Signal
//
//  Created by Frederic Jacobs on 24/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "OWSCall.h"
#import "TSAttachmentPointer.h"
#import "TSAttachmentStream.h"
#import "TSCall.h"
#import "TSContactThread.h"
#import "TSContentAdapters.h"
#import "TSErrorMessage.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSOutgoingMessage.h"
#import <MobileCoreServices/MobileCoreServices.h>


@interface TSMessageAdapter ()

// ---

@property (nonatomic, retain) TSContactThread *thread;

// OR for groups

@property (nonatomic, retain) NSString *senderId;
@property (nonatomic, retain) NSString *senderDisplayName;

// for InfoMessages

@property NSInteger infoMessageType;

// for ErrorMessages

@property NSInteger errorMessageType;

// for outgoing Messages only

@property NSInteger outgoingMessageStatus;

// for MediaMessages

@property JSQMediaItem<OWSMessageEditing> *mediaItem;


// -- Redeclaring properties from OWSMessageData protocol to synthesize variables
@property (nonatomic) TSMessageAdapterType messageType;
@property (nonatomic, getter=isExpiringMessage) BOOL expiringMessage;
@property (nonatomic) uint64_t expiresAtSeconds;
@property (nonatomic) uint32_t expiresInSeconds;

@property (nonatomic, copy) NSDate *messageDate;
@property (nonatomic, retain) NSString *messageBody;

@property NSUInteger identifier;

@end


@implementation TSMessageAdapter

- (instancetype)initWithInteraction:(TSInteraction *)interaction
{
    self = [super init];
    if (!self) {
        return self;
    }

    _interaction = interaction;
    _messageDate = interaction.date;
    // TODO casting a string to an integer? At least need a comment here explaining why we are doing this.
    // Can we just remove this? Haven't found where we're using it...
    _identifier = (NSUInteger)interaction.uniqueId;

    if ([interaction isKindOfClass:[TSMessage class]]) {
        TSMessage *message = (TSMessage *)interaction;
        _expiringMessage = message.isExpiringMessage;
        _expiresAtSeconds = message.expiresAt / 1000;
        _expiresInSeconds = message.expiresInSeconds;
    } else {
        _expiringMessage = NO;
    }

    return self;
}

+ (id<OWSMessageData>)messageViewDataWithInteraction:(TSInteraction *)interaction inThread:(TSThread *)thread
{
    TSMessageAdapter *adapter = [[TSMessageAdapter alloc] initWithInteraction:interaction];

    if ([thread isKindOfClass:[TSContactThread class]]) {
        adapter.thread = (TSContactThread *)thread;
        if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
            NSString *contactId       = ((TSContactThread *)thread).contactIdentifier;
            adapter.senderId          = contactId;
            adapter.senderDisplayName = contactId;
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
            adapter.senderDisplayName  = message.authorId;
            adapter.messageType        = TSIncomingMessageAdapter;
        } else {
            adapter.senderId          = ME_MESSAGE_IDENTIFIER;
            adapter.senderDisplayName = NSLocalizedString(@"ME_STRING", @"");
            adapter.messageType       = TSOutgoingMessageAdapter;
        }
    }

    if ([interaction isKindOfClass:[TSIncomingMessage class]] ||
        [interaction isKindOfClass:[TSOutgoingMessage class]]) {
        TSMessage *message  = (TSMessage *)interaction;
        adapter.messageBody = message.body;

        if ([message hasAttachments]) {
            for (NSString *attachmentID in message.attachmentIds) {
                TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentID];

                if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                    TSAttachmentStream *stream = (TSAttachmentStream *)attachment;
                    if ([stream isAnimated]) {
                        adapter.mediaItem = [[TSAnimatedAdapter alloc] initWithAttachment:stream];
                        adapter.mediaItem.appliesMediaViewMaskAsOutgoing =
                            [interaction isKindOfClass:[TSOutgoingMessage class]];
                        break;
                    } else if ([stream isImage]) {
                        adapter.mediaItem = [[TSPhotoAdapter alloc] initWithAttachment:stream];
                        adapter.mediaItem.appliesMediaViewMaskAsOutgoing =
                            [interaction isKindOfClass:[TSOutgoingMessage class]];
                        break;
                    } else {
                        adapter.mediaItem = [[TSVideoAttachmentAdapter alloc]
                            initWithAttachment:stream
                                      incoming:[interaction isKindOfClass:[TSIncomingMessage class]]];
                        adapter.mediaItem.appliesMediaViewMaskAsOutgoing =
                            [interaction isKindOfClass:[TSOutgoingMessage class]];
                        break;
                    }
                } else if ([attachment isKindOfClass:[TSAttachmentPointer class]]) {
                    TSAttachmentPointer *pointer = (TSAttachmentPointer *)attachment;
                    adapter.messageType          = TSInfoMessageAdapter;

                    if (pointer.isDownloading) {
                        adapter.messageBody = NSLocalizedString(@"ATTACHMENT_DOWNLOADING", nil);
                    } else {
                        if (pointer.hasFailed) {
                            adapter.messageBody = NSLocalizedString(@"ATTACHMENT_QUEUED", nil);
                        } else {
                            adapter.messageBody = NSLocalizedString(@"ATTACHMENT_DOWNLOAD_FAILED", nil);
                        }
                    }
                } else {
                    DDLogError(@"We retrieved an attachment that doesn't have a known type : %@",
                               NSStringFromClass([attachment class]));
                }
            }
        }
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        adapter.messageBody = @"Placeholder for TSCalls";
        adapter.messageType = TSCallAdapter;
        OWSCall *call       = [self owsCallForTSCall:(TSCall *)interaction thread:(TSContactThread *)thread];
        return call;
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        TSInfoMessage *infoMessage = (TSInfoMessage *)interaction;
        adapter.infoMessageType    = infoMessage.messageType;
        adapter.messageBody        = infoMessage.description;
        adapter.messageType        = TSInfoMessageAdapter;
        if (adapter.infoMessageType == TSInfoMessageTypeGroupQuit ||
            adapter.infoMessageType == TSInfoMessageTypeGroupUpdate) {
            // repurposing call display for info message stuff for group updates, ! adapter will know because the date
            // is nil
            CallStatus status = 0;
            if (adapter.infoMessageType == TSInfoMessageTypeGroupQuit) {
                status = kGroupUpdateLeft;
            } else if (adapter.infoMessageType == TSInfoMessageTypeGroupUpdate) {
                status = kGroupUpdate;
            }
            OWSCall *call = [[OWSCall alloc] initWithCallerId:@""
                                            callerDisplayName:adapter.messageBody
                                                         date:nil
                                                       status:status
                                                displayString:@""];
            return call;
        }
    } else {
        TSErrorMessage *errorMessage = (TSErrorMessage *)interaction;
        adapter.infoMessageType      = errorMessage.errorType;
        adapter.messageBody          = errorMessage.description;
        adapter.messageType          = TSErrorMessageAdapter;
    }

    if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
        adapter.outgoingMessageStatus = ((TSOutgoingMessage *)interaction).messageState;
    }

    return adapter;
}

+ (OWSCall *)owsCallForTSCall:(TSCall *)call thread:(TSContactThread *)thread {
    CallStatus status      = 0;
    NSString *name         = thread.name;
    NSString *detailString = @"";

    switch (call.callType) {
        case RPRecentCallTypeOutgoing:
            status = kCallOutgoing;
            break;
        case RPRecentCallTypeMissed:
            status = kCallMissed;
            break;
        case RPRecentCallTypeIncoming:
            status = kCallIncoming;
            break;
        default:
            status = kCallIncoming;
            break;
    }

    switch (status) {
        case kCallMissed:
            detailString = [NSString stringWithFormat:NSLocalizedString(@"MSGVIEW_MISSED_CALL", nil), name];
            break;
        case kCallIncoming:
            detailString = [NSString stringWithFormat:NSLocalizedString(@"MSGVIEW_RECEIVED_CALL", nil), name];
            break;
        case kCallOutgoing:
            detailString = [NSString stringWithFormat:NSLocalizedString(@"MSGVIEW_YOU_CALLED", nil), name];
            break;
        default:
            break;
    }

    OWSCall *owsCall = [[OWSCall alloc] initWithCallerId:thread.contactIdentifier
                                       callerDisplayName:thread.name
                                                    date:call.date
                                                  status:status
                                           displayString:detailString];
    return owsCall;
}

- (NSString *)senderId {
    if (_senderId) {
        return _senderId;
    } else {
        return ME_MESSAGE_IDENTIFIER;
    }
}

- (NSString *)senderDisplayName {
    if (self.thread) {
        return _thread.name;
    }
    return _senderDisplayName;
}

- (NSDate *)date {
    return self.messageDate;
}

#pragma mark - OWSMessageEditing Protocol

- (BOOL)canPerformEditingAction:(SEL)action
{

    // Deletes are always handled by TSMessageAdapter
    if (action == @selector(delete:)) {
        return YES;
    }

    // Delegate other actions for media items
    if (self.isMediaMessage) {
        return [self.mediaItem canPerformEditingAction:action];
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
    DDLogError(@"'%@' action unsupported for TSInteraction: uniqueId=%@, mediaType=%@",
        actionString,
        self.interaction.uniqueId,
        [self.mediaItem class]);
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
    if (self.isMediaMessage) {
        return [self.mediaItem mediaHash];
    } else {
        return self.identifier;
    }
}

- (NSInteger)messageState {
    return self.outgoingMessageStatus;
}

@end
