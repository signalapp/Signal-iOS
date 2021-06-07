//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/OWSIncompleteCallsJob.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSCall.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSIncompleteCallsJob

- (NSArray<NSString *> *)fetchIncompleteCallIdsWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    return [InteractionFinder incompleteCallIdsWithTransaction:transaction];
}

- (void)enumerateIncompleteCallsWithBlock:(void (^)(TSCall *call))block
                              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    // Since we can't directly mutate the enumerated "incomplete" calls, we store only their ids in hopes
    // of saving a little memory and then enumerate the (larger) TSCall objects one at a time.
    for (NSString *callId in [self fetchIncompleteCallIdsWithTransaction:transaction]) {
        TSCall *_Nullable call = [TSCall anyFetchCallWithUniqueId:callId transaction:transaction];
        if (call == nil) {
            OWSFailDebug(@"Missing call.");
            continue;
        }
        block(call);
    }
}

- (void)runSync
{
    __block uint count = 0;

    OWSAssertDebug(CurrentAppContext().appLaunchTime);
    uint64_t cutoffTimestamp = [NSDate ows_millisecondsSince1970ForDate:CurrentAppContext().appLaunchTime];

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self
            enumerateIncompleteCallsWithBlock:^(TSCall *call) {
                if (call.timestamp > cutoffTimestamp) {
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
    });

    OWSLogInfo(@"Marked %u calls as missed", count);
}

@end

NS_ASSUME_NONNULL_END
