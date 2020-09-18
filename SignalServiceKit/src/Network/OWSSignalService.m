//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSSignalService.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSCensorshipConfiguration.h"
#import "OWSError.h"
#import "OWSHTTPSecurityPolicy.h"
#import "TSAccountManager.h"
#import "TSConstants.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kisCensorshipCircumventionManuallyActivatedKey
    = @"kTSStorageManager_isCensorshipCircumventionManuallyActivated";
NSString *const kisCensorshipCircumventionManuallyDisabledKey
    = @"kTSStorageManager_isCensorshipCircumventionManuallyDisabled";
NSString *const kManualCensorshipCircumventionCountryCodeKey
    = @"kTSStorageManager_ManualCensorshipCircumventionCountryCode";

NSString *const kNSNotificationName_IsCensorshipCircumventionActiveDidChange =
    @"kNSNotificationName_IsCensorshipCircumventionActiveDidChange";

@interface OWSSignalService ()

@property (atomic) BOOL hasCensoredPhoneNumber;

@property (atomic) BOOL isCensorshipCircumventionActive;

@end

#pragma mark -

@implementation OWSSignalService

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

- (SDSKeyValueStore *)keyValueStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"kTSStorageManager_OWSSignalService"];
}

#pragma mark -


@synthesize isCensorshipCircumventionActive = _isCensorshipCircumventionActive;

+ (instancetype)shared
{
    static OWSSignalService *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] initDefault]; });
    return shared;
}

- (instancetype)initDefault
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self observeNotifications];

    [self updateHasCensoredPhoneNumber];
    [self updateIsCensorshipCircumventionActive];

    OWSSingletonAssert();

    return self;
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange:)
                                                 name:NSNotificationNameRegistrationStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localNumberDidChange:)
                                                 name:kNSNotificationName_LocalNumberDidChange
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateHasCensoredPhoneNumber
{
    NSString *localNumber = [TSAccountManager localNumber];

    if (localNumber) {
        self.hasCensoredPhoneNumber = [OWSCensorshipConfiguration isCensoredPhoneNumber:localNumber];
    } else {
        OWSLogError(@"no known phone number to check for censorship.");
        self.hasCensoredPhoneNumber = NO;
    }

    [self updateIsCensorshipCircumventionActive];
}

- (BOOL)isCensorshipCircumventionManuallyActivated
{
    __block BOOL result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore getBool:kisCensorshipCircumventionManuallyActivatedKey
                                defaultValue:NO
                                 transaction:transaction];
    }];
    return result;
}

- (void)setIsCensorshipCircumventionManuallyActivated:(BOOL)value
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setBool:value key:kisCensorshipCircumventionManuallyActivatedKey transaction:transaction];
    });

    [self updateIsCensorshipCircumventionActive];
}

- (BOOL)isCensorshipCircumventionManuallyDisabled
{
    __block BOOL result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore getBool:kisCensorshipCircumventionManuallyDisabledKey
                                defaultValue:NO
                                 transaction:transaction];
    }];
    return result;
}

- (void)setIsCensorshipCircumventionManuallyDisabled:(BOOL)value
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setBool:value key:kisCensorshipCircumventionManuallyDisabledKey transaction:transaction];
    });

    [self updateIsCensorshipCircumventionActive];
}


- (void)updateIsCensorshipCircumventionActive
{
    if (self.isCensorshipCircumventionManuallyDisabled) {
        self.isCensorshipCircumventionActive = NO;
    } else if (self.isCensorshipCircumventionManuallyActivated) {
        self.isCensorshipCircumventionActive = YES;
    } else if (self.hasCensoredPhoneNumber) {
        self.isCensorshipCircumventionActive = YES;
    } else {
        self.isCensorshipCircumventionActive = NO;
    }
}

- (void)setIsCensorshipCircumventionActive:(BOOL)isCensorshipCircumventionActive
{
    @synchronized(self)
    {
        if (_isCensorshipCircumventionActive == isCensorshipCircumventionActive) {
            return;
        }

        _isCensorshipCircumventionActive = isCensorshipCircumventionActive;
    }

    [[NSNotificationCenter defaultCenter]
        postNotificationNameAsync:kNSNotificationName_IsCensorshipCircumventionActiveDidChange
                           object:nil
                         userInfo:nil];
}

- (BOOL)isCensorshipCircumventionActive
{
    @synchronized(self)
    {
        return _isCensorshipCircumventionActive;
    }
}

- (NSURL *)domainFrontBaseURL
{
    OWSAssertDebug(self.isCensorshipCircumventionActive);
    OWSCensorshipConfiguration *censorshipConfiguration = [self buildCensorshipConfiguration];
    return censorshipConfiguration.domainFrontBaseURL;
}

#pragma mark - Events

- (void)registrationStateDidChange:(NSNotification *)notification
{
    [self updateHasCensoredPhoneNumber];
}

- (void)localNumberDidChange:(NSNotification *)notification
{
    [self updateHasCensoredPhoneNumber];
}

#pragma mark - Censorship Circumvention

- (OWSCensorshipConfiguration *)buildCensorshipConfiguration
{
    OWSAssertDebug(self.isCensorshipCircumventionActive);

    if (self.isCensorshipCircumventionManuallyActivated) {
        NSString *countryCode = self.manualCensorshipCircumventionCountryCode;
        if (countryCode.length == 0) {
            OWSFailDebug(@"manualCensorshipCircumventionCountryCode was unexpectedly 0");
        }

        OWSCensorshipConfiguration *configuration =
            [OWSCensorshipConfiguration censorshipConfigurationWithCountryCode:countryCode];
        OWSAssertDebug(configuration);

        return configuration;
    }

    OWSCensorshipConfiguration *_Nullable configuration =
        [OWSCensorshipConfiguration censorshipConfigurationWithPhoneNumber:TSAccountManager.localNumber];
    if (configuration != nil) {
        return configuration;
    }

    return OWSCensorshipConfiguration.defaultConfiguration;
}

- (nullable NSString *)manualCensorshipCircumventionCountryCode
{
    __block NSString *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore getString:kManualCensorshipCircumventionCountryCodeKey transaction:transaction];
    }];
    return result;
}

- (void)setManualCensorshipCircumventionCountryCode:(nullable NSString *)value
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setString:value key:kManualCensorshipCircumventionCountryCodeKey transaction:transaction];
    });
}

@end

NS_ASSUME_NONNULL_END
