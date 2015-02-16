//
//  TSThread.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSYapDatabaseObject.h"

@class TSInteraction;

typedef NS_ENUM(NSInteger, TSLastActionType) {
    TSLastActionNone,
    
    TSLastActionCallIncoming,
    TSLastActionCallIncomingMissed,

    TSLastActionCallOutgoing,
    TSLastActionCallOutgoingMissed,
    TSLastActionCallOutgoingFailed,
    
    TSLastActionMessageAttemptingOut,
    TSLastActionMessageUnsent,
    TSLastActionMessageSent,
    TSLastActionMessageDelivered,
    
    TSLastActionMessageIncomingRead,
    TSLastActionMessageIncomingUnread,
    
    TSLastActionInfoMessage,
    TSLastActionErrorMessage
};

/**
 *  TSThread is the superclass of TSContactThread and TSGroupThread
 */

@interface TSThread : TSYapDatabaseObject

/**
 *  Returns whether the object is a group thread or not
 *
 *  @return Is a group
 */

- (BOOL)isGroupThread;

/**
 *  Returns the name of the thread.
 *
 *  @return name of the thread
 */

- (NSString*)name;

/**
 *  Returns the image representing the thread. Nil if not available.
 *
 *  @return UIImage of the thread, or nil.
 */

- (UIImage*)image;

- (NSDate*)lastMessageDate;
- (NSString*)lastMessageLabel;

- (void)updateWithLastMessage:(TSInteraction*)lastMessage transaction:(YapDatabaseReadWriteTransaction*)transaction;

- (TSLastActionType)lastAction;

- (BOOL)hasUnreadMessages;

@property NSDate *archivalDate;

@end
