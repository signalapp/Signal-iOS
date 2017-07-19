//
//  TSStorageManager+messageIDs.m
//  Signal
//
//  Created by Frederic Jacobs on 24/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager+messageIDs.h"

#define TSStorageParametersCollection @"TSStorageParametersCollection"
#define TSMessagesLatestId @"TSMessagesLatestId"

@implementation TSStorageManager (messageIDs)

+ (NSString *)getAndIncrementMessageIdWithTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    NSString *messageId = [transaction objectForKey:TSMessagesLatestId inCollection:TSStorageParametersCollection];
    if (!messageId) {
        messageId = @"0";
    }

    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    numberFormatter.numberStyle        = NSNumberFormatterDecimalStyle;
    NSNumber *myNumber                 = [numberFormatter numberFromString:messageId];

    unsigned long long nextMessageId = [myNumber unsignedLongLongValue];
    nextMessageId++;

    NSString *nextMessageIdString = [[NSNumber numberWithUnsignedLongLong:nextMessageId] stringValue];

    [transaction setObject:nextMessageIdString forKey:TSMessagesLatestId inCollection:TSStorageParametersCollection];

    return messageId;
}

@end
