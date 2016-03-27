//
//  TSDatabaseSecondaryIndexes.m
//  Signal
//
//  Created by Frederic Jacobs on 26/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSDatabaseSecondaryIndexes.h"

#import "TSInteraction.h"

#define TSTimeStampSQLiteIndex @"messagesTimeStamp"

@implementation TSDatabaseSecondaryIndexes

+ (YapDatabaseSecondaryIndex *)registerTimeStampIndex {
    YapDatabaseSecondaryIndexSetup *setup = [[YapDatabaseSecondaryIndexSetup alloc] init];
    [setup addColumn:TSTimeStampSQLiteIndex withType:YapDatabaseSecondaryIndexTypeReal];

    YapDatabaseSecondaryIndexWithObjectBlock block =
        ^(YapDatabaseReadTransaction *transaction, NSMutableDictionary *dict, NSString *collection, NSString *key, id object) {

          if ([object isKindOfClass:[TSInteraction class]]) {
              TSInteraction *interaction = (TSInteraction *)object;

              [dict setObject:@(interaction.timestamp) forKey:TSTimeStampSQLiteIndex];
          }
        };

    YapDatabaseSecondaryIndexHandler *handler = [YapDatabaseSecondaryIndexHandler withObjectBlock:block];

    YapDatabaseSecondaryIndex *secondaryIndex = [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler];

    return secondaryIndex;
}


+ (void)enumerateMessagesWithTimestamp:(uint64_t)timestamp
                             withBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block
                      usingTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ = %lld", TSTimeStampSQLiteIndex, timestamp];
    YapDatabaseQuery *query   = [YapDatabaseQuery queryWithFormat:formattedString];
    [[transaction ext:@"idx"] enumerateKeysMatchingQuery:query usingBlock:block];
}
@end
