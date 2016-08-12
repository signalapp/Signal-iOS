//
//  TSMessageAdapter.h
//  Signal
//
//  Created by Frederic Jacobs on 24/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageEditing.h"
#import <JSQMessagesViewController/JSQMessageData.h>

@class TSInteraction;
@class TSThread;

#define ME_MESSAGE_IDENTIFIER @"Me";

typedef NS_ENUM(NSInteger, TSMessageAdapterType) {
    TSIncomingMessageAdapter,
    TSOutgoingMessageAdapter,
    TSCallAdapter,
    TSInfoMessageAdapter,
    TSErrorMessageAdapter,
    TSMediaAttachmentAdapter,
    TSGenericTextMessageAdapter, // Used when message direction is unknown (outgoing or incoming)
};

@interface TSMessageAdapter : NSObject <JSQMessageData, OWSMessageEditing>

+ (id<JSQMessageData>)messageViewDataWithInteraction:(TSInteraction *)interaction inThread:(TSThread *)thread;

@property TSInteraction *interaction;
@property TSMessageAdapterType messageType;

@end
