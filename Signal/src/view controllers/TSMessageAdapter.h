//
//  TSMessageAdapter.h
//  Signal
//
//  Created by Frederic Jacobs on 24/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <JSQMessagesViewController/JSQMessageData.h>

#import "TSInteraction.h"
#import "TSMessageAdapter.h"
#import "TSThread.h"

#define ME_MESSAGE_IDENTIFIER @"Me";

@interface TSMessageAdapter : NSObject <JSQMessageData>

+ (id<JSQMessageData>)messageViewDataWithInteraction:(TSInteraction *)interaction inThread:(TSThread *)thread;

@property TSMessageAdapterType messageType;

@end
