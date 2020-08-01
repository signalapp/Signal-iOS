//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ContactsUpdater.h"
#import "OWSError.h"
#import "OWSRequestFactory.h"
#import "PhoneNumber.h"
#import "SSKEnvironment.h"
#import "TSNetworkManager.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/Threading.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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

- (void)contactIntersectionWithSet:(NSSet<NSString *> *)phoneNumbersToLookup
                           success:(void (^)(NSSet<SignalRecipient *> *recipients))success
                           failure:(void (^)(NSError *error))failure
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OWSOperation<OWSContactDiscovering> *operation = nil;

        if (SSKFeatureFlags.useOnlyModernContactDiscovery) {
            operation = [[OWSContactDiscoveryOperation alloc] initWithPhoneNumbersToLookup:phoneNumbersToLookup.allObjects];
        } else {
            operation = [[OWSLegacyContactDiscoveryOperation alloc] initWithPhoneNumbersToLookup:phoneNumbersToLookup.allObjects];
        }

        NSArray<NSOperation *> *operationAndDependencies = [operation.dependencies arrayByAddingObject:operation];
        [self.contactIntersectionQueue addOperations:operationAndDependencies waitUntilFinished:YES];

        if (operation.discoveredContactInfo == nil) {
            NSError *error = operation.failingError ?: OWSErrorMakeAssertionError(@"Unexpected operation cancellation");
            failure(error);
            return;
        }

        NSMutableSet<SignalRecipient *> *registeredRecipients = [[NSMutableSet alloc] init];
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            NSMutableSet<NSString *> *toUnregister = [phoneNumbersToLookup mutableCopy];
            for (OWSDiscoveredContactInfo *contactInfo in operation.discoveredContactInfo) {
                SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithUuid:contactInfo.uuid
                                                                               phoneNumber:contactInfo.e164];
                SignalRecipient *recipient = [SignalRecipient markRecipientAsRegisteredAndGet:address
                                                                                   trustLevel:SignalRecipientTrustLevelHigh
                                                                                  transaction:transaction];

                [registeredRecipients addObject:recipient];
                [toUnregister removeObject:contactInfo.e164];
            }

            for (NSString *phoneNumber in toUnregister) {
                SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber];
                [SignalRecipient markRecipientAsUnregistered:address transaction:transaction];
            }
        });

        dispatch_async(dispatch_get_main_queue(), ^{
            success([registeredRecipients copy]);
        });
    });
}

@end

NS_ASSUME_NONNULL_END
