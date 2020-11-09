//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSDatabaseSecondaryIndexes.h"
#import "OWSStorage.h"
#import "TSInteraction.h"

NS_ASSUME_NONNULL_BEGIN

#define TSTimeStampSQLiteIndex @"messagesTimeStamp"

@implementation TSDatabaseSecondaryIndexes

+ (NSString *)registerTimeStampIndexExtensionName
{
    return @"idx";
}

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

    YapDatabaseSecondaryIndex *secondaryIndex =
        [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler versionTag:nil];

    return secondaryIndex;
}


+ (void)enumerateMessagesWithTimestamp:(uint64_t)timestamp
                             withBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block
                      usingTransaction:(YapDatabaseReadTransaction *)transaction
{
    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ = %lld", TSTimeStampSQLiteIndex, timestamp];
    YapDatabaseQuery *query   = [YapDatabaseQuery queryWithFormat:formattedString];
    [[transaction ext:[self registerTimeStampIndexExtensionName]] enumerateKeysMatchingQuery:query usingBlock:block];
}

@end

NS_ASSUME_NONNULL_END
