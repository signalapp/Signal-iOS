//
//  TSMessagesManager+attachments.h
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesManager+sendMessages.h"
#import "TSMessagesManager.h"

@class TSAttachment;
@class TSAttachmentPointer;

@interface TSMessagesManager (attachments)

- (void)handleReceivedMediaMessage:(IncomingPushMessageSignal *)message withContent:(PushMessageContent *)content;

- (void)sendAttachment:(NSData *)attachmentData
           contentType:(NSString *)contentType
             inMessage:(TSOutgoingMessage *)outgoingMessage
                thread:(TSThread *)thread
               success:(successSendingCompletionBlock)successCompletionBlock
               failure:(failedSendingCompletionBlock)failedCompletionBlock;

- (void)retrieveAttachment:(TSAttachmentPointer *)attachment messageId:(NSString *)messageId;

@end
