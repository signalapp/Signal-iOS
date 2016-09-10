//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSIncomingMessage.h"
#import "TSContactThread.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSGroupThread.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSIncomingMessageWasReadOnThisDeviceNotification = @"TSIncomingMessageWasReadOnThisDeviceNotification";

@implementation TSIncomingMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSContactThread *)thread
                      messageBody:(nullable NSString *)body
{
    return [super initWithTimestamp:timestamp inThread:thread messageBody:body attachmentIds:@[]];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSContactThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds
{
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:body attachmentIds:attachmentIds];

    if (!self) {
        return self;
    }

    _authorId = nil;
    _read = NO;
    _receivedAt = [NSDate date];

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSGroupThread *)thread
                         authorId:(nullable NSString *)authorId
                      messageBody:(nullable NSString *)body
{
    return [self initWithTimestamp:timestamp inThread:thread authorId:authorId messageBody:body attachmentIds:@[]];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSGroupThread *)thread
                         authorId:(nullable NSString *)authorId
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds
{
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:body attachmentIds:attachmentIds];

    if (!self) {
        return self;
    }

    _authorId = authorId;
    _read = NO;
    _receivedAt = [NSDate date];

    return self;
}

+ (nullable instancetype)findMessageWithAuthorId:(NSString *)authorId timestamp:(uint64_t)timestamp
{
    __block TSIncomingMessage *foundMessage;
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        // In theory we could build a new secondaryIndex for (authorId,timestamp), but in practice there should
        // be *very* few (millisecond) timestamps with multiple authors.
        [TSDatabaseSecondaryIndexes
            enumerateMessagesWithTimestamp:timestamp
                                 withBlock:^(NSString *collection, NSString *key, BOOL *stop) {
                                     TSInteraction *interaction =
                                         [TSInteraction fetchObjectWithUniqueID:key transaction:transaction];
                                     if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
                                         TSIncomingMessage *message = (TSIncomingMessage *)interaction;

                                         // Only groupthread sets authorId, thus this crappy code.
                                         // TODO ALL incoming messages should have an authorId.
                                         NSString *messageAuthorId;
                                         if (message.authorId) { // Group Thread
                                             messageAuthorId = message.authorId;
                                         } else { // Contact Thread
                                             messageAuthorId =
                                                 [TSContactThread contactIdFromThreadId:message.uniqueThreadId];
                                         }

                                         if ([messageAuthorId isEqualToString:authorId]) {
                                             foundMessage = message;
                                         }
                                     }
                                 }
                          usingTransaction:transaction];
    }];

    return foundMessage;
}

- (void)markAsReadFromReadReceipt
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self markAsReadWithoutNotificationWithTransaction:transaction];
    }];
}

- (void)markAsReadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self markAsReadWithoutNotificationWithTransaction:transaction];
    [[NSNotificationCenter defaultCenter] postNotificationName:TSIncomingMessageWasReadOnThisDeviceNotification
                                                        object:self];
}

- (void)markAsReadWithoutNotificationWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    _read = YES;
    [self saveWithTransaction:transaction];
    [transaction touchObjectForKey:self.uniqueThreadId inCollection:[TSThread collection]];
}

@end

NS_ASSUME_NONNULL_END
