//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSPreferences.h"
#import <SignalServiceKit/NSUserDefaults+OWS.h>
#import <SignalServiceKit/TSStorageHeaders.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSPreferencesSignalDatabaseCollection = @"SignalPreferences";

NSString *const OWSPreferencesKeyScreenSecurity = @"Screen Security Key";
NSString *const OWSPreferencesKeyEnableDebugLog = @"Debugging Log Enabled Key";
NSString *const OWSPreferencesKeyNotificationPreviewType = @"Notification Preview Type Key";
NSString *const OWSPreferencesKeyHasSentAMessage = @"User has sent a message";
NSString *const OWSPreferencesKeyHasArchivedAMessage = @"User archived a message";
NSString *const OWSPreferencesKeyPlaySoundInForeground = @"NotificationSoundInForeground";
NSString *const OWSPreferencesKeyLastRecordedPushToken = @"LastRecordedPushToken";
NSString *const OWSPreferencesKeyLastRecordedVoipToken = @"LastRecordedVoipToken";
NSString *const OWSPreferencesKeyCallKitEnabled = @"CallKitEnabled";
NSString *const OWSPreferencesKeyCallKitPrivacyEnabled = @"CallKitPrivacyEnabled";
NSString *const OWSPreferencesKeyCallsHideIPAddress = @"CallsHideIPAddress";
NSString *const OWSPreferencesKeyHasDeclinedNoContactsView = @"hasDeclinedNoContactsView";
NSString *const OWSPreferencesKeyIOSUpgradeNagVersion = @"iOSUpgradeNagVersion";
NSString *const OWSPreferencesKey_IsReadyForAppExtensions = @"isReadyForAppExtensions";

@implementation OWSPreferences

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    return self;
}

#pragma mark - Helpers

- (void)clear
{
    [NSUserDefaults removeAll];
}

- (nullable id)tryGetValueForKey:(NSString *)key
{
    ows_require(key != nil);
    return [TSStorageManager.sharedManager objectForKey:key inCollection:OWSPreferencesSignalDatabaseCollection];
}

- (void)setValueForKey:(NSString *)key toValue:(nullable id)value
{
    ows_require(key != nil);

    [TSStorageManager.sharedManager setObject:value forKey:key inCollection:OWSPreferencesSignalDatabaseCollection];
}

#pragma mark - Specific Preferences

+ (BOOL)isReadyForAppExtensions
{
    NSNumber *preference = [NSUserDefaults.appUserDefaults objectForKey:OWSPreferencesKey_IsReadyForAppExtensions];

    if (preference) {
        return [preference boolValue];
    } else {
        return NO;
    }
}

+ (void)setIsReadyForAppExtensions:(BOOL)value
{
    [NSUserDefaults.appUserDefaults setObject:@(value) forKey:OWSPreferencesKey_IsReadyForAppExtensions];
    [NSUserDefaults.appUserDefaults synchronize];
}

- (BOOL)screenSecurityIsEnabled
{
    NSNumber *preference = [self tryGetValueForKey:OWSPreferencesKeyScreenSecurity];
    return preference ? [preference boolValue] : YES;
}

- (void)setScreenSecurity:(BOOL)flag
{
    [self setValueForKey:OWSPreferencesKeyScreenSecurity toValue:@(flag)];
}

- (BOOL)getHasSentAMessage
{
    NSNumber *preference = [self tryGetValueForKey:OWSPreferencesKeyHasSentAMessage];
    if (preference) {
        return [preference boolValue];
    } else {
        return NO;
    }
}

- (BOOL)getHasArchivedAMessage
{
    NSNumber *preference = [self tryGetValueForKey:OWSPreferencesKeyHasArchivedAMessage];
    if (preference) {
        return [preference boolValue];
    } else {
        return NO;
    }
}

+ (BOOL)isLoggingEnabled
{
    NSNumber *preference = [NSUserDefaults.appUserDefaults objectForKey:OWSPreferencesKeyEnableDebugLog];

    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}

+ (void)setIsLoggingEnabled:(BOOL)flag
{
    // Logging preferences are stored in UserDefaults instead of the database, so that we can (optionally) start
    // logging before the database is initialized. This is important because sometimes there are problems *with* the
    // database initialization, and without logging it would be hard to track down.
    [NSUserDefaults.appUserDefaults setObject:@(flag) forKey:OWSPreferencesKeyEnableDebugLog];
    [NSUserDefaults.appUserDefaults synchronize];
}

- (void)setHasSentAMessage:(BOOL)enabled
{
    [self setValueForKey:OWSPreferencesKeyHasSentAMessage toValue:@(enabled)];
}

- (void)setHasArchivedAMessage:(BOOL)enabled
{
    [self setValueForKey:OWSPreferencesKeyHasArchivedAMessage toValue:@(enabled)];
}

- (BOOL)hasDeclinedNoContactsView
{
    NSNumber *preference = [self tryGetValueForKey:OWSPreferencesKeyHasDeclinedNoContactsView];
    // Default to NO.
    return preference ? [preference boolValue] : NO;
}

- (void)setHasDeclinedNoContactsView:(BOOL)value
{
    [self setValueForKey:OWSPreferencesKeyHasDeclinedNoContactsView toValue:@(value)];
}

- (void)setIOSUpgradeNagVersion:(NSString *)value
{
    [self setValueForKey:OWSPreferencesKeyIOSUpgradeNagVersion toValue:value];
}

- (nullable NSString *)iOSUpgradeNagVersion
{
    return [self tryGetValueForKey:OWSPreferencesKeyIOSUpgradeNagVersion];
}

#pragma mark - Calling

#pragma mark CallKit

- (BOOL)isCallKitEnabled
{
    NSNumber *preference = [self tryGetValueForKey:OWSPreferencesKeyCallKitEnabled];
    return preference ? [preference boolValue] : YES;
}

- (void)setIsCallKitEnabled:(BOOL)flag
{
    [self setValueForKey:OWSPreferencesKeyCallKitEnabled toValue:@(flag)];
}

- (BOOL)isCallKitEnabledSet
{
    NSNumber *preference = [self tryGetValueForKey:OWSPreferencesKeyCallKitEnabled];
    return preference != nil;
}

- (BOOL)isCallKitPrivacyEnabled
{
    NSNumber *preference = [self tryGetValueForKey:OWSPreferencesKeyCallKitPrivacyEnabled];
    return preference ? [preference boolValue] : YES;
}

- (void)setIsCallKitPrivacyEnabled:(BOOL)flag
{
    [self setValueForKey:OWSPreferencesKeyCallKitPrivacyEnabled toValue:@(flag)];
}

- (BOOL)isCallKitPrivacySet
{
    NSNumber *preference = [self tryGetValueForKey:OWSPreferencesKeyCallKitPrivacyEnabled];
    return preference != nil;
}

#pragma mark direct call connectivity (non-TURN)

// Allow callers to connect directly, when desirable, vs. enforcing TURN only proxy connectivity

- (BOOL)doCallsHideIPAddress
{
    NSNumber *preference = [self tryGetValueForKey:OWSPreferencesKeyCallsHideIPAddress];
    return preference ? [preference boolValue] : NO;
}

- (void)setDoCallsHideIPAddress:(BOOL)flag
{
    [self setValueForKey:OWSPreferencesKeyCallsHideIPAddress toValue:@(flag)];
}

#pragma mark Notification Preferences

- (BOOL)soundInForeground
{
    NSNumber *preference = [self tryGetValueForKey:OWSPreferencesKeyPlaySoundInForeground];
    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}

- (void)setSoundInForeground:(BOOL)enabled
{
    [self setValueForKey:OWSPreferencesKeyPlaySoundInForeground toValue:@(enabled)];
}

- (void)setNotificationPreviewType:(NotificationType)type
{
    [self setValueForKey:OWSPreferencesKeyNotificationPreviewType toValue:@(type)];
}

- (NotificationType)notificationPreviewType
{
    NSNumber *preference = [self tryGetValueForKey:OWSPreferencesKeyNotificationPreviewType];

    if (preference) {
        return [preference unsignedIntegerValue];
    } else {
        return NotificationNamePreview;
    }
}

- (NSString *)nameForNotificationPreviewType:(NotificationType)notificationType
{
    switch (notificationType) {
        case NotificationNamePreview:
            return NSLocalizedString(@"NOTIFICATIONS_SENDER_AND_MESSAGE", nil);
        case NotificationNameNoPreview:
            return NSLocalizedString(@"NOTIFICATIONS_SENDER_ONLY", nil);
        case NotificationNoNameNoPreview:
            return NSLocalizedString(@"NOTIFICATIONS_NONE", nil);
        default:
            DDLogWarn(@"Undefined NotificationType in Settings");
            return @"";
    }
}

#pragma mark - Push Tokens

- (void)setPushToken:(NSString *)value
{
    [self setValueForKey:OWSPreferencesKeyLastRecordedPushToken toValue:value];
}

- (nullable NSString *)getPushToken
{
    return [self tryGetValueForKey:OWSPreferencesKeyLastRecordedPushToken];
}

- (void)setVoipToken:(NSString *)value
{
    [self setValueForKey:OWSPreferencesKeyLastRecordedVoipToken toValue:value];
}

- (nullable NSString *)getVoipToken
{
    return [self tryGetValueForKey:OWSPreferencesKeyLastRecordedVoipToken];
}

- (void)unsetRecordedAPNSTokens
{
    DDLogWarn(@"%@ Forgetting recorded APNS tokens", self.tag);
    [self setValueForKey:OWSPreferencesKeyLastRecordedPushToken toValue:nil];
    [self setValueForKey:OWSPreferencesKeyLastRecordedVoipToken toValue:nil];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
