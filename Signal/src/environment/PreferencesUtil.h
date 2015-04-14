#import <Foundation/Foundation.h>
#import "PhoneNumberDirectoryFilter.h"
#import "PropertyListPreferences.h"
#import "Zid.h"

typedef NS_ENUM(NSUInteger, NotificationType) {
    NotificationNoNameNoPreview,
    NotificationNameNoPreview,
    NotificationNamePreview,
};

typedef NS_ENUM(NSUInteger, TSImageQuality) {
    TSImageQualityUncropped = 1,
    TSImageQualityHigh      = 2,
    TSImageQualityMedium    = 3,
    TSImageQualityLow       = 4
};

@class PhoneNumber;

@interface PropertyListPreferences (PropertyUtil)

- (PhoneNumberDirectoryFilter*) tryGetSavedPhoneNumberDirectory;
- (void) setSavedPhoneNumberDirectory:(PhoneNumberDirectoryFilter*)phoneNumberDirectoryFilter;
- (NSTimeInterval) getCachedOrDefaultDesiredBufferDepth;
- (void) setCachedDesiredBufferDepth:(double)value;

- (BOOL) getHasSentAMessage;
- (void) setHasSentAMessage:(BOOL)enabled;

- (BOOL) getHasArchivedAMessage;
- (void) setHasArchivedAMessage:(BOOL)enabled;

- (BOOL)loggingIsEnabled;
- (void)setLoggingEnabled:(BOOL)flag;

- (BOOL)screenSecurityIsEnabled;
- (void)setScreenSecurity:(BOOL)flag;

- (NotificationType)notificationPreviewType;
- (void)setNotificationPreviewType:(NotificationType)type;
- (NSString*)nameForNotificationPreviewType:(NotificationType)notificationType;

- (BOOL)soundInForeground;
- (void)setSoundInForeground:(BOOL)enabled;

- (TSImageQuality)imageUploadQuality;
- (void)setImageUploadQuality:(TSImageQuality)quality;

- (NSString*)lastRanVersion;
- (NSString*)setAndGetCurrentVersion;


@end
