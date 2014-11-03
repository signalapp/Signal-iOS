#import "PreferencesUtil.h"
#import "CryptoTools.h"
#import "Constraints.h"
#import "PhoneNumber.h"
#import "Util.h"

#import "NotificationManifest.h"

#define CALL_STREAM_DES_BUFFER_LEVEL_KEY @"CallStreamDesiredBufferLevel"

#define PHONE_DIRECTORY_BLOOM_FILTER_HASH_COUNT_KEY @"Directory Bloom Hash Count"
#define PHONE_DIRECTORY_BLOOM_FILTER_DATA_KEY @"Directory Bloom Data"
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

#define kSignalVersionKey @"SignalUpdateVersionKey"

@implementation PropertyListPreferences (PropertyUtil)

-(PhoneNumberDirectoryFilter*) tryGetSavedPhoneNumberDirectory {
    NSUInteger hashCount = [[self tryGetValueForKey:PHONE_DIRECTORY_BLOOM_FILTER_HASH_COUNT_KEY] unsignedIntegerValue];
    NSData* data = [self tryGetValueForKey:PHONE_DIRECTORY_BLOOM_FILTER_DATA_KEY];
    NSDate* expiration = [self tryGetValueForKey:PHONE_DIRECTORY_EXPIRATION];
    if (hashCount == 0 || data.length == 0 || expiration == nil) return nil;
    BloomFilter* bloomFilter = [[BloomFilter alloc] initWithHashCount:hashCount andData:data];
    return [PhoneNumberDirectoryFilter phoneNumberDirectoryFilterWithBloomFilter:bloomFilter
                                                               andExpirationDate:expiration];
}
-(void) setSavedPhoneNumberDirectory:(PhoneNumberDirectoryFilter*)phoneNumberDirectoryFilter {
    [self setValueForKey:PHONE_DIRECTORY_BLOOM_FILTER_DATA_KEY toValue:nil];
    [self setValueForKey:PHONE_DIRECTORY_BLOOM_FILTER_HASH_COUNT_KEY toValue:nil];
    [self setValueForKey:PHONE_DIRECTORY_EXPIRATION toValue:nil];
    if (phoneNumberDirectoryFilter == nil) return;
    
    NSData* data = [[phoneNumberDirectoryFilter bloomFilter] data];
    NSNumber* hashCount = @([[phoneNumberDirectoryFilter bloomFilter] hashCount]);
    NSDate* expiry = phoneNumberDirectoryFilter.getExpirationDate;
    [self setValueForKey:PHONE_DIRECTORY_BLOOM_FILTER_DATA_KEY toValue:data];
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

-(NSString*)setAndGetCurrentVersion{
    NSString *lastVersion = self.lastRanVersion;
    
    [NSUserDefaults.standardUserDefaults setObject:[NSString stringWithFormat:@"%@", NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]]
                                            forKey:kSignalVersionKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    return lastVersion;
}

@end
