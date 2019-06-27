//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSIncomingMessageFinder.h"
#import "OWSPrimaryStorage.h"
#import "TSIncomingMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSIncomingMessageFinderExtensionName = @"OWSIncomingMessageFinderExtensionName";

NSString *const OWSIncomingMessageFinderColumnTimestamp = @"OWSIncomingMessageFinderColumnTimestamp";
NSString *const OWSIncomingMessageFinderColumnSourceId = @"OWSIncomingMessageFinderColumnSourceId";
NSString *const OWSIncomingMessageFinderColumnSourceDeviceId = @"OWSIncomingMessageFinderColumnSourceDeviceId";

@implementation OWSIncomingMessageFinder

#pragma mark - init

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    return self;
}

#pragma mark - YAP integration

+ (YapDatabaseSecondaryIndex *)indexExtension
{
    YapDatabaseSecondaryIndexSetup *setup = [YapDatabaseSecondaryIndexSetup new];

    [setup addColumn:OWSIncomingMessageFinderColumnTimestamp withType:YapDatabaseSecondaryIndexTypeInteger];
    [setup addColumn:OWSIncomingMessageFinderColumnSourceId withType:YapDatabaseSecondaryIndexTypeText];
    [setup addColumn:OWSIncomingMessageFinderColumnSourceDeviceId withType:YapDatabaseSecondaryIndexTypeInteger];

    YapDatabaseSecondaryIndexWithObjectBlock block = ^(YapDatabaseReadTransaction *transaction,
        NSMutableDictionary *dict,
        NSString *collection,
        NSString *key,
        id object) {
        if ([object isKindOfClass:[TSIncomingMessage class]]) {
            TSIncomingMessage *incomingMessage = (TSIncomingMessage *)object;

            // UUID TODO
            if (SSKFeatureFlags.allowUUIDOnlyContacts) {
                return;
            }

            // On new messages authorId should be set on all incoming messages, but there was a time when authorId was
            // only set on incoming group messages.
            NSObject *authorIdOrNull = incomingMessage.authorAddress.transitional_phoneNumber
                ? incomingMessage.authorAddress.transitional_phoneNumber
                : [NSNull null];
            [dict setObject:@(incomingMessage.timestamp) forKey:OWSIncomingMessageFinderColumnTimestamp];
            [dict setObject:authorIdOrNull forKey:OWSIncomingMessageFinderColumnSourceId];
            [dict setObject:@(incomingMessage.sourceDeviceId) forKey:OWSIncomingMessageFinderColumnSourceDeviceId];
        }
    };

    YapDatabaseSecondaryIndexHandler *handler = [YapDatabaseSecondaryIndexHandler withObjectBlock:block];

    return [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler versionTag:nil];
}

+ (NSString *)databaseExtensionName
{
    return OWSIncomingMessageFinderExtensionName;
}

+ (void)asyncRegisterExtensionWithPrimaryStorage:(OWSStorage *)storage
{
    OWSLogInfo(@"registering async.");
    [storage asyncRegisterExtension:self.indexExtension withName:OWSIncomingMessageFinderExtensionName];
}

#pragma mark - instance methods

- (BOOL)existsMessageWithTimestamp:(uint64_t)timestamp
                          sourceId:(NSString *)sourceId
                    sourceDeviceId:(uint32_t)sourceDeviceId
                       transaction:(YapDatabaseReadTransaction *)transaction
{
    NSString *queryFormat = [NSString stringWithFormat:@"WHERE %@ = ? AND %@ = ? AND %@ = ?",
                                      OWSIncomingMessageFinderColumnTimestamp,
                                      OWSIncomingMessageFinderColumnSourceId,
                                      OWSIncomingMessageFinderColumnSourceDeviceId];
    // YapDatabaseQuery params must be objects
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:queryFormat, @(timestamp), sourceId, @(sourceDeviceId)];

    NSUInteger count;
    BOOL success = [[transaction ext:OWSIncomingMessageFinderExtensionName] getNumberOfRows:&count matchingQuery:query];
    if (!success) {
        OWSFailDebug(@"Could not execute query");
        return NO;
    }

    return count > 0;
}

@end

NS_ASSUME_NONNULL_END
