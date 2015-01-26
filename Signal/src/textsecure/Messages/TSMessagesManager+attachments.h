//
//  TSMessagesManager+attachments.h
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesManager.h"
#import "TSAttachment.h"

@interface TSMessagesManager (attachments)

- (void)handleReceivedMediaMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content;

- (void)sendAttachment:(NSData*)attachmentData
           contentType:(NSString*)contentType
             inMessage:(TSOutgoingMessage*)outgoingMessage
                thread:(TSThread*)thread;

@end
