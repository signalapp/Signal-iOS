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
#import "YapDatabaseConnection+OWS.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const NSNotificationName_2FAStateDidChange = @"NSNotificationName_2FAStateDidChange";

NSString *const kOWS2FAManager_Collection = @"kOWS2FAManager_Collection";
NSString *const kOWS2FAManager_LastSuccessfulReminderDateKey = @"kOWS2FAManager_LastSuccessfulReminderDateKey";
NSString *const kOWS2FAManager_PinCode = @"kOWS2FAManager_PinCode";
NSString *const kOWS2FAManager_RepetitionInterval = @"kOWS2FAManager_RepetitionInterval";

const NSUInteger kHourSecs = 60 * 60;
const NSUInteger kDaySecs = kHourSecs * 24;

@interface OWS2FAManager ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic) OWS2FAMode mode;

@end

#pragma mark -

@implementation OWS2FAManager

+ (instancetype)sharedManager
{
    OWSAssertDebug(SSKEnvironment.shared.ows2FAManager);

    return SSKEnvironment.shared.ows2FAManager;
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertDebug(primaryStorage);

    _dbConnection = primaryStorage.newDatabaseConnection;

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

#pragma mark -

- (nullable NSString *)pinCode
{
    return [self.dbConnection objectForKey:kOWS2FAManager_PinCode inCollection:kOWS2FAManager_Collection];
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
    [self.dbConnection removeObjectForKey:kOWS2FAManager_PinCode inCollection:kOWS2FAManager_Collection];

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:NSNotificationName_2FAStateDidChange
                                                             object:nil
                                                           userInfo:nil];

    [[self.tsAccountManager updateAccountAttributes] retainUntilComplete];
}

- (void)mark2FAAsEnabledWithPin:(NSString *)pin
{
    OWSAssertDebug(pin.length > 0);

    if (!SSKFeatureFlags.registrationLockV2) {
        [self.dbConnection setObject:pin forKey:kOWS2FAManager_PinCode inCollection:kOWS2FAManager_Collection];
    } else {
        // Remove any old pin when we're migrating
        [self.dbConnection removeObjectForKey:kOWS2FAManager_PinCode inCollection:kOWS2FAManager_Collection];
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
            [[OWSKeyBackupService deleteKeys].then(^{
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
            }).catch(^(NSError *error){
                if (failure) {
                    failure(error);
                }
            }) retainUntilComplete];
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
    return [self.dbConnection dateForKey:kOWS2FAManager_LastSuccessfulReminderDateKey
                            inCollection:kOWS2FAManager_Collection];
}

- (void)setLastSuccessfulReminderDate:(nullable NSDate *)date
{
    OWSLogDebug(@"Seting setLastSuccessfulReminderDate:%@", date);
    [self.dbConnection setDate:date
                        forKey:kOWS2FAManager_LastSuccessfulReminderDateKey
                  inCollection:kOWS2FAManager_Collection];
}

- (BOOL)isDueForReminder
{
    if (!self.is2FAEnabled) {
        return NO;
    }

    return self.nextReminderDate.timeIntervalSinceNow < 0;
}

- (void)verifyPin:(NSString *)pin result:(void (^_Nonnull)(BOOL))result
{
    switch (self.mode) {
    case OWS2FAMode_V2:
        [OWSKeyBackupService verifyPin:pin resultHandler:result];
        break;
    case OWS2FAMode_V1:
        result(self.pinCode == pin);
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
    return [self.dbConnection doubleForKey:kOWS2FAManager_RepetitionInterval
                              inCollection:kOWS2FAManager_Collection
                              defaultValue:self.defaultRepetitionInterval];
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
    [self.dbConnection setDouble:newInterval
                          forKey:kOWS2FAManager_RepetitionInterval
                    inCollection:kOWS2FAManager_Collection];
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
    [self.dbConnection setDouble:self.defaultRepetitionInterval
                          forKey:kOWS2FAManager_RepetitionInterval
                    inCollection:kOWS2FAManager_Collection];
}

@end

NS_ASSUME_NONNULL_END
