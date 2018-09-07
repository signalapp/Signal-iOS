//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSIncompleteCallsJob.h"
#import "AppContext.h"
#import "NSDate+OWS.h"
#import "OWSPrimaryStorage.h"
#import "TSCall.h"
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseQuery.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const OWSIncompleteCallsJobCallTypeColumn = @"call_type";
static NSString *const OWSIncompleteCallsJobCallTypeIndex = @"index_calls_on_call_type";

@interface OWSIncompleteCallsJob ()

@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;

@end

#pragma mark -

@implementation OWSIncompleteCallsJob

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];
    if (!self) {
        return self;
    }

    _primaryStorage = primaryStorage;

    return self;
}

- (NSArray<NSString *> *)fetchIncompleteCallIdsWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSMutableArray<NSString *> *messageIds = [NSMutableArray new];

    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ == %d OR  %@ == %d",
                                          OWSIncompleteCallsJobCallTypeColumn,
                                          (int)RPRecentCallTypeOutgoingIncomplete,
                                          OWSIncompleteCallsJobCallTypeColumn,
                                          (int)RPRecentCallTypeIncomingIncomplete];
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];
    [[transaction ext:OWSIncompleteCallsJobCallTypeIndex]
        enumerateKeysMatchingQuery:query
                        usingBlock:^void(NSString *collection, NSString *key, BOOL *stop) {
                            [messageIds addObject:key];
                        }];

    return [messageIds copy];
}

- (void)enumerateIncompleteCallsWithBlock:(void (^)(TSCall *call))block
                              transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    // Since we can't directly mutate the enumerated "incomplete" calls, we store only their ids in hopes
    // of saving a little memory and then enumerate the (larger) TSCall objects one at a time.
    for (NSString *callId in [self fetchIncompleteCallIdsWithTransaction:transaction]) {
        TSCall *_Nullable call = [TSCall fetchObjectWithUniqueID:callId transaction:transaction];
        if ([call isKindOfClass:[TSCall class]]) {
            block(call);
        } else {
            OWSLogError(@"unexpected object: %@", call);
        }
    }
}

- (void)run
{
    __block uint count = 0;

    OWSAssertDebug(CurrentAppContext().appLaunchTime);
    uint64_t cutoffTimestamp = [NSDate ows_millisecondsSince1970ForDate:CurrentAppContext().appLaunchTime];

    [[self.primaryStorage newDatabaseConnection] readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self
            enumerateIncompleteCallsWithBlock:^(TSCall *call) {
                if (call.timestamp <= cutoffTimestamp) {
                    OWSLogInfo(@"ignoring new call: %@", call.uniqueId);
                    return;
                }

                if (call.callType == RPRecentCallTypeOutgoingIncomplete) {
                    OWSLogDebug(@"marking call as missed: %@", call.uniqueId);
                    [call updateCallType:RPRecentCallTypeOutgoingMissed transaction:transaction];
                    OWSAssertDebug(call.callType == RPRecentCallTypeOutgoingMissed);
                } else if (call.callType == RPRecentCallTypeIncomingIncomplete) {
                    OWSLogDebug(@"marking call as missed: %@", call.uniqueId);
                    [call updateCallType:RPRecentCallTypeIncomingMissed transaction:transaction];
                    OWSAssertDebug(call.callType == RPRecentCallTypeIncomingMissed);
                } else {
                    OWSFailDebug(@"call has unexpected call type: %@", NSStringFromCallType(call.callType));
                    return;
                }
                count++;
            }
                                  transaction:transaction];
    }];

    OWSLogInfo(@"Marked %u calls as missed", count);
}

#pragma mark - YapDatabaseExtension

+ (YapDatabaseSecondaryIndex *)indexDatabaseExtension
{
    YapDatabaseSecondaryIndexSetup *setup = [YapDatabaseSecondaryIndexSetup new];
    [setup addColumn:OWSIncompleteCallsJobCallTypeColumn withType:YapDatabaseSecondaryIndexTypeInteger];

    YapDatabaseSecondaryIndexHandler *handler =
        [YapDatabaseSecondaryIndexHandler withObjectBlock:^(YapDatabaseReadTransaction *transaction,
            NSMutableDictionary *dict,
            NSString *collection,
            NSString *key,
            id object) {
            if (![object isKindOfClass:[TSCall class]]) {
                return;
            }
            TSCall *call = (TSCall *)object;

            dict[OWSIncompleteCallsJobCallTypeColumn] = @(call.callType);
        }];

    return [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler versionTag:nil];
}

#ifdef DEBUG
// Useful for tests, don't use in app startup path because it's slow.
- (void)blockingRegisterDatabaseExtensions
{
    [self.primaryStorage registerExtension:[self.class indexDatabaseExtension]
                                  withName:OWSIncompleteCallsJobCallTypeIndex];
}
#endif

+ (NSString *)databaseExtensionName
{
    return OWSIncompleteCallsJobCallTypeIndex;
}

+ (void)asyncRegisterDatabaseExtensionsWithPrimaryStorage:(OWSStorage *)storage
{
    [storage asyncRegisterExtension:[self indexDatabaseExtension] withName:OWSIncompleteCallsJobCallTypeIndex];
}

@end

NS_ASSUME_NONNULL_END
