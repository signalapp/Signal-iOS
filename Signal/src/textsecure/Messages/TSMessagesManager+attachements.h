//
//  TSMessagesManager+attachements.h
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesManager.h"
#import "TSAttachement.h"

@interface TSMessagesManager (attachements)

- (void)handleReceivedMediaMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content;
- (void)retrieveAttachment:(TSAttachement*)attachement;

@end
