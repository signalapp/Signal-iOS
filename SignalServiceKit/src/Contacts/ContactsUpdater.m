//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ContactsUpdater.h"
#import "Cryptography.h"
#import "OWSError.h"
#import "OWSPrimaryStorage.h"
#import "OWSRequestFactory.h"
#import "PhoneNumber.h"
#import "TSNetworkManager.h"
#import "Threading.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@interface ContactsUpdater ()

@property (nonatomic, readonly) NSOperationQueue *contactIntersectionQueue;

@end

@implementation ContactsUpdater

+ (instancetype)sharedUpdater {
    static dispatch_once_t onceToken;
    static id sharedInstance = nil;
    dispatch_once(&onceToken, ^{
        sharedInstance = [self new];
    });
    return sharedInstance;
}


- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _contactIntersectionQueue = [NSOperationQueue new];
    _contactIntersectionQueue.maxConcurrentOperationCount = 1;

    OWSSingletonAssert();

    return self;
}

- (void)lookupIdentifiers:(NSArray<NSString *> *)identifiers
                 success:(void (^)(NSArray<SignalRecipient *> *recipients))success
                 failure:(void (^)(NSError *error))failure
{
    if (identifiers.count < 1) {
        OWSFail(@"%@ Cannot lookup zero identifiers", self.logTag);
        DispatchMainThreadSafe(^{
            failure(
                OWSErrorWithCodeDescription(OWSErrorCodeInvalidMethodParameters, @"Cannot lookup zero identifiers"));
        });
        return;
    }

    [self contactIntersectionWithSet:[NSSet setWithArray:identifiers]
        success:^(NSSet<SignalRecipient *> *recipients) {
            if (recipients.count == 0) {
                DDLogInfo(@"%@ in %s no contacts are Signal users", self.logTag, __PRETTY_FUNCTION__);
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
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OWSLegacyContactDiscoveryOperation *operation =
            [[OWSLegacyContactDiscoveryOperation alloc] initWithRecipientIdsToLookup:recipientIdsToLookup.allObjects];

        NSArray<NSOperation *> *operationAndDependencies = [operation.dependencies arrayByAddingObject:operation];
        [self.contactIntersectionQueue addOperations:operationAndDependencies waitUntilFinished:YES];

        if (operation.failingError != nil) {
            failure(operation.failingError);
            return;
        }

        NSSet<NSString *> *registeredRecipientIds = operation.registeredRecipientIds;

        NSMutableSet<SignalRecipient *> *recipients = [NSMutableSet new];
        [OWSPrimaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            for (NSString *recipientId in recipientIdsToLookup) {
                if ([registeredRecipientIds containsObject:recipientId]) {
                    SignalRecipient *recipient =
                        [SignalRecipient markRecipientAsRegisteredAndGet:recipientId transaction:transaction];
                    [recipients addObject:recipient];
                } else {
                    [SignalRecipient removeUnregisteredRecipient:recipientId transaction:transaction];
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
