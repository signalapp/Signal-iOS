//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "PropertyListPreferences.h"
#import "Constraints.h"
#import "TSStorageHeaders.h"
#import <SignalServiceKit/TSPrivacyPreferences.h>

NS_ASSUME_NONNULL_BEGIN

double const PropertyListPreferencesDefaultCallStreamDESBufferLevel = 0.5;
NSString *const PropertyListPreferencesSignalDatabaseCollection = @"SignalPreferences";

NSString *const PropertyListPreferencesKeyCallStreamDESBufferLevel = @"CallStreamDesiredBufferLevel";
NSString *const PropertyListPreferencesKeyScreenSecurity = @"Screen Security Key";
NSString *const PropertyListPreferencesKeyEnableDebugLog = @"Debugging Log Enabled Key";
NSString *const PropertyListPreferencesKeyNotificationPreviewType = @"Notification Preview Type Key";
NSString *const PropertyListPreferencesKeyHasSentAMessage = @"User has sent a message";
NSString *const PropertyListPreferencesKeyHasArchivedAMessage = @"User archived a message";
NSString *const PropertyListPreferencesKeyLastRunSignalVersion = @"SignalUpdateVersionKey";
NSString *const PropertyListPreferencesKeyPlaySoundInForeground = @"NotificationSoundInForeground";
NSString *const PropertyListPreferencesKeyHasRegisteredVoipPush = @"VOIPPushEnabled";
NSString *const PropertyListPreferencesKeyLastRecordedPushToken = @"LastRecordedPushToken";
NSString *const PropertyListPreferencesKeyLastRecordedVoipToken = @"LastRecordedVoipToken";
NSString *const PropertyListPreferencesKeyWebRTCEnabled = @"WebRTCEnabled";
NSString *const PropertyListPreferencesKeyCallKitEnabled = @"CallKitEnabled";

@implementation PropertyListPreferences

#pragma mark - Helpers

- (void)clear {
    @synchronized(self) {
        NSString *appDomain = NSBundle.mainBundle.bundleIdentifier;
        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:appDomain];
    }
}

- (nullable id)tryGetValueForKey:(NSString *)key
{
    ows_require(key != nil);
    return
        [TSStorageManager.sharedManager objectForKey:key inCollection:PropertyListPreferencesSignalDatabaseCollection];
}

- (void)setValueForKey:(NSString *)key toValue:(nullable id)value
{
    ows_require(key != nil);

    [TSStorageManager.sharedManager setObject:value
                                       forKey:key
                                 inCollection:PropertyListPreferencesSignalDatabaseCollection];
}

- (TSPrivacyPreferences *)tsPrivacyPreferences
{
    return [TSPrivacyPreferences sharedInstance];
}

#pragma mark - Specific Preferences

- (NSTimeInterval)getCachedOrDefaultDesiredBufferDepth
{
    id v = [self tryGetValueForKey:PropertyListPreferencesKeyCallStreamDESBufferLevel];
    if (v == nil)
        return PropertyListPreferencesDefaultCallStreamDESBufferLevel;
    return [v doubleValue];
}

- (void)setCachedDesiredBufferDepth:(double)value
{
    ows_require(value >= 0);
    [self setValueForKey:PropertyListPreferencesKeyCallStreamDESBufferLevel toValue:@(value)];
}

- (BOOL)screenSecurityIsEnabled
{
    NSNumber *preference = [self tryGetValueForKey:PropertyListPreferencesKeyScreenSecurity];
    return preference ? [preference boolValue] : YES;
}

- (BOOL)getHasSentAMessage
{
    NSNumber *preference = [self tryGetValueForKey:PropertyListPreferencesKeyHasSentAMessage];
    if (preference) {
        return [preference boolValue];
    } else {
        return NO;
    }
}

- (BOOL)getHasArchivedAMessage
{
    NSNumber *preference = [self tryGetValueForKey:PropertyListPreferencesKeyHasArchivedAMessage];
    if (preference) {
        return [preference boolValue];
    } else {
        return NO;
    }
}

- (BOOL)hasRegisteredVOIPPush
{
    NSNumber *preference = [self tryGetValueForKey:PropertyListPreferencesKeyHasRegisteredVoipPush];
    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}

- (TSImageQuality)imageUploadQuality
{
    // always return average image quality
    return TSImageQualityMedium;
}

- (void)setScreenSecurity:(BOOL)flag
{
    [self setValueForKey:PropertyListPreferencesKeyScreenSecurity toValue:@(flag)];
}


- (void)setHasRegisteredVOIPPush:(BOOL)enabled
{
    [self setValueForKey:PropertyListPreferencesKeyHasRegisteredVoipPush toValue:@(enabled)];
}

- (BOOL)loggingIsEnabled
{
    NSNumber *preference = [NSUserDefaults.standardUserDefaults objectForKey:PropertyListPreferencesKeyEnableDebugLog];

    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}

- (void)setLoggingEnabled:(BOOL)flag
{
    [NSUserDefaults.standardUserDefaults setObject:@(flag) forKey:PropertyListPreferencesKeyEnableDebugLog];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (nullable NSString *)lastRanVersion
{
    return [NSUserDefaults.standardUserDefaults objectForKey:PropertyListPreferencesKeyLastRunSignalVersion];
}

- (void)setHasSentAMessage:(BOOL)enabled
{
    [self setValueForKey:PropertyListPreferencesKeyHasSentAMessage toValue:@(enabled)];
}

- (void)setHasArchivedAMessage:(BOOL)enabled
{
    [self setValueForKey:PropertyListPreferencesKeyHasArchivedAMessage toValue:@(enabled)];
}

- (NSString *)setAndGetCurrentVersion
{
    NSString *currentVersion =
        [NSString stringWithFormat:@"%@", NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]];
    [NSUserDefaults.standardUserDefaults setObject:currentVersion
                                            forKey:PropertyListPreferencesKeyLastRunSignalVersion];
    [NSUserDefaults.standardUserDefaults synchronize];
    return currentVersion;
}

#pragma mark - Calling

#pragma mark WebRTC

- (BOOL)isWebRTCEnabled
{
    NSNumber *preference = [self tryGetValueForKey:PropertyListPreferencesKeyWebRTCEnabled];
    // Currently default to NO.
    return preference ? [preference boolValue] : NO;
}

- (void)setIsWebRTCEnabled:(BOOL)flag
{
    [self setValueForKey:PropertyListPreferencesKeyWebRTCEnabled toValue:@(flag)];
}

#pragma mark CallKit

- (BOOL)isCallKitEnabled
{
    NSNumber *preference = [self tryGetValueForKey:PropertyListPreferencesKeyCallKitEnabled];
    return preference ? [preference boolValue] : YES;
}

- (void)setIsCallKitEnabled:(BOOL)flag
{
    [self setValueForKey:PropertyListPreferencesKeyCallKitEnabled toValue:@(flag)];
}

#pragma mark Notification Preferences

- (BOOL)soundInForeground
{
    NSNumber *preference = [self tryGetValueForKey:PropertyListPreferencesKeyPlaySoundInForeground];
    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}

- (void)setSoundInForeground:(BOOL)enabled
{
    [self setValueForKey:PropertyListPreferencesKeyPlaySoundInForeground toValue:@(enabled)];
}

- (void)setNotificationPreviewType:(NotificationType)type
{
    [self setValueForKey:PropertyListPreferencesKeyNotificationPreviewType toValue:@(type)];
}

- (NotificationType)notificationPreviewType
{
    NSNumber *preference = [self tryGetValueForKey:PropertyListPreferencesKeyNotificationPreviewType];

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

#pragma mark - Block on Identity Change

- (BOOL)shouldBlockOnIdentityChange
{
    return self.tsPrivacyPreferences.shouldBlockOnIdentityChange;
}

- (void)setShouldBlockOnIdentityChange:(BOOL)value
{
    self.tsPrivacyPreferences.shouldBlockOnIdentityChange = value;
    [self.tsPrivacyPreferences save];
}

#pragma mark - Push Tokens

- (void)setPushToken:(NSString *)value
{
    [self setValueForKey:PropertyListPreferencesKeyLastRecordedPushToken toValue:value];
}

- (nullable NSString *)getPushToken
{
    return [self tryGetValueForKey:PropertyListPreferencesKeyLastRecordedPushToken];
}

- (void)setVoipToken:(NSString *)value
{
    [self setValueForKey:PropertyListPreferencesKeyLastRecordedVoipToken toValue:value];
}

- (nullable NSString *)getVoipToken
{
    return [self tryGetValueForKey:PropertyListPreferencesKeyLastRecordedVoipToken];
}

@end

NS_ASSUME_NONNULL_END
