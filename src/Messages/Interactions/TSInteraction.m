//
//  TSInteraction.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSInteraction.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSStorageManager+messageIDs.h"
#import "TSThread.h"


const struct TSMessageRelationships TSMessageRelationships = {
    .threadUniqueId = @"threadUniqueId",
};

const struct TSMessageEdges TSMessageEdges = {
    .thread = @"thread",
};

@implementation TSInteraction

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread {
    self = [super initWithUniqueId:nil];

    if (self) {
        _timestamp      = timestamp;
        _uniqueThreadId = thread.uniqueId;
    }

    return self;
}

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


#pragma mark YapDatabaseRelationshipNode

- (NSArray *)yapDatabaseRelationshipEdges {
    NSArray *edges = nil;
    if (self.uniqueThreadId) {
        YapDatabaseRelationshipEdge *threadEdge =
            [YapDatabaseRelationshipEdge edgeWithName:TSMessageEdges.thread
                                       destinationKey:self.uniqueThreadId
                                           collection:[TSThread collection]
                                      nodeDeleteRules:YDB_DeleteSourceIfDestinationDeleted];
        edges = @[ threadEdge ];
    }

    return edges;
}

+ (NSString *)collection {
    return @"TSInteraction";
}

#pragma mark Date operations

- (uint64_t)millisecondsTimestamp {
    return self.timestamp;
}

- (NSDate *)date {
    uint64_t seconds = self.timestamp / 1000;
    return [NSDate dateWithTimeIntervalSince1970:seconds];
}

+ (NSString *)stringFromTimeStamp:(uint64_t)timestamp {
    return [[NSNumber numberWithUnsignedLongLong:timestamp] stringValue];
}

+ (uint64_t)timeStampFromString:(NSString *)string {
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    [f setNumberStyle:NSNumberFormatterNoStyle];
    NSNumber *myNumber = [f numberFromString:string];
    return [myNumber unsignedLongLongValue];
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

@end
