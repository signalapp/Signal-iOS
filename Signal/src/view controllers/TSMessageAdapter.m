//
//  TSMessageAdapter.m
//  Signal
//
//  Created by Frederic Jacobs on 24/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "JSQCall.h"
#import "NSDate+millisecondTimeStamp.h"

#import "TSMessageAdapter.h"
#import "TSIncomingMessage.h"
#import "TSOutgoingMessage.h"
#import "TSCall.h"
#import "TSInfoMessage.h"
#import "TSErrorMessage.h"
#import "TSattachment.h"
#import "TSAttachmentStream.h"
#import "TSAttachmentAdapter.h"
#import "TSAttachmentPointer.h"
#import "TSVideoAttachmentAdapter.h"


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

@property JSQMediaItem *mediaItem;

// ---

@property (nonatomic, copy)   NSDate   *messageDate;
@property (nonatomic, retain) NSString *messageBody;

@property NSUInteger identifier;

@end


@implementation TSMessageAdapter

+ (id<JSQMessageData>)messageViewDataWithInteraction:(TSInteraction*)interaction inThread:(TSThread*)thread{

    TSMessageAdapter *adapter = [[TSMessageAdapter alloc] init];
    adapter.messageDate       = interaction.date;
    adapter.identifier        = (NSUInteger)interaction.uniqueId;

    if ([thread isKindOfClass:[TSContactThread class]]) {
        adapter.thread = (TSContactThread*)thread;
        if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
            NSString *contactId       = ((TSContactThread*)thread).contactIdentifier;
            adapter.senderId          = contactId;
            adapter.senderDisplayName = contactId;
            adapter.messageType       = TSIncomingMessageAdapter;
        } else {
            adapter.senderId   = ME_MESSAGE_IDENTIFIER;
            adapter.senderDisplayName = NSLocalizedString(@"ME_STRING", @"");
            adapter.messageType = TSOutgoingMessageAdapter;
        }
    } else if ([thread isKindOfClass:[TSGroupThread class]]){
        if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
            TSIncomingMessage *message = (TSIncomingMessage*)interaction;
            adapter.senderId   = message.authorId;
            adapter.senderDisplayName = message.authorId;
            adapter.messageType       = TSIncomingMessageAdapter;
        } else {
            adapter.senderId   = ME_MESSAGE_IDENTIFIER;
            adapter.senderDisplayName =  NSLocalizedString(@"ME_STRING", @"");
            adapter.messageType = TSOutgoingMessageAdapter;
        }
    }
    
    if ([interaction isKindOfClass:[TSIncomingMessage class]] || [interaction isKindOfClass:[TSOutgoingMessage class]]) {
        TSMessage *message = (TSMessage*)interaction;
        adapter.messageBody = message.body;
        
        if ([message.attachments count] > 0) {
            
            for (NSString *attachmentID in message.attachments) {
                TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentID];
    
                if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                    TSAttachmentStream *stream = (TSAttachmentStream*)attachment;
                    if ([stream isImage]) {
                        adapter.mediaItem = [[TSAttachmentAdapter alloc] initWithAttachment:stream];
                        adapter.mediaItem.appliesMediaViewMaskAsOutgoing = [interaction isKindOfClass:[TSOutgoingMessage class]];
                        break;
                    }
                    else {
                        adapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:stream incoming:[interaction isKindOfClass:[TSIncomingMessage class]]];
                        adapter.mediaItem.appliesMediaViewMaskAsOutgoing = [interaction isKindOfClass:[TSOutgoingMessage class]];
                        break;
                    }
                }
                else if ([attachment isKindOfClass:[TSAttachmentPointer class]]){
                    // can do loading information here
                    //TSAttachmentPointer *pointer = (TSAttachmentPointer*)attachment;
                    //TODO: Change this status when download failed;
                    adapter.messageBody = NSLocalizedString(@"ATTACHMENT_DOWNLOADING", @"");
                    adapter.messageType = TSInfoMessageAdapter;
                } else {
                    DDLogError(@"We retreived an attachment that doesn't have a known type : %@", NSStringFromClass([attachment class]));
                }
            }
        }
        
    } else if ([interaction isKindOfClass:[TSCall class]]){
        adapter.messageBody = @"Placeholder for TSCalls";
        adapter.messageType = TSCallAdapter;
        JSQCall *call =  [self jsqCallForTSCall:(TSCall*)interaction thread:(TSContactThread*)thread];
        call.useThumbnail = NO; // disables use of iconography to represent group update actions
        return call;
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]){
        TSInfoMessage * infoMessage = (TSInfoMessage*)interaction;
        adapter.infoMessageType = infoMessage.messageType;
        adapter.messageBody = infoMessage.description;
        adapter.messageType = TSInfoMessageAdapter;
        if(adapter.infoMessageType == TSInfoMessageTypeGroupQuit || adapter.infoMessageType == TSInfoMessageTypeGroupUpdate) {
            // repurposing call display for info message stuff for group updates, ! adapter will know because the date is nil
            CallStatus status = 0;
            if(adapter.infoMessageType==TSInfoMessageTypeGroupQuit) {
                status = kGroupUpdateLeft;
            }
            else if(adapter.infoMessageType == TSInfoMessageTypeGroupUpdate) {
                status = kGroupUpdate;
            }
            JSQCall* call = [[JSQCall alloc] initWithCallerId:@"" callerDisplayName:adapter.messageBody date:nil status:status];
            call.useThumbnail = NO; // disables use of iconography to represent group update actions
            return call;
        }
    } else {
        TSErrorMessage * errorMessage = (TSErrorMessage*)interaction;
        adapter.infoMessageType = errorMessage.errorType;
        adapter.messageBody = errorMessage.description;
        adapter.messageType = TSErrorMessageAdapter;
    }
    
    if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
        adapter.outgoingMessageStatus = ((TSOutgoingMessage*)interaction).messageState;
    }
    
    return adapter;
}

+ (JSQCall*)jsqCallForTSCall:(TSCall*)call thread:(TSContactThread*)thread{
    CallStatus status = 0;
    
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
    }
    
    JSQCall *jsqCall = [[JSQCall alloc] initWithCallerId:thread.contactIdentifier callerDisplayName:thread.name date:call.date status:status];
    return jsqCall;
}

- (NSString*)senderId{
    if (_senderId) {
        return _senderId;
    }
    else{
        return ME_MESSAGE_IDENTIFIER;
    }
}

- (NSString *)senderDisplayName{
    if (self.thread) {
        return _thread.name;
    }
    return self.senderDisplayName;
}

- (NSDate *)date{
    return self.messageDate;
}

- (BOOL)isMediaMessage{
    return _mediaItem?YES:NO;
}

- (id<JSQMessageMediaData>)media{
    return _mediaItem;
}

- (NSString *)text{
    return self.messageBody;
}

- (NSUInteger)hash{
    return self.identifier;
}

- (NSInteger)messageState{
    return self.outgoingMessageStatus;
}

@end
