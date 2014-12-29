//
//  TSThread.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"
#import "Environment.h"
#import "ContactsManager.h"
#import "TSInteraction.h"
#import "TSStorageManager.h"

#import "TSCall.h"
#import "TSOutgoingMessage.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSErrorMessage.h"

@implementation TSThread

+ (NSString *)collection{
    return @"TSThread";
}

- (instancetype)initWithUniqueId:(NSString *)uniqueId{
    self = [super initWithUniqueId:uniqueId];
    
    if (self) {
        _blocked       = NO;
        _lastMessageId = 0;
    }
    
    return self;
}

- (BOOL)isGroupThread{
    NSAssert(false, @"An abstract method on TSThread was called.");
    return FALSE;
}

- (uint64_t)lastMessageId{
    return _lastMessageId;
}

- (NSDate*)lastMessageDate{
    __block NSDate *date;
    [[TSStorageManager sharedManager].dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        date = [TSInteraction fetchObjectWithUniqueID:[TSInteraction stringFromTimeStamp:_lastMessageId] transaction:transaction].date;
    }];
    
    if (date) {
        return date;
    } else{
        return [NSDate date];
    }
}

- (UIImage*)image{
    return nil;
}

- (NSString*)lastMessageLabel{
    __block TSInteraction *interaction;
    [[TSStorageManager sharedManager].dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        interaction = [TSInteraction fetchObjectWithUniqueID:[TSInteraction stringFromTimeStamp:_lastMessageId] transaction:transaction];
    }];
    return interaction.description;
}

- (TSLastActionType)lastAction
{
    __block TSInteraction *interaction;
    [[TSStorageManager sharedManager].dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        interaction = [TSInteraction fetchObjectWithUniqueID:[TSInteraction stringFromTimeStamp:_lastMessageId] transaction:transaction];
    }];
    
    return [self lastActionForInteraction:interaction];
}

- (TSLastActionType)lastActionForInteraction:(TSInteraction*)interaction
{
    if ([interaction isKindOfClass:[TSCall class]])
    {
        TSCall * callInteraction = (TSCall*)interaction;
        
        switch (callInteraction.callType) {
            case RPRecentCallTypeMissed:
                return TSLastActionCallIncomingMissed;
            case RPRecentCallTypeIncoming:
                return TSLastActionCallIncoming;
            case RPRecentCallTypeOutgoing:
                return TSLastActionCallOutgoing;
            default:
                return TSLastActionNone;
        }
    } else if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
        TSOutgoingMessage * outgoingMessageInteraction = (TSOutgoingMessage*)interaction;
        
        switch (outgoingMessageInteraction.messageState) {
            case TSOutgoingMessageStateAttemptingOut:
                return TSLastActionNone;
            case TSOutgoingMessageStateUnsent:
                return TSLastActionMessageUnsent;
            case TSOutgoingMessageStateSent:
                return TSLastActionMessageSent;
            case TSOutgoingMessageStateDelivered:
                return TSLastActionMessageDelivered;
            default:
                return TSLastActionNone;
        }
        
    } else if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
        return self.hasUnreadMessages ? TSLastActionMessageIncomingUnread : TSLastActionMessageIncomingRead ;
    } else if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        return TSLastActionErrorMessage;
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        return TSLastActionInfoMessage;
    } else {
        return TSLastActionNone;
    }
}

- (BOOL)hasUnreadMessages{
    __block TSInteraction * interaction;
    __block BOOL hasUnread = NO;
    [[TSStorageManager sharedManager].dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        interaction = [TSInteraction fetchObjectWithUniqueID:[TSInteraction stringFromTimeStamp:_lastMessageId] transaction:transaction];
        if ([interaction isKindOfClass:[TSIncomingMessage class]]){
            hasUnread = ![(TSIncomingMessage*)interaction wasRead];
        }
    }];
    
    return hasUnread;
}

- (NSString *)name{
    NSAssert(FALSE, @"Should be implemented in subclasses");
    return nil;
}

@end
