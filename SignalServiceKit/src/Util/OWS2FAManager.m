//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWS2FAManager.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSPrimaryStorage.h"
#import "OWSRequestFactory.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import "TSNetworkManager.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const NSNotificationName_2FAStateDidChange = @"NSNotificationName_2FAStateDidChange";

NSString *const kOWS2FAManager_LastSuccessfulReminderDateKey = @"kOWS2FAManager_LastSuccessfulReminderDateKey";
NSString *const kOWS2FAManager_PinCode = @"kOWS2FAManager_PinCode";
NSString *const kOWS2FAManager_RepetitionInterval = @"kOWS2FAManager_RepetitionInterval";

const NSUInteger kHourSecs = 60 * 60;
const NSUInteger kDaySecs = kHourSecs * 24;

@interface OWS2FAManager ()

@property (nonatomic) OWS2FAMode mode;

@end

#pragma mark -

@implementation OWS2FAManager

#pragma mark -

+ (SDSKeyValueStore *)keyValueStore
{
    NSString *const kOWS2FAManager_Collection = @"kOWS2FAManager_Collection";
    return [[SDSKeyValueStore alloc] initWithCollection:kOWS2FAManager_Collection];
}

#pragma mark -

+ (instancetype)sharedManager
{
    OWSAssertDebug(SSKEnvironment.shared.ows2FAManager);

    return SSKEnvironment.shared.ows2FAManager;
}

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    return self;
}

#pragma mark - Dependencies

- (TSNetworkManager *)networkManager {
    OWSAssertDebug(SSKEnvironment.shared.networkManager);

    return SSKEnvironment.shared.networkManager;
}

- (TSAccountManager *)tsAccountManager {
    return TSAccountManager.sharedInstance;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SSKEnvironment.shared.databaseStorage;
}

#pragma mark -

- (nullable NSString *)pinCode
{
    __block NSString *_Nullable value;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        value = [OWS2FAManager.keyValueStore getString:kOWS2FAManager_PinCode transaction:transaction];
    }];
    return value;
}

- (OWS2FAMode)mode
{
    // Identify what version of 2FA we're using
    if (OWSKeyBackupService.hasLocalKeys) {
        OWSAssertDebug(SSKFeatureFlags.registrationLockV2);
        return OWS2FAMode_V2;
    } else if (self.pinCode != nil) {
        return OWS2FAMode_V1;
    } else {
        return OWS2FAMode_Disabled;
    }
}

- (BOOL)is2FAEnabled
{
    return self.mode != OWS2FAMode_Disabled;
}

- (void)set2FANotEnabled
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [OWS2FAManager.keyValueStore removeValueForKey:kOWS2FAManager_PinCode transaction:transaction];
    }];

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:NSNotificationName_2FAStateDidChange
                                                             object:nil
                                                           userInfo:nil];

    [[self.tsAccountManager updateAccountAttributes] retainUntilComplete];
}

- (void)mark2FAAsEnabledWithPin:(NSString *)pin
{
    OWSAssertDebug(pin.length > 0);

    // Convert the pin to arabic numerals, we never want to
    // operate with pins in other numbering systems.
    pin = pin.ensureArabicNumerals;

    if (!SSKFeatureFlags.registrationLockV2) {
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            [OWS2FAManager.keyValueStore setString:pin key:kOWS2FAManager_PinCode transaction:transaction];
        }];
    } else {
        // Remove any old pin when we're migrating
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            [OWS2FAManager.keyValueStore removeValueForKey:kOWS2FAManager_PinCode transaction:transaction];
        }];
    }

    // Schedule next reminder relative to now
    self.lastSuccessfulReminderDate = [NSDate new];

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:NSNotificationName_2FAStateDidChange
                                                             object:nil
                                                           userInfo:nil];

    [[self.tsAccountManager updateAccountAttributes] retainUntilComplete];
}

- (void)requestEnable2FAWithPin:(NSString *)pin
                        success:(nullable OWS2FASuccess)success
                        failure:(nullable OWS2FAFailure)failure
{
    OWSAssertDebug(pin.length > 0);
    OWSAssertDebug(success);
    OWSAssertDebug(failure);

    if (SSKFeatureFlags.registrationLockV2) {
        [[OWSKeyBackupService generateAndBackupKeysWithPin:pin].then(^{
            NSString *token = [OWSKeyBackupService deriveRegistrationLockToken];
            TSRequest *request = [OWSRequestFactory enableRegistrationLockV2RequestWithToken:token];
            [self.networkManager makeRequest:request
                                     success:^(NSURLSessionDataTask *task, id responseObject) {
                                         OWSAssertIsOnMainThread();

                                         [self mark2FAAsEnabledWithPin:pin];

                                         if (success) {
                                             success();
                                         }
                                     }
                                     failure:^(NSURLSessionDataTask *task, NSError *error) {
                                         OWSAssertIsOnMainThread();

                                         if (failure) {
                                             failure(error);
                                         }
                                     }];
        }).catch(^(NSError *error){
            if (failure) {
                failure(error);
            }
        }) retainUntilComplete];
    } else {
        TSRequest *request = [OWSRequestFactory enable2FARequestWithPin:pin];
        [self.networkManager makeRequest:request
                                 success:^(NSURLSessionDataTask *task, id responseObject) {
                                     OWSAssertIsOnMainThread();

                                     [self mark2FAAsEnabledWithPin:pin];

                                     if (success) {
                                         success();
                                     }
                                 }
                                 failure:^(NSURLSessionDataTask *task, NSError *error) {
                                     OWSAssertIsOnMainThread();

                                     if (failure) {
                                         failure(error);
                                     }
                                 }];
    }
}

- (void)disable2FAWithSuccess:(nullable OWS2FASuccess)success failure:(nullable OWS2FAFailure)failure
{
    switch (self.mode) {
        case OWS2FAMode_V2:
        {
            TSRequest *request = [OWSRequestFactory disableRegistrationLockV2Request];
            [self.networkManager makeRequest:request
                success:^(NSURLSessionDataTask *task, id responseObject) {
                    OWSAssertIsOnMainThread();

                    [OWSKeyBackupService clearKeychain];

                    [self set2FANotEnabled];

                    if (success) {
                        success();
                    }
                }
                failure:^(NSURLSessionDataTask *task, NSError *error) {
                    OWSAssertIsOnMainThread();

                    if (failure) {
                        failure(error);
                    }
                }];
            break;
        }
        case OWS2FAMode_V1:
        {
            TSRequest *request = [OWSRequestFactory disable2FARequest];
            [self.networkManager makeRequest:request
                                     success:^(NSURLSessionDataTask *task, id responseObject) {
                                         OWSAssertIsOnMainThread();

                                         [self set2FANotEnabled];

                                         if (success) {
                                             success();
                                         }
                                     }
                                     failure:^(NSURLSessionDataTask *task, NSError *error) {
                                         OWSAssertIsOnMainThread();

                                         if (failure) {
                                             failure(error);
                                         }
                                     }];
            break;
        }
        case OWS2FAMode_Disabled:
            OWSFailDebug(@"Unexpectedly attempting to disable 2fa for disabled mode");
            break;
    }
}


#pragma mark - Reminders

- (nullable NSDate *)lastSuccessfulReminderDate
{
    __block NSDate *_Nullable value;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        value =
            [OWS2FAManager.keyValueStore getDate:kOWS2FAManager_LastSuccessfulReminderDateKey transaction:transaction];
    }];
    return value;
}

- (void)setLastSuccessfulReminderDate:(nullable NSDate *)date
{
    OWSLogDebug(@"Seting setLastSuccessfulReminderDate:%@", date);
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [OWS2FAManager.keyValueStore setDate:date
                                         key:kOWS2FAManager_LastSuccessfulReminderDateKey
                                 transaction:transaction];
    }];
}

- (BOOL)isDueForReminder
{
    if (!self.is2FAEnabled) {
        return NO;
    }

    return self.nextReminderDate.timeIntervalSinceNow < 0;
}

- (BOOL)hasPending2FASetup
{
    __block BOOL hasPendingPinExperienceUpgrade = NO;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        hasPendingPinExperienceUpgrade = [ExperienceUpgradeFinder.sharedManager
            hasUnseenWithExperienceUpgrade:ExperienceUpgradeFinder.sharedManager.pins
                               transaction:transaction];
    }];

    // If we require pins AND we don't have a pin AND we're not going to setup a pin through the upgrade interstitial
    return SSKFeatureFlags.pinsForEveryone && !self.is2FAEnabled && !hasPendingPinExperienceUpgrade;
}

- (void)verifyPin:(NSString *)pin result:(void (^_Nonnull)(BOOL))result
{
    // Convert the pin to arabic numerals, we never want to
    // operate with pins in other numbering systems.
    pin = pin.ensureArabicNumerals;

    switch (self.mode) {
    case OWS2FAMode_V2:
        [OWSKeyBackupService verifyPin:pin resultHandler:result];
        break;
    case OWS2FAMode_V1:
        result([self.pinCode.ensureArabicNumerals isEqualToString:pin]);
        break;
    case OWS2FAMode_Disabled:
        OWSFailDebug(@"unexpectedly attempting to verify pin when 2fa is disabled");
        result(NO);
        break;
    }
}

- (NSDate *)nextReminderDate
{
    NSDate *lastSuccessfulReminderDate = self.lastSuccessfulReminderDate ?: [NSDate distantPast];

    return [lastSuccessfulReminderDate dateByAddingTimeInterval:self.repetitionInterval];
}

- (NSArray<NSNumber *> *)allRepetitionIntervals
{
    // Keep sorted monotonically increasing.
    return @[
        @(6 * kHourSecs),
        @(12 * kHourSecs),
        @(1 * kDaySecs),
        @(3 * kDaySecs),
        @(7 * kDaySecs),
    ];
}

- (double)defaultRepetitionInterval
{
    return self.allRepetitionIntervals.firstObject.doubleValue;
}

- (NSTimeInterval)repetitionInterval
{
    __block NSTimeInterval value;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        value = [OWS2FAManager.keyValueStore getDouble:kOWS2FAManager_RepetitionInterval
                                          defaultValue:self.defaultRepetitionInterval
                                           transaction:transaction];
    }];
    return value;
}

- (void)updateRepetitionIntervalWithWasSuccessful:(BOOL)wasSuccessful
{
    if (wasSuccessful) {
        self.lastSuccessfulReminderDate = [NSDate new];
    }

    NSTimeInterval oldInterval = self.repetitionInterval;
    NSTimeInterval newInterval = [self adjustRepetitionInterval:oldInterval wasSuccessful:wasSuccessful];

    OWSLogInfo(@"%@ guess. Updating repetition interval: %f -> %f",
        (wasSuccessful ? @"successful" : @"failed"),
        oldInterval,
        newInterval);
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [OWS2FAManager.keyValueStore setDouble:newInterval
                                           key:kOWS2FAManager_RepetitionInterval
                                   transaction:transaction];
    }];
}

- (NSTimeInterval)adjustRepetitionInterval:(NSTimeInterval)oldInterval wasSuccessful:(BOOL)wasSuccessful
{
    NSArray<NSNumber *> *allIntervals = self.allRepetitionIntervals;

    NSUInteger oldIndex =
        [allIntervals indexOfObjectPassingTest:^BOOL(NSNumber *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
            return oldInterval <= (NSTimeInterval)obj.doubleValue;
        }];

    NSUInteger newIndex;
    if (wasSuccessful) {
        newIndex = oldIndex + 1;
    } else {
        // prevent overflow
        newIndex = oldIndex <= 0 ? 0 : oldIndex - 1;
    }

    // clamp to be valid
    newIndex = MAX(0, MIN(allIntervals.count - 1, newIndex));

    NSTimeInterval newInterval = allIntervals[newIndex].doubleValue;
    return newInterval;
}

- (void)setDefaultRepetitionInterval
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [OWS2FAManager.keyValueStore setDouble:self.defaultRepetitionInterval
                                           key:kOWS2FAManager_RepetitionInterval
                                   transaction:transaction];
    }];
}

@end

NS_ASSUME_NONNULL_END
