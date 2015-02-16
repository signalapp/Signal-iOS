//
//  TSThread.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"
#import "ContactsManager.h"
#import "TSDatabaseView.h"
#import "TSInteraction.h"
#import "TSStorageManager.h"

#import "TSCall.h"
#import "TSOutgoingMessage.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSErrorMessage.h"

@interface TSThread ()

@property (nonatomic, retain) NSDate   *creationDate;
@property (nonatomic, copy)   NSDate   *archivalDate;
@property (nonatomic, retain) NSDate   *lastMessageDate;
@property (nonatomic, copy  ) NSString *latestMessageId;

@end

@implementation TSThread

+ (NSString *)collection{
    return @"TSThread";
}

- (instancetype)initWithUniqueId:(NSString *)uniqueId{
    self = [super initWithUniqueId:uniqueId];
    
    if (self) {
        _archivalDate    = nil;
        _latestMessageId = nil;
        _lastMessageDate = nil;
        _creationDate    = [NSDate date];
    }
    
    return self;
}

- (BOOL)isGroupThread{
    NSAssert(false, @"An abstract method on TSThread was called.");
    return FALSE;
}

- (NSDate *)lastMessageDate{
    if (_lastMessageDate) {
        return _lastMessageDate;
    } else {
        return _creationDate;
    }
}

- (UIImage*)image{
    return nil;
}

- (NSDate *)archivalDate{
    return _archivalDate;
}

- (NSString*)lastMessageLabel{
    __block TSInteraction *interaction;
    [[TSStorageManager sharedManager].dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        interaction = [TSInteraction fetchObjectWithUniqueID:self.latestMessageId transaction:transaction];
    }];
    return interaction.description;
}

- (TSLastActionType)lastAction
{
    __block TSInteraction *interaction;
    [[TSStorageManager sharedManager].dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        interaction = [TSInteraction fetchObjectWithUniqueID:self.latestMessageId transaction:transaction];
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
        interaction = [TSInteraction fetchObjectWithUniqueID:self.latestMessageId transaction:transaction];
        if ([interaction isKindOfClass:[TSIncomingMessage class]]){
            hasUnread = ![(TSIncomingMessage*)interaction wasRead];
        }
    }];
    
    return hasUnread;
}

- (void)markAllAsReadWithTransaction:(YapDatabaseReadWriteTransaction*)transaction {
    YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSUnreadDatabaseViewExtensionName];
    NSUInteger numberOfItemsInSection           = [viewTransaction numberOfItemsInGroup:self.uniqueId];
    for (NSUInteger i = 0; i < numberOfItemsInSection; i++) {
        TSIncomingMessage *message = [viewTransaction objectAtIndex:i inGroup:self.uniqueId];
        message.read = YES;
        [message saveWithTransaction:transaction];
    }
}

- (void)archiveThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    [self archiveThreadWithTransaction:transaction referenceDate:[NSDate date]];
}

- (void)archiveThreadWithTransaction:(YapDatabaseReadWriteTransaction*)transaction referenceDate:(NSDate*)date {
    [self markAllAsReadWithTransaction:transaction];
    _archivalDate = date;
    
    [self saveWithTransaction:transaction];
}

- (void)unarchiveThreadWithTransaction:(YapDatabaseReadWriteTransaction*)transaction {
    _archivalDate = nil;
    [self saveWithTransaction:transaction];
}

- (void)updateWithLastMessage:(TSInteraction*)lastMessage transaction:(YapDatabaseReadWriteTransaction*)transaction {
    if (!_lastMessageDate || [lastMessage.date timeIntervalSinceDate:self.lastMessageDate] > 0) {
        _latestMessageId = lastMessage.uniqueId;
        _lastMessageDate = lastMessage.date;
        [self saveWithTransaction:transaction];
    }
}

- (NSString *)name{
    NSAssert(FALSE, @"Should be implemented in subclasses");
    return nil;
}

@end
