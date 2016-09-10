//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSReadReceipt.h"
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const IndexOnSenderIdAndTimestamp = @"OWSReadReceiptIndexOnSenderIdAndTimestamp";
NSString *const TimestampColumn = @"timestamp";
NSString *const SenderIdColumn = @"senderId";

@implementation OWSReadReceipt

- (instancetype)initWithSenderId:(NSString *)senderId timestamp:(uint64_t)timestamp;
{
    self = [super init];
    if (!self) {
        return self;
    }

    NSMutableArray<NSString *> *validationErrorMessage = [NSMutableArray new];
    if (!senderId) {
        [validationErrorMessage addObject:@"Must specify sender id"];
    }
    _senderId = senderId;

    if (!timestamp) {
        [validationErrorMessage addObject:@"Must specify timestamp"];
    }
    _timestamp = timestamp;

    _valid = validationErrorMessage.count == 0;
    _validationErrorMessages = [validationErrorMessage copy];

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];
    if (!self) {
        return nil;
    }

    _valid = YES;
    _validationErrorMessages = @[];

    return self;
}

+ (NSDictionary *)encodingBehaviorsByPropertyKey
{
    NSMutableDictionary *behaviorsByPropertyKey = [[super encodingBehaviorsByPropertyKey] mutableCopy];

    // Don't persist transient properties used in validation.
    behaviorsByPropertyKey[@"valid"] = @(MTLModelEncodingBehaviorExcluded);
    behaviorsByPropertyKey[@"validationErrorMessages"] = @(MTLModelEncodingBehaviorExcluded);

    return [behaviorsByPropertyKey copy];
}

+ (void)registerIndexOnSenderIdAndTimestampWithDatabase:(YapDatabase *)database
{
    YapDatabaseSecondaryIndexSetup *setup = [YapDatabaseSecondaryIndexSetup new];
    [setup addColumn:SenderIdColumn withType:YapDatabaseSecondaryIndexTypeText];
    [setup addColumn:TimestampColumn withType:YapDatabaseSecondaryIndexTypeInteger];

    YapDatabaseSecondaryIndexHandler *handler =
        [YapDatabaseSecondaryIndexHandler withObjectBlock:^(YapDatabaseReadTransaction *transaction,
            NSMutableDictionary *dict,
            NSString *collection,
            NSString *key,
            id object) {
            if ([object isKindOfClass:[OWSReadReceipt class]]) {
                OWSReadReceipt *readReceipt = (OWSReadReceipt *)object;
                dict[SenderIdColumn] = readReceipt.senderId;
                dict[TimestampColumn] = @(readReceipt.timestamp);
            }
        }];

    YapDatabaseSecondaryIndex *index = [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler];
    [database registerExtension:index withName:IndexOnSenderIdAndTimestamp];
}

+ (nullable instancetype)firstWithSenderId:(NSString *)senderId timestamp:(uint64_t)timestamp
{
    __block OWSReadReceipt *foundReadReceipt;

    NSString *queryFormat = [NSString stringWithFormat:@"WHERE %@ = ? AND %@ = ?", SenderIdColumn, TimestampColumn];
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:queryFormat, senderId, @(timestamp)];

    [[self dbConnection] readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        [[transaction ext:IndexOnSenderIdAndTimestamp]
            enumerateKeysAndObjectsMatchingQuery:query
                                      usingBlock:^(NSString *collection, NSString *key, id object, BOOL *stop) {
                                          if (![object isKindOfClass:[OWSReadReceipt class]]) {
                                              DDLogError(@"%@ Unexpected object in index: %@", self.tag, object);
                                              return;
                                          }

                                          foundReadReceipt = (OWSReadReceipt *)object;
                                          *stop = YES;
                                      }];
    }];

    return foundReadReceipt;
}

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
