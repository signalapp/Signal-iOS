#import "PreferencesUtil.h"
#import "CryptoTools.h"
#import "Constraints.h"
#import "PhoneNumber.h"
#import "Util.h"

#import "NotificationManifest.h"

#define CALL_STREAM_DES_BUFFER_LEVEL_KEY @"CallStreamDesiredBufferLevel"

#define PHONE_DIRECTORY_BLOOM_FILTER_HASH_COUNT_KEY @"Directory Bloom Hash Count"
#define PHONE_DIRECTORY_EXPIRATION @"Directory Expiration"

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

#define BloomFilterCacheName     @"bloomfilter"

@implementation PropertyListPreferences (PropertyUtil)

-(PhoneNumberDirectoryFilter*) tryGetSavedPhoneNumberDirectory {
    NSUInteger hashCount = [[self tryGetValueForKey:PHONE_DIRECTORY_BLOOM_FILTER_HASH_COUNT_KEY] unsignedIntegerValue];
    NSData* data = [self tryRetreiveBloomFilter];
    NSDate* expiration = [self tryGetValueForKey:PHONE_DIRECTORY_EXPIRATION];
    if (hashCount == 0 || data.length == 0 || expiration == nil) return nil;
    BloomFilter* bloomFilter = [BloomFilter bloomFilterWithHashCount:hashCount andData:data];
    return [PhoneNumberDirectoryFilter phoneNumberDirectoryFilterWithBloomFilter:bloomFilter
                                                               andExpirationDate:expiration];
}
-(void) setSavedPhoneNumberDirectory:(PhoneNumberDirectoryFilter*)phoneNumberDirectoryFilter {
    [self storeBloomfilter:nil];
    [self setValueForKey:PHONE_DIRECTORY_BLOOM_FILTER_HASH_COUNT_KEY toValue:nil];
    [self setValueForKey:PHONE_DIRECTORY_EXPIRATION toValue:nil];
    if (phoneNumberDirectoryFilter == nil) return;
    
    NSData* data = [[phoneNumberDirectoryFilter bloomFilter] data];
    NSNumber* hashCount = @([[phoneNumberDirectoryFilter bloomFilter] hashCount]);
    NSDate* expiry = phoneNumberDirectoryFilter.getExpirationDate;
    [self storeBloomfilter:data];
    [self setValueForKey:PHONE_DIRECTORY_BLOOM_FILTER_HASH_COUNT_KEY toValue:hashCount];
    [self setValueForKey:PHONE_DIRECTORY_EXPIRATION toValue:expiry];
    [self sendDirectoryUpdateNotification];
}

-(void) sendDirectoryUpdateNotification{
    [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_DIRECTORY_UPDATE object:nil];
}

-(NSTimeInterval) getCachedOrDefaultDesiredBufferDepth {
    id v = [self tryGetValueForKey:CALL_STREAM_DES_BUFFER_LEVEL_KEY];
    if (v == nil) return DEFAULT_CALL_STREAM_DES_BUFFER_LEVEL;
    return [v doubleValue];
}
-(void) setCachedDesiredBufferDepth:(double)value {
    require(value >= 0);
    [self setValueForKey:CALL_STREAM_DES_BUFFER_LEVEL_KEY toValue:@(value)];
}

-(BOOL) getFreshInstallTutorialsEnabled {
    NSNumber *preference = [self tryGetValueForKey:FRESH_INSTALL_TUTORIALS_ENABLED_KEY];
    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}
-(BOOL) getContactImagesEnabled {
    NSNumber *preference = [self tryGetValueForKey:CONTACT_IMAGES_ENABLED_KEY];
    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}
-(BOOL) getAutocorrectEnabled {
    NSNumber *preference = [self tryGetValueForKey:AUTOCORRECT_ENABLED_KEY];
    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}
-(BOOL) getHistoryLogEnabled {
    NSNumber *preference = [self tryGetValueForKey:HISTORY_LOG_ENABLED_KEY];
    if (preference) {
        return [preference boolValue];
    } else {
        return YES;
    }
}

- (BOOL)loggingIsEnabled{
    NSNumber *preference = [self tryGetValueForKey:DEBUG_IS_ENABLED_KEY];
    if (preference) {
        return [preference boolValue];
    } else{
        return YES;
    }
}

-(BOOL)screenSecurityIsEnabled{
    NSNumber *preference = [self tryGetValueForKey:SCREEN_SECURITY_KEY];
    if (preference) {
        return [preference boolValue];
    } else{
        return NO;
    }
}

- (BOOL) getHasSentAMessage{
    NSNumber *preference = [self tryGetValueForKey:HAS_SENT_A_MESSAGE_KEY];
    if (preference) {
        return [preference boolValue];
    } else{
        return NO;
    }

}

- (BOOL) getHasArchivedAMessage {
    NSNumber *preference = [self tryGetValueForKey:HAS_ARCHIVED_A_MESSAGE_KEY];
    if (preference) {
        return [preference boolValue];
    } else{
        return NO;
    }

}

-(TSImageQuality)imageUploadQuality {
    // always return average image quality
    return TSImageQualityMedium;
}

-(void)setImageUploadQuality:(TSImageQuality)quality {
    [self setValueForKey:IMAGE_UPLOAD_QUALITY_KEY toValue:@(quality)];
}

-(void)setScreenSecurity:(BOOL)flag{
    [self setValueForKey:SCREEN_SECURITY_KEY toValue:@(flag)];
}

-(void) setFreshInstallTutorialsEnabled:(BOOL)enabled {
    [self setValueForKey:FRESH_INSTALL_TUTORIALS_ENABLED_KEY toValue:@(enabled)];
}

-(void) setContactImagesEnabled:(BOOL)enabled {
    [self setValueForKey:CONTACT_IMAGES_ENABLED_KEY toValue:@(enabled)];
}
-(void) setAutocorrectEnabled:(BOOL)enabled {
    [self setValueForKey:AUTOCORRECT_ENABLED_KEY toValue:@(enabled)];
}
-(void) setHistoryLogEnabled:(BOOL)enabled {
    [self setValueForKey:HISTORY_LOG_ENABLED_KEY toValue:@(enabled)];
}

-(BOOL) encounteredRevokedPushPermission{
    return [[self tryGetValueForKey:PUSH_REVOKED_KEY] boolValue];
}
-(void) setRevokedPushPermission:(BOOL)revoked{
    [self setValueForKey:PUSH_REVOKED_KEY toValue:@(revoked)];
}

-(void) setLoggingEnabled:(BOOL)flag{
    [self setValueForKey:DEBUG_IS_ENABLED_KEY toValue:@(flag)];
}

-(NSString*)lastRanVersion{
    return [NSUserDefaults.standardUserDefaults objectForKey:kSignalVersionKey];
}

- (void) setHasSentAMessage:(BOOL)enabled{
    [self setValueForKey:HAS_SENT_A_MESSAGE_KEY toValue:@(enabled)];
}

- (void) setHasArchivedAMessage:(BOOL)enabled{
    [self setValueForKey:HAS_ARCHIVED_A_MESSAGE_KEY toValue:@(enabled)];
}

-(NSString*)setAndGetCurrentVersion{
    NSString *currentVersion = [NSString stringWithFormat:@"%@", NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]];
    [NSUserDefaults.standardUserDefaults setObject:currentVersion forKey:kSignalVersionKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    return currentVersion;
}


#pragma mark Notification Preferences

- (BOOL)soundInForeground {
    NSNumber *preference = [self tryGetValueForKey:PLAY_SOUND_IN_FOREGROUND_KEY];
    if (preference) {
        return [preference boolValue];
    } else{
        return YES;
    }
}

- (void)setSoundInForeground:(BOOL)enabled {
    [self setValueForKey:PLAY_SOUND_IN_FOREGROUND_KEY toValue:@(enabled)];
}

-(void)setNotificationPreviewType:(NotificationType)type
{
    [self setValueForKey:NOTIFICATION_PREVIEW_TYPE_KEY toValue:@(type)];
}

-(NotificationType)notificationPreviewType {
    NSNumber *preference = [self tryGetValueForKey:NOTIFICATION_PREVIEW_TYPE_KEY];
    
    if (preference) {
        return [preference unsignedIntegerValue];
    } else {
        return NotificationNamePreview;
    }
}

- (NSString*)nameForNotificationPreviewType:(NotificationType)notificationType {
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

#pragma mark Bloom filter

- (NSData*)tryRetreiveBloomFilter {
    return [NSData dataWithContentsOfFile:[self bloomfilterPath]];
}

- (void)storeBloomfilter:(NSData*)bloomFilterData {
    if (!bloomFilterData) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError       *error;
        
        if ([fileManager fileExistsAtPath:[self bloomfilterPath]]) {
            [fileManager removeItemAtPath:[self bloomfilterPath] error:&error];
        }
        
        if (error) {
            DDLogError(@"Failed to remove bloomfilter with error: %@", error);
        }
        
        return;
    }
    
    NSError *error;
    [bloomFilterData writeToFile:[self bloomfilterPath] options:NSDataWritingAtomic error:&error];
    if (error) {
        DDLogError(@"Failed to store bloomfilter with error: %@", error);
    }
}

- (NSString*)bloomfilterPath {
    NSFileManager *fm         = [NSFileManager defaultManager];
    NSArray  *cachesDir       = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *bloomFilterPath = [cachesDir  objectAtIndex:0];
    NSError  *error;
    
    if (![fm fileExistsAtPath:bloomFilterPath]) {
        [fm createDirectoryAtPath:bloomFilterPath withIntermediateDirectories:YES attributes:@{} error:&error];
    }

    if (error) {
        DDLogError(@"Failed to create caches directory with error: %@", error.description);
    }
    
    bloomFilterPath = [bloomFilterPath stringByAppendingPathComponent:BloomFilterCacheName];
    
    return bloomFilterPath;
}

@end
