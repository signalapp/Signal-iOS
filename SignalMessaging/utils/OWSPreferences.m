//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "OWSPreferences.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/NSUserDefaults+OWS.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/StorageCoordinator.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

NSString *NSStringForNotificationType(NotificationType value)
{
    switch (value) {
        case NotificationNamePreview:
            return @"NotificationNamePreview";
        case NotificationNameNoPreview:
            return @"NotificationNameNoPreview";
        case NotificationNoNameNoPreview:
            return @"NotificationNoNameNoPreview";
    }
}

NSString *const OWSPreferencesSignalDatabaseCollection = @"SignalPreferences";
NSString *const OWSPreferencesCallLoggingDidChangeNotification = @"OWSPreferencesCallLoggingDidChangeNotification";

NSString *const OWSPreferencesKeyScreenSecurity = @"Screen Security Key";
NSString *const OWSPreferencesKeyEnableDebugLog = @"Debugging Log Enabled Key";
NSString *const OWSPreferencesKeyNotificationPreviewType = @"Notification Preview Type Key";
NSString *const OWSPreferencesKeyPlaySoundInForeground = @"NotificationSoundInForeground";
NSString *const OWSPreferencesKeyLastRecordedPushToken = @"LastRecordedPushToken";
NSString *const OWSPreferencesKeyLastRecordedVoipToken = @"LastRecordedVoipToken";
NSString *const OWSPreferencesKeyCallKitEnabled = @"CallKitEnabled";
NSString *const OWSPreferencesKeyCallKitPrivacyEnabled = @"CallKitPrivacyEnabled";
NSString *const OWSPreferencesKeyCallsHideIPAddress = @"CallsHideIPAddress";
NSString *const OWSPreferencesKeyHasDeclinedNoContactsView = @"hasDeclinedNoContactsView";
NSString *const OWSPreferencesKeyHasGeneratedThumbnails = @"OWSPreferencesKeyHasGeneratedThumbnails";
NSString *const OWSPreferencesKeyShouldShowUnidentifiedDeliveryIndicators
    = @"OWSPreferencesKeyShouldShowUnidentifiedDeliveryIndicators";
NSString *const OWSPreferencesKeyShouldNotifyOfNewAccountKey = @"OWSPreferencesKeyShouldNotifyOfNewAccountKey";
NSString *const OWSPreferencesKeyIOSUpgradeNagDate = @"iOSUpgradeNagDate";
NSString *const OWSPreferencesKey_IsAudibleErrorLoggingEnabled = @"IsAudibleErrorLoggingEnabled";
NSString *const OWSPreferencesKeySystemCallLogEnabled = @"OWSPreferencesKeySystemCallLogEnabled";
NSString *const OWSPreferencesKeyWasViewOnceTooltipShown = @"OWSPreferencesKeyWasViewOnceTooltipShown";
NSString *const OWSPreferencesKeyWasDeleteForEveryoneConfirmationShown
    = @"OWSPreferencesKeyWasDeleteForEveryoneConfirmationShown";
NSString *const OWSPreferencesKeyWasBlurTooltipShown = @"OWSPreferencesKeyWasBlurTooltipShown";
NSString *const OWSPreferencesKeyWasGroupCallTooltipShown = @"OWSPreferencesKeyWasGroupCallTooltipShown";
NSString *const OWSPreferencesKeyWasGroupCallTooltipShownCount = @"OWSPreferencesKeyWasGroupCallTooltipShownCount";
NSString *const OWSPreferencesKeyDeviceScale = @"OWSPreferencesKeyDeviceScale";

@interface OWSPreferences ()

@property (atomic, nullable) NSNumber *notificationPreviewTypeCache;
@property (atomic, nullable) NSNumber *mentionNotificationsEnabledCache;

@end

#pragma mark -

@implementation OWSPreferences

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _keyValueStore = [[SDSKeyValueStore alloc] initWithCollection:OWSPreferencesSignalDatabaseCollection];

    OWSSingletonAssert();

    // In the NSE, the main screen scale is inaccurate so we need to record it
    // when we're in a context that has a valid UI / screen for use later.
    if (CurrentAppContext().hasUI) {
        [CurrentAppContext().appUserDefaults setObject:@(UIScreen.mainScreen.scale)
                                                forKey:OWSPreferencesKeyDeviceScale];
    }

    return self;
}

#pragma mark - Helpers

- (void)removeAllValues
{
    [NSUserDefaults removeAll];

    // We don't need to clear our key-value store; database
    // storage is cleared otherwise.
}

- (BOOL)hasValueForKey:(NSString *)key
{
    __block BOOL result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore hasValueForKey:key transaction:transaction];
    }];
    return result;
}

- (void)removeValueForKey:(NSString *)key
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore removeValueForKey:key transaction:transaction];
    });
}

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue
{
    __block BOOL result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore getBool:key defaultValue:defaultValue transaction:transaction];
    } file:__FILE__ function:__FUNCTION__ line:__LINE__];
    return result;
}

- (void)setBool:(BOOL)value forKey:(NSString *)key
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setBool:value key:key transaction:transaction];
    });
}

- (NSUInteger)uintForKey:(NSString *)key defaultValue:(NSUInteger)defaultValue
{
    __block NSUInteger result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore getUInt:key defaultValue:defaultValue transaction:transaction];
    }];
    return result;
}

- (void)setUInt:(NSUInteger)value forKey:(NSString *)key
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setUInt:value key:key transaction:transaction];
    });
}

- (nullable NSDate *)dateForKey:(NSString *)key
{
    __block NSDate *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore getDate:key transaction:transaction];
    }];
    return result;
}

- (void)setDate:(NSDate *)value forKey:(NSString *)key
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setDate:value key:key transaction:transaction];
    });
}

- (nullable NSString *)stringForKey:(NSString *)key
{
    __block NSString *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore getString:key transaction:transaction];
    } file:__FILE__ function:__FUNCTION__ line:__LINE__];
    return result;
}

- (void)setString:(nullable NSString *)value forKey:(NSString *)key
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setString:value key:key transaction:transaction];
    });
}

#pragma mark - Specific Preferences

+ (BOOL)isAudibleErrorLoggingEnabled
{
    NSNumber *_Nullable persistedValue =
        [NSUserDefaults.appUserDefaults objectForKey:OWSPreferencesKey_IsAudibleErrorLoggingEnabled];

    if (persistedValue == nil) {
        // default
        return NO;
    }

    return persistedValue.boolValue;
}

+ (void)setIsAudibleErrorLoggingEnabled:(BOOL)value
{
    [NSUserDefaults.appUserDefaults setObject:@(value) forKey:OWSPreferencesKey_IsAudibleErrorLoggingEnabled];
    [NSUserDefaults.appUserDefaults synchronize];
}

+ (BOOL)appUserDefaultsFlagWithKey:(NSString *)key
{
    NSNumber *preference = [NSUserDefaults.appUserDefaults objectForKey:key];

    if (preference) {
        return [preference boolValue];
    } else {
        return NO;
    }
}

+ (void)setAppUserDefaultsFlagWithKey:(NSString *)key
{
    OWSAssertDebug(CurrentAppContext().isMainApp);

    [NSUserDefaults.appUserDefaults setObject:@(YES) forKey:key];
    [NSUserDefaults.appUserDefaults synchronize];
}

- (BOOL)screenSecurityIsEnabled
{
    return [self boolForKey:OWSPreferencesKeyScreenSecurity defaultValue:NO];
}

- (void)setScreenSecurity:(BOOL)value
{
    [self setBool:value forKey:OWSPreferencesKeyScreenSecurity];
}

+ (BOOL)isLoggingEnabled
{
    // See: setIsLoggingEnabled.
    NSNumber *_Nullable preference = [NSUserDefaults.appUserDefaults objectForKey:OWSPreferencesKeyEnableDebugLog];

    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}

+ (void)setIsLoggingEnabled:(BOOL)value
{
    OWSAssertDebug(CurrentAppContext().isMainApp);

    // Logging preferences are stored in UserDefaults instead of the database, so that we can (optionally) start
    // logging before the database is initialized. This is important because sometimes there are problems *with* the
    // database initialization, and without logging it would be hard to track down.
    [NSUserDefaults.appUserDefaults setObject:@(value) forKey:OWSPreferencesKeyEnableDebugLog];
    [NSUserDefaults.appUserDefaults synchronize];
}

- (BOOL)hasDeclinedNoContactsView
{
    return [self boolForKey:OWSPreferencesKeyHasDeclinedNoContactsView defaultValue:NO];
}

- (void)setHasDeclinedNoContactsView:(BOOL)value
{
    [self setBool:value forKey:OWSPreferencesKeyHasDeclinedNoContactsView];
}

- (BOOL)hasGeneratedThumbnails
{
    return [self boolForKey:OWSPreferencesKeyHasGeneratedThumbnails defaultValue:NO];
}

- (void)setHasGeneratedThumbnails:(BOOL)value
{
    [self setBool:value forKey:OWSPreferencesKeyHasGeneratedThumbnails];
}

- (void)setIOSUpgradeNagDate:(NSDate *)value
{
    [self setDate:value forKey:OWSPreferencesKeyIOSUpgradeNagDate];
}

- (nullable NSDate *)iOSUpgradeNagDate
{
    return [self dateForKey:OWSPreferencesKeyIOSUpgradeNagDate];
}

- (BOOL)shouldShowUnidentifiedDeliveryIndicators
{
    return [self boolForKey:OWSPreferencesKeyShouldShowUnidentifiedDeliveryIndicators defaultValue:NO];
}

- (BOOL)shouldShowUnidentifiedDeliveryIndicatorsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.keyValueStore getBool:OWSPreferencesKeyShouldShowUnidentifiedDeliveryIndicators
                          defaultValue:NO
                           transaction:transaction];
}

- (void)setShouldShowUnidentifiedDeliveryIndicatorsAndSendSyncMessage:(BOOL)value
{
    [self setBool:value forKey:OWSPreferencesKeyShouldShowUnidentifiedDeliveryIndicators];

    [SSKEnvironment.shared.syncManager sendConfigurationSyncMessage];
    [SSKEnvironment.shared.storageServiceManager recordPendingLocalAccountUpdates];
}

- (void)setShouldShowUnidentifiedDeliveryIndicators:(BOOL)value transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.keyValueStore setBool:value key:OWSPreferencesKeyShouldShowUnidentifiedDeliveryIndicators transaction:transaction];
}

- (BOOL)shouldNotifyOfNewAccountsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.keyValueStore getBool:OWSPreferencesKeyShouldNotifyOfNewAccountKey
                          defaultValue:NO
                           transaction:transaction];
}

- (void)setShouldNotifyOfNewAccounts:(BOOL)newValue transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.keyValueStore setBool:newValue key:OWSPreferencesKeyShouldNotifyOfNewAccountKey transaction:transaction];
}

- (CGFloat)cachedDeviceScale
{
    NSNumber *scale = [CurrentAppContext().appUserDefaults objectForKey:OWSPreferencesKeyDeviceScale];

    if (!scale || CurrentAppContext().hasUI) {
        return UIScreen.mainScreen.scale;
    }

    return scale.floatValue;
}

#pragma mark - Calling

#pragma mark CallKit

- (BOOL)isSystemCallLogEnabled
{
    return [self boolForKey:OWSPreferencesKeySystemCallLogEnabled defaultValue:YES];
}

- (void)setIsSystemCallLogEnabled:(BOOL)value
{
    [self setBool:value forKey:OWSPreferencesKeySystemCallLogEnabled];
}

- (BOOL)wasViewOnceTooltipShown
{
    return [self boolForKey:OWSPreferencesKeyWasViewOnceTooltipShown defaultValue:NO];
}

- (void)setWasViewOnceTooltipShown
{
    [self setBool:YES forKey:OWSPreferencesKeyWasViewOnceTooltipShown];
}

- (BOOL)wasGroupCallTooltipShown
{
    return [self boolForKey:OWSPreferencesKeyWasGroupCallTooltipShown defaultValue:NO];
}

- (void)incrementGroupCallTooltipShownCount
{
    NSUInteger currentCount = [self uintForKey:OWSPreferencesKeyWasGroupCallTooltipShownCount defaultValue:0];
    NSUInteger incrementedCount = currentCount + 1;

    // If we have shown the tooltip more than 3 times, don't show it again.
    if (incrementedCount > 3) {
        [self setWasGroupCallTooltipShown];
    } else {
        [self setUInt:incrementedCount forKey:OWSPreferencesKeyWasGroupCallTooltipShownCount];
    }
}

- (void)setWasGroupCallTooltipShown
{
    [self setBool:YES forKey:OWSPreferencesKeyWasGroupCallTooltipShown];
}

- (BOOL)wasBlurTooltipShown
{
    return [self boolForKey:OWSPreferencesKeyWasBlurTooltipShown defaultValue:NO];
}

- (void)setWasBlurTooltipShown
{
    [self setBool:YES forKey:OWSPreferencesKeyWasBlurTooltipShown];
}

- (BOOL)wasDeleteForEveryoneConfirmationShown
{
    return [self boolForKey:OWSPreferencesKeyWasDeleteForEveryoneConfirmationShown defaultValue:NO];
}

- (void)setWasDeleteForEveryoneConfirmationShown
{
    [self setBool:YES forKey:OWSPreferencesKeyWasDeleteForEveryoneConfirmationShown];
}

#pragma mark direct call connectivity (non-TURN)

// Allow callers to connect directly, when desirable, vs. enforcing TURN only proxy connectivity

- (BOOL)doCallsHideIPAddress
{
    return [self boolForKey:OWSPreferencesKeyCallsHideIPAddress defaultValue:NO];
}

- (void)setDoCallsHideIPAddress:(BOOL)value
{
    [self setBool:value forKey:OWSPreferencesKeyCallsHideIPAddress];
}

#pragma mark Notification Preferences

- (BOOL)soundInForeground
{
    return [self boolForKey:OWSPreferencesKeyPlaySoundInForeground defaultValue:YES];
}

- (void)setSoundInForeground:(BOOL)value
{
    [self setBool:value forKey:OWSPreferencesKeyPlaySoundInForeground];
}

- (void)setNotificationPreviewType:(NotificationType)value
{
    [self setUInt:(NSUInteger)value forKey:OWSPreferencesKeyNotificationPreviewType];

    self.notificationPreviewTypeCache = @(value);
}

- (NotificationType)notificationPreviewType
{
    NSNumber *_Nullable cachedValue = self.notificationPreviewTypeCache;
    if (cachedValue != nil) {
        return (NotificationType)cachedValue.unsignedIntegerValue;
    }

    NotificationType result = (NotificationType)[self uintForKey:OWSPreferencesKeyNotificationPreviewType
                                                    defaultValue:(NSUInteger)NotificationNamePreview];
    self.notificationPreviewTypeCache = @(result);
    return result;
}

- (NSString *)nameForNotificationPreviewType:(NotificationType)notificationType
{
    switch (notificationType) {
        case NotificationNamePreview:
            return OWSLocalizedString(@"NOTIFICATIONS_SENDER_AND_MESSAGE", nil);
        case NotificationNameNoPreview:
            return OWSLocalizedString(@"NOTIFICATIONS_SENDER_ONLY", nil);
        case NotificationNoNameNoPreview:
            return OWSLocalizedString(@"NOTIFICATIONS_NONE", nil);
        default:
            OWSLogWarn(@"Undefined NotificationType in Settings");
            return @"";
    }
}

#pragma mark - Push Tokens

- (void)setPushToken:(NSString *)value
{
    [self setString:value forKey:OWSPreferencesKeyLastRecordedPushToken];
}

- (nullable NSString *)getPushToken
{
    return [self stringForKey:OWSPreferencesKeyLastRecordedPushToken];
}

- (void)setVoipToken:(nullable NSString *)value
{
    [self setString:value forKey:OWSPreferencesKeyLastRecordedVoipToken];
}

- (nullable NSString *)getVoipToken
{
    return [self stringForKey:OWSPreferencesKeyLastRecordedVoipToken];
}

- (void)unsetRecordedAPNSTokens
{
    OWSLogWarn(@"Forgetting recorded APNS tokens");

    [self removeValueForKey:OWSPreferencesKeyLastRecordedPushToken];
    [self removeValueForKey:OWSPreferencesKeyLastRecordedVoipToken];
}

@end

NS_ASSUME_NONNULL_END
