//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSReadReceipt.h"
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSReadReceiptIndexOnSenderIdAndTimestamp = @"OWSReadReceiptIndexOnSenderIdAndTimestamp";
NSString *const OWSReadReceiptColumnTimestamp = @"timestamp";
NSString *const OWSReadReceiptColumnSenderId = @"senderId";

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

+ (MTLPropertyStorage)storageBehaviorForPropertyWithKey:(NSString *)propertyKey
{
    // Don't store ephemeral properties.
    if ([propertyKey isEqualToString:@"valid"] || [propertyKey isEqualToString:@"validationErrorMessages"]) {
        return MTLPropertyStorageNone;
    } else {
        return [super storageBehaviorForPropertyWithKey:propertyKey];
    }
}

+ (void)asyncRegisterIndexOnSenderIdAndTimestampWithDatabase:(YapDatabase *)database
{
    YapDatabaseSecondaryIndexSetup *setup = [YapDatabaseSecondaryIndexSetup new];
    [setup addColumn:OWSReadReceiptColumnSenderId withType:YapDatabaseSecondaryIndexTypeText];
    [setup addColumn:OWSReadReceiptColumnTimestamp withType:YapDatabaseSecondaryIndexTypeInteger];

    YapDatabaseSecondaryIndexHandler *handler =
        [YapDatabaseSecondaryIndexHandler withObjectBlock:^(YapDatabaseReadTransaction *transaction,
            NSMutableDictionary *dict,
            NSString *collection,
            NSString *key,
            id object) {
            if ([object isKindOfClass:[OWSReadReceipt class]]) {
                OWSReadReceipt *readReceipt = (OWSReadReceipt *)object;
                dict[OWSReadReceiptColumnSenderId] = readReceipt.senderId;
                dict[OWSReadReceiptColumnTimestamp] = @(readReceipt.timestamp);
            }
        }];

    YapDatabaseSecondaryIndex *index = [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler];

    [database
        asyncRegisterExtension:index
                      withName:OWSReadReceiptIndexOnSenderIdAndTimestamp
               completionBlock:^(BOOL ready) {
                   if (ready) {
                       DDLogDebug(@"%@ Successfully set up extension: %@",
                           self.tag,
                           OWSReadReceiptIndexOnSenderIdAndTimestamp);
                   } else {
                       DDLogError(
                           @"%@ Unable to setup extension: %@", self.tag, OWSReadReceiptIndexOnSenderIdAndTimestamp);
                   }
               }];
}

+ (nullable instancetype)firstWithSenderId:(NSString *)senderId timestamp:(uint64_t)timestamp
{
    __block OWSReadReceipt *foundReadReceipt;

    NSString *queryFormat = [NSString
        stringWithFormat:@"WHERE %@ = ? AND %@ = ?", OWSReadReceiptColumnSenderId, OWSReadReceiptColumnTimestamp];
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:queryFormat, senderId, @(timestamp)];

    [[self dbConnection] readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        [[transaction ext:OWSReadReceiptIndexOnSenderIdAndTimestamp]
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
