#import "Constraints.h"
#import "PreferencesUtil.h"

#define CALL_STREAM_DES_BUFFER_LEVEL_KEY @"CallStreamDesiredBufferLevel"


#define DEFAULT_CALL_STREAM_DES_BUFFER_LEVEL 0.5

#define SETTINGS_EXPANDED_ROW_PREF_DICT_KEY @"Settings Expanded Row Pref Dict Key"

#define FRESH_INSTALL_TUTORIALS_ENABLED_KEY @"Fresh Install Tutorials Enabled Key"
#define CONTACT_IMAGES_ENABLED_KEY @"Contact Images Enabled Key"
#define AUTOCORRECT_ENABLED_KEY @"Autocorrect Enabled Key"
#define HISTORY_LOG_ENABLED_KEY @"History Log Enabled Key"
#define PUSH_REVOKED_KEY @"Push Revoked Key"
#define SCREEN_SECURITY_KEY @"Screen Security Key"
#define DEBUG_IS_ENABLED_KEY @"Debugging Log Enabled Key"
#define NOTIFICATION_PREVIEW_TYPE_KEY @"Notification Preview Type Key"
#define IMAGE_UPLOAD_QUALITY_KEY @"Image Upload Quality Key"
#define HAS_SENT_A_MESSAGE_KEY @"User has sent a message"
#define HAS_ARCHIVED_A_MESSAGE_KEY @"User archived a message"
#define kSignalVersionKey @"SignalUpdateVersionKey"
#define PLAY_SOUND_IN_FOREGROUND_KEY @"NotificationSoundInForeground"
#define HAS_REGISTERED_VOIP_PUSH @"VOIPPushEnabled"

@implementation PropertyListPreferences (PropertyUtil)

- (NSTimeInterval)getCachedOrDefaultDesiredBufferDepth {
    id v = [self tryGetValueForKey:CALL_STREAM_DES_BUFFER_LEVEL_KEY];
    if (v == nil)
        return DEFAULT_CALL_STREAM_DES_BUFFER_LEVEL;
    return [v doubleValue];
}
- (void)setCachedDesiredBufferDepth:(double)value {
    ows_require(value >= 0);
    [self setValueForKey:CALL_STREAM_DES_BUFFER_LEVEL_KEY toValue:@(value)];
}

- (BOOL)getFreshInstallTutorialsEnabled {
    NSNumber *preference = [self tryGetValueForKey:FRESH_INSTALL_TUTORIALS_ENABLED_KEY];
    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}
- (BOOL)getContactImagesEnabled {
    NSNumber *preference = [self tryGetValueForKey:CONTACT_IMAGES_ENABLED_KEY];
    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}
- (BOOL)getAutocorrectEnabled {
    NSNumber *preference = [self tryGetValueForKey:AUTOCORRECT_ENABLED_KEY];
    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}
- (BOOL)getHistoryLogEnabled {
    NSNumber *preference = [self tryGetValueForKey:HISTORY_LOG_ENABLED_KEY];
    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}

- (BOOL)loggingIsEnabled {
    NSNumber *preference = [self tryGetValueForKey:DEBUG_IS_ENABLED_KEY];
    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}

- (BOOL)screenSecurityIsEnabled {
    NSNumber *preference = [self tryGetValueForKey:SCREEN_SECURITY_KEY];
    if (preference) {
        return [preference boolValue];
    } else {
        return NO;
    }
}

- (BOOL)getHasSentAMessage {
    NSNumber *preference = [self tryGetValueForKey:HAS_SENT_A_MESSAGE_KEY];
    if (preference) {
        return [preference boolValue];
    } else {
        return NO;
    }
}

- (BOOL)getHasArchivedAMessage {
    NSNumber *preference = [self tryGetValueForKey:HAS_ARCHIVED_A_MESSAGE_KEY];
    if (preference) {
        return [preference boolValue];
    } else {
        return NO;
    }
}

- (BOOL)hasRegisteredVOIPPush {
    NSNumber *preference = [self tryGetValueForKey:HAS_REGISTERED_VOIP_PUSH];
    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}

- (TSImageQuality)imageUploadQuality {
    // always return average image quality
    return TSImageQualityMedium;
}

- (void)setImageUploadQuality:(TSImageQuality)quality {
    [self setValueForKey:IMAGE_UPLOAD_QUALITY_KEY toValue:@(quality)];
}

- (void)setScreenSecurity:(BOOL)flag {
    [self setValueForKey:SCREEN_SECURITY_KEY toValue:@(flag)];
}

- (void)setFreshInstallTutorialsEnabled:(BOOL)enabled {
    [self setValueForKey:FRESH_INSTALL_TUTORIALS_ENABLED_KEY toValue:@(enabled)];
}

- (void)setHasRegisteredVOIPPush:(BOOL)enabled {
    [self setValueForKey:HAS_REGISTERED_VOIP_PUSH toValue:@(enabled)];
}

- (void)setContactImagesEnabled:(BOOL)enabled {
    [self setValueForKey:CONTACT_IMAGES_ENABLED_KEY toValue:@(enabled)];
}
- (void)setAutocorrectEnabled:(BOOL)enabled {
    [self setValueForKey:AUTOCORRECT_ENABLED_KEY toValue:@(enabled)];
}
- (void)setHistoryLogEnabled:(BOOL)enabled {
    [self setValueForKey:HISTORY_LOG_ENABLED_KEY toValue:@(enabled)];
}

- (BOOL)encounteredRevokedPushPermission {
    return [[self tryGetValueForKey:PUSH_REVOKED_KEY] boolValue];
}
- (void)setRevokedPushPermission:(BOOL)revoked {
    [self setValueForKey:PUSH_REVOKED_KEY toValue:@(revoked)];
}

- (void)setLoggingEnabled:(BOOL)flag {
    [self setValueForKey:DEBUG_IS_ENABLED_KEY toValue:@(flag)];
}

- (NSString *)lastRanVersion {
    return [NSUserDefaults.standardUserDefaults objectForKey:kSignalVersionKey];
}

- (void)setHasSentAMessage:(BOOL)enabled {
    [self setValueForKey:HAS_SENT_A_MESSAGE_KEY toValue:@(enabled)];
}

- (void)setHasArchivedAMessage:(BOOL)enabled {
    [self setValueForKey:HAS_ARCHIVED_A_MESSAGE_KEY toValue:@(enabled)];
}

- (NSString *)setAndGetCurrentVersion {
    NSString *currentVersion =
        [NSString stringWithFormat:@"%@", NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]];
    [NSUserDefaults.standardUserDefaults setObject:currentVersion forKey:kSignalVersionKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    return currentVersion;
}

#pragma mark Notification Preferences

- (BOOL)soundInForeground {
    NSNumber *preference = [self tryGetValueForKey:PLAY_SOUND_IN_FOREGROUND_KEY];
    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}

- (void)setSoundInForeground:(BOOL)enabled {
    [self setValueForKey:PLAY_SOUND_IN_FOREGROUND_KEY toValue:@(enabled)];
}

- (void)setNotificationPreviewType:(NotificationType)type {
    [self setValueForKey:NOTIFICATION_PREVIEW_TYPE_KEY toValue:@(type)];
}

- (NotificationType)notificationPreviewType {
    NSNumber *preference = [self tryGetValueForKey:NOTIFICATION_PREVIEW_TYPE_KEY];

    if (preference) {
        return [preference unsignedIntegerValue];
    } else {
        return NotificationNamePreview;
    }
}

- (NSString *)nameForNotificationPreviewType:(NotificationType)notificationType {
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

@end
