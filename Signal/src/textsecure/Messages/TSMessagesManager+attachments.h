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
- (void)retrieveAttachment:(TSAttachment*)attachment;
- (void)sendAttachment:(NSData*)attachmentData contentType:(NSString*)contentType thread:(TSThread*)thread;

@end
