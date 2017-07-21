//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSInteraction.h"
#import "NSDate+millisecondTimeStamp.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSStorageManager+messageIDs.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSInteraction

+ (instancetype)interactionForTimestamp:(uint64_t)timestamp
                        withTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    __block int counter = 0;
    __block TSInteraction *interaction;

    [TSDatabaseSecondaryIndexes
        enumerateMessagesWithTimestamp:timestamp
                             withBlock:^(NSString *collection, NSString *key, BOOL *stop) {

                                 if (counter != 0) {
                                     DDLogWarn(@"The database contains two colliding timestamps at: %lld.", timestamp);
                                     return;
                                 }

                                 interaction = [TSInteraction fetchObjectWithUniqueID:key transaction:transaction];

                                 counter++;
                             }
                      usingTransaction:transaction];

    return interaction;
}

+ (NSString *)collection {
    return @"TSInteraction";
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread
{
    self = [super initWithUniqueId:nil];

    if (!self) {
        return self;
    }

    _timestamp = timestamp;
    _uniqueThreadId = thread.uniqueId;

    return self;
}

#pragma mark Thread

- (TSThread *)thread
{
    return [TSThread fetchObjectWithUniqueID:self.uniqueThreadId];
}

- (void)touchThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    TSThread *thread = [TSThread fetchObjectWithUniqueID:self.uniqueThreadId transaction:transaction];
    [thread touchWithTransaction:transaction];
}

#pragma mark Date operations

- (uint64_t)millisecondsTimestamp {
    return self.timestamp;
}

- (NSDate *)dateForSorting
{
    return [NSDate ows_dateWithMillisecondsSince1970:self.timestampForSorting];
}

- (uint64_t)timestampForSorting
{
    return self.timestamp;
}

- (NSComparisonResult)compareForSorting:(TSInteraction *)other
{
    OWSAssert(other);

    uint64_t timestamp1 = self.timestampForSorting;
    uint64_t timestamp2 = other.timestampForSorting;

    if (timestamp1 > timestamp2) {
        return NSOrderedDescending;
    } else if (timestamp1 < timestamp2) {
        return NSOrderedAscending;
    } else {
        return NSOrderedSame;
    }
}

- (NSString *)description {
    return @"Interaction description";
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    if (!self.uniqueId) {
        self.uniqueId = [TSStorageManager getAndIncrementMessageIdWithTransaction:transaction];
    }

    [super saveWithTransaction:transaction];

    TSThread *fetchedThread = [TSThread fetchObjectWithUniqueID:self.uniqueThreadId transaction:transaction];

    [fetchedThread updateWithLastMessage:self transaction:transaction];
}

- (BOOL)isDynamicInteraction
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
