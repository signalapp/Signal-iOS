//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSIncomingMessage.h"
#import "TSContactThread.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSGroupThread.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSIncomingMessageWasReadOnThisDeviceNotification = @"TSIncomingMessageWasReadOnThisDeviceNotification";

@implementation TSIncomingMessage

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                         authorId:(NSString *)authorId
                   sourceDeviceId:(uint32_t)sourceDeviceId
                      messageBody:(nullable NSString *)body
{
    return [self initWithTimestamp:timestamp
                          inThread:thread
                          authorId:authorId
                    sourceDeviceId:sourceDeviceId
                       messageBody:body
                     attachmentIds:@[]
                  expiresInSeconds:0];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                         authorId:(NSString *)authorId
                   sourceDeviceId:(uint32_t)sourceDeviceId
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds
{
    self = [super initWithTimestamp:timestamp
                           inThread:thread
                        messageBody:body
                      attachmentIds:attachmentIds
                   expiresInSeconds:expiresInSeconds
                    expireStartedAt:0];

    if (!self) {
        return self;
    }

    _authorId = authorId;
    _sourceDeviceId = sourceDeviceId;
    _read = NO;

    OWSAssert(self.receivedAtDate);

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

- (void)markAsReadLocallyWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self markAsReadWithoutNotificationWithTransaction:transaction];
    [[NSNotificationCenter defaultCenter] postNotificationName:TSIncomingMessageWasReadOnThisDeviceNotification
                                                        object:self];
}

- (void)markAsReadLocally
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self markAsReadWithoutNotificationWithTransaction:transaction];
    }];
    // Notification must happen outside of the transaction, else we'll likely crash when the notification receiver
    // tries to do anything with the DB.
    [[NSNotificationCenter defaultCenter] postNotificationName:TSIncomingMessageWasReadOnThisDeviceNotification
                                                        object:self];
}

- (void)markAsReadWithoutNotificationWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    DDLogInfo(@"%@ marking as read uniqueId: %@ which has timestamp: %llu", self.tag, self.uniqueId, self.timestamp);
    _read = YES;
    [self saveWithTransaction:transaction];
    [self touchThreadWithTransaction:transaction];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
