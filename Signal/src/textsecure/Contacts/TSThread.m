//
//  TSThread.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"
#import "TSDatabaseView.h"
#import "TSInteraction.h"
#import "TSStorageManager.h"

#import "TSOutgoingMessage.h"
#import "TSIncomingMessage.h"

@interface TSThread ()

@property (nonatomic, retain) NSDate   *creationDate;
@property (nonatomic, copy  ) NSDate   *archivalDate;
@property (nonatomic, retain) NSDate   *lastMessageDate;
@property (nonatomic, copy  ) NSString *latestMessageId;
@property (nonatomic, copy  ) NSString *messageDraft;
@end

@implementation TSThread

+ (NSString *)collection
{
    return @"TSThread";
}

- (instancetype)initWithUniqueId:(NSString *)uniqueId
{
    self = [super initWithUniqueId:uniqueId];

    if (self) {
        _archivalDate    = nil;
        _latestMessageId = nil;
        _lastMessageDate = nil;
        _creationDate    = [NSDate date];
        _messageDraft    = nil;
    }

    return self;
}

#pragma mark To be subclassed.

- (BOOL)isGroupThread
{
    NSAssert(false, @"An abstract method on TSThread was called.");
    return FALSE;
}

- (NSString *)name
{
    NSAssert(FALSE, @"Should be implemented in subclasses");
    return nil;
}

- (UIImage *)image
{
    return nil;
}

#pragma mark Read Status

- (BOOL)hasUnreadMessages
{
    __block TSInteraction *interaction;
    __block BOOL hasUnread = NO;
    [[TSStorageManager sharedManager].dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      interaction = [TSInteraction fetchObjectWithUniqueID:self.latestMessageId transaction:transaction];
      if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
          hasUnread = ![(TSIncomingMessage *)interaction wasRead];
      }
    }];

    return hasUnread;
}

- (void)markAllAsReadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSUnreadDatabaseViewExtensionName];
    NSMutableArray *array = [NSMutableArray array];
    [viewTransaction enumerateRowsInGroup:self.uniqueId
                               usingBlock:^(NSString *collection, NSString *key, id object, id metadata,
                                            NSUInteger index, BOOL *stop) {
                                 [array addObject:object];
                               }];

    for (TSIncomingMessage *message in array) {
        message.read = YES;
        [message saveWithTransaction:transaction];
    }
}

#pragma mark Last Interactions

- (NSDate *)lastMessageDate
{
    if (_lastMessageDate) {
        return _lastMessageDate;
    } else {
        return _creationDate;
    }
}

- (NSString *)lastMessageLabel
{
    __block TSInteraction *interaction;
    [[TSStorageManager sharedManager].dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      interaction = [TSInteraction fetchObjectWithUniqueID:self.latestMessageId transaction:transaction];
    }];
    return interaction.description;
}

- (void)updateWithLastMessage:(TSInteraction *)lastMessage transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSDate *lastMessageDate = lastMessage.date;
    
    if ([lastMessage isKindOfClass:[TSIncomingMessage class]]) {
        TSIncomingMessage *message = (TSIncomingMessage*)lastMessage;
        lastMessageDate = message.receivedAt;
    }
    
    if (!_lastMessageDate || [lastMessageDate timeIntervalSinceDate:self.lastMessageDate] > 0) {
        _latestMessageId = lastMessage.uniqueId;
        _lastMessageDate = lastMessageDate;

        [self saveWithTransaction:transaction];
    }
}

#pragma mark Archival

- (NSDate *)archivalDate
{
    return _archivalDate;
}

- (void)archiveThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self archiveThreadWithTransaction:transaction referenceDate:[NSDate date]];
}

- (void)archiveThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction referenceDate:(NSDate *)date
{
    [self markAllAsReadWithTransaction:transaction];
    _archivalDate = date;

    [self saveWithTransaction:transaction];
}

- (void)unarchiveThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    _archivalDate = nil;
    [self saveWithTransaction:transaction];
}

#pragma mark Drafts

- (NSString *)currentDraftWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    TSThread *thread = [TSThread fetchObjectWithUniqueID:self.uniqueId transaction:transaction];
    if (thread.messageDraft) {
        return thread.messageDraft;
    } else {
        return @"";
    }
}

- (void)setDraft:(NSString *)draftString transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    TSThread *thread = [TSThread fetchObjectWithUniqueID:self.uniqueId transaction:transaction];
    thread.messageDraft = draftString;
    [thread saveWithTransaction:transaction];
}

@end
