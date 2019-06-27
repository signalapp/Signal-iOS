//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ContactsUpdater.h"
#import "OWSError.h"
#import "OWSPrimaryStorage.h"
#import "OWSRequestFactory.h"
#import "PhoneNumber.h"
#import "SSKEnvironment.h"
#import "TSNetworkManager.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/Threading.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@interface ContactsUpdater ()

@property (nonatomic, readonly) NSOperationQueue *contactIntersectionQueue;

@end

#pragma mark -

@implementation ContactsUpdater

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

+ (instancetype)sharedUpdater {
    OWSAssertDebug(SSKEnvironment.shared.contactsUpdater);

    return SSKEnvironment.shared.contactsUpdater;
}

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _contactIntersectionQueue = [NSOperationQueue new];
    _contactIntersectionQueue.maxConcurrentOperationCount = 1;
    _contactIntersectionQueue.name = self.logTag;

    OWSSingletonAssert();

    return self;
}

- (void)lookupIdentifiers:(NSArray<NSString *> *)identifiers
                 success:(void (^)(NSArray<SignalRecipient *> *recipients))success
                 failure:(void (^)(NSError *error))failure
{
    if (identifiers.count < 1) {
        OWSFailDebug(@"Cannot lookup zero identifiers");
        DispatchMainThreadSafe(^{
            failure(
                OWSErrorWithCodeDescription(OWSErrorCodeInvalidMethodParameters, @"Cannot lookup zero identifiers"));
        });
        return;
    }

    [self contactIntersectionWithSet:[NSSet setWithArray:identifiers]
        success:^(NSSet<SignalRecipient *> *recipients) {
            if (recipients.count == 0) {
                OWSLogInfo(@"no contacts are Signal users");
            }
            DispatchMainThreadSafe(^{
                success(recipients.allObjects);
            });
        }
        failure:^(NSError *error) {
            DispatchMainThreadSafe(^{
                failure(error);
            });
        }];
}

- (void)contactIntersectionWithSet:(NSSet<NSString *> *)recipientIdsToLookup
                           success:(void (^)(NSSet<SignalRecipient *> *recipients))success
                           failure:(void (^)(NSError *error))failure
{
    OWSLegacyContactDiscoveryOperation *operation =
        [[OWSLegacyContactDiscoveryOperation alloc] initWithRecipientIdsToLookup:recipientIdsToLookup.allObjects];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<NSOperation *> *operationAndDependencies = [operation.dependencies arrayByAddingObject:operation];
        [self.contactIntersectionQueue addOperations:operationAndDependencies waitUntilFinished:YES];

        if (operation.failingError != nil) {
            failure(operation.failingError);
            return;
        }

        NSSet<NSString *> *registeredRecipientIds = operation.registeredRecipientIds;

        NSMutableSet<SignalRecipient *> *recipients = [NSMutableSet new];
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            for (NSString *recipientId in recipientIdsToLookup) {
                if ([registeredRecipientIds containsObject:recipientId]) {
                    SignalRecipient *recipient =
                        [SignalRecipient markRecipientAsRegisteredAndGet:recipientId.transitional_signalServiceAddress
                                                             transaction:transaction];
                    [recipients addObject:recipient];
                } else {
                    [SignalRecipient markRecipientAsUnregistered:recipientId.transitional_signalServiceAddress
                                                     transaction:transaction];
                }
            }
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            success([recipients copy]);
        });
    });
}

@end

NS_ASSUME_NONNULL_END
