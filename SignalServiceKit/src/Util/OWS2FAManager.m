//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWS2FAManager.h"
#import "NSNotificationCenter+OWS.h"
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
NSString *const kOWS2FAManager_HasMigratedTruncatedPinKey = @"kOWS2FAManager_HasMigratedTruncatedPinKey";

const NSUInteger kHourSecs = 60 * 60;
const NSUInteger kDaySecs = kHourSecs * 24;

const NSUInteger kMin2FAPinLength = 4;
const NSUInteger kMin2FAv2PinLength = 6;
const NSUInteger kMax2FAv1PinLength = 20; // v2 doesn't have a max length
const NSUInteger kLegacyTruncated2FAv1PinLength = 16;

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
    if (OWSKeyBackupService.hasMasterKey) {
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
        [OWSKeyBackupService clearKeysWithTransaction:transaction];
    }];

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:NSNotificationName_2FAStateDidChange
                                                             object:nil
                                                           userInfo:nil];

    [[self.tsAccountManager updateAccountAttributes] retainUntilComplete];
}

- (void)mark2FAAsEnabledWithPin:(NSString *)pin
{
    OWSAssertDebug(pin.length > 0);

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        if (OWSKeyBackupService.hasMasterKey) {
            // Remove any old pin when we're migrating
            [OWS2FAManager.keyValueStore removeValueForKey:kOWS2FAManager_PinCode transaction:transaction];
        } else {
            // Convert the pin to arabic numerals, we never want to
            // operate with pins in other numbering systems.
            [OWS2FAManager.keyValueStore setString:pin.ensureArabicNumerals
                                               key:kOWS2FAManager_PinCode
                                       transaction:transaction];
        }

        // Since we just created this pin, we know it doesn't need migration. Mark it as such.
        [self markLegacyPinAsMigratedWithTransaction:transaction];

        // Reset the reminder repetition interval for the new pin.
        [self setDefaultRepetitionIntervalWithTransaction:transaction];

        // Schedule next reminder relative to now
        [self setLastSuccessfulReminderDate:[NSDate new] transaction:transaction];
    }];

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:NSNotificationName_2FAStateDidChange
                                                             object:nil
                                                           userInfo:nil];

    [[self.tsAccountManager updateAccountAttributes] retainUntilComplete];
}

- (void)requestEnable2FAWithPin:(NSString *)pin
                           mode:(OWS2FAMode)mode
                        success:(nullable OWS2FASuccess)success
                        failure:(nullable OWS2FAFailure)failure
{
    OWSAssertDebug(pin.length > 0);
    OWSAssertDebug(success);
    OWSAssertDebug(failure);

    switch (mode) {
        case OWS2FAMode_V2: {
            [[OWSKeyBackupService generateAndBackupKeysWithPin:pin]
                    .then(^{
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
                    })
                    .catch(^(NSError *error) {
                        if (failure) {
                            failure(error);
                        }
                    }) retainUntilComplete];
            break;
        }
        case OWS2FAMode_V1: {
            // Convert the pin to arabic numerals, we never want to
            // operate with pins in other numbering systems.
            TSRequest *request = [OWSRequestFactory enable2FARequestWithPin:pin.ensureArabicNumerals];
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
            break;
        }
        case OWS2FAMode_Disabled:
            OWSFailDebug(@"Unexpectedly attempting to enable 2fa for disabled mode");
            break;
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

- (nullable NSDate *)lastSuccessfulReminderDateWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [OWS2FAManager.keyValueStore getDate:kOWS2FAManager_LastSuccessfulReminderDateKey transaction:transaction];
}

- (void)setLastSuccessfulReminderDate:(nullable NSDate *)date transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogDebug(@"Setting setLastSuccessfulReminderDate:%@", date);
    [OWS2FAManager.keyValueStore setDate:date key:kOWS2FAManager_LastSuccessfulReminderDateKey transaction:transaction];
}

- (BOOL)isDueForV1Reminder
{
    if (!self.tsAccountManager.isRegisteredPrimaryDevice) {
        return NO;
    }

    if (self.mode != OWS2FAMode_V1) {
        return NO;
    }

    return self.nextReminderDate.timeIntervalSinceNow < 0;
}

- (BOOL)isDueForV2ReminderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    if (!self.tsAccountManager.isRegisteredPrimaryDevice) {
        return NO;
    }

    if (!OWSKeyBackupService.hasMasterKey) {
        return NO;
    }

    NSDate *nextReminderDate = [self nextReminderDateWithTransaction:transaction];

    return nextReminderDate.timeIntervalSinceNow < 0;
}

- (BOOL)needsLegacyPinMigration
{
    __block BOOL hasMigratedTruncatedPin = NO;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        hasMigratedTruncatedPin = [OWS2FAManager.keyValueStore getBool:kOWS2FAManager_HasMigratedTruncatedPinKey
                                                          defaultValue:NO
                                                           transaction:transaction];
    }];

    if (hasMigratedTruncatedPin) {
        return NO;
    }

    // Older versions of the app truncated newly created pins to 16 characters. We no longer do that.
    // If we detect that the user's pin is the truncated length and it was created before we stopped
    // truncating pins, we'll need to ensure we migrate to the user's entire pin next time we prompt
    // them for it.
    if (self.mode == OWS2FAMode_V1 && self.pinCode.length >= kLegacyTruncated2FAv1PinLength) {
        return YES;
    }

    // We don't need to migrate this pin, either because it's v2 or short enough that
    // we never truncated it. Mark it as complete so we don't need to check again.

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self markLegacyPinAsMigratedWithTransaction:transaction];
    }];

    return NO;
}

- (void)markLegacyPinAsMigratedWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [OWS2FAManager.keyValueStore setBool:YES key:kOWS2FAManager_HasMigratedTruncatedPinKey transaction:transaction];
}

- (void)verifyPin:(NSString *)pin result:(void (^_Nonnull)(BOOL))result
{
    switch (self.mode) {
    case OWS2FAMode_V2:
        [OWSKeyBackupService verifyPin:pin resultHandler:result];
        break;
    case OWS2FAMode_V1:
        // Convert the pin to arabic numerals, we never want to
        // operate with pins in other numbering systems.
        result([self.pinCode.ensureArabicNumerals isEqualToString:pin.ensureArabicNumerals]);
        break;
    case OWS2FAMode_Disabled:
        OWSFailDebug(@"unexpectedly attempting to verify pin when 2fa is disabled");
        result(NO);
        break;
    }
}

- (NSDate *)nextReminderDate
{
    __block NSDate *_Nullable value;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        value = [self nextReminderDateWithTransaction:transaction];
    }];
    return value;
}

- (NSDate *)nextReminderDateWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSDate *lastSuccessfulReminderDate =
        [self lastSuccessfulReminderDateWithTransaction:transaction] ?: [NSDate distantPast];
    NSTimeInterval repetitionInterval = [self repetitionIntervalWithTransaction:transaction];

    return [lastSuccessfulReminderDate dateByAddingTimeInterval:repetitionInterval];
}

- (NSArray<NSNumber *> *)allRepetitionIntervals
{
    // Keep sorted monotonically increasing.
    return @[
        @(12 * kHourSecs),
        @(1 * kDaySecs),
        @(3 * kDaySecs),
        @(7 * kDaySecs),
        @(14 * kDaySecs),
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
        value = [self repetitionIntervalWithTransaction:transaction];
    }];
    return value;
}

- (NSTimeInterval)repetitionIntervalWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [OWS2FAManager.keyValueStore getDouble:kOWS2FAManager_RepetitionInterval
                                     defaultValue:self.defaultRepetitionInterval
                                      transaction:transaction];
}

- (void)updateRepetitionIntervalWithWasSuccessful:(BOOL)wasSuccessful
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        if (wasSuccessful) {
            [self setLastSuccessfulReminderDate:[NSDate new] transaction:transaction];
        }

        NSTimeInterval oldInterval = [self repetitionIntervalWithTransaction:transaction];
        NSTimeInterval newInterval = [self adjustRepetitionInterval:oldInterval wasSuccessful:wasSuccessful];

        OWSLogInfo(@"%@ guess. Updating repetition interval: %f -> %f",
            (wasSuccessful ? @"successful" : @"failed"),
            oldInterval,
            newInterval);

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

- (void)setDefaultRepetitionIntervalWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [OWS2FAManager.keyValueStore setDouble:self.defaultRepetitionInterval
                                       key:kOWS2FAManager_RepetitionInterval
                               transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
