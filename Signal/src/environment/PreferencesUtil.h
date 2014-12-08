#import <Foundation/Foundation.h>
#import "PhoneNumberDirectoryFilter.h"
#import "PropertyListPreferences.h"
#import "Zid.h"

typedef NS_ENUM(NSUInteger, NotificationType) {
    NotificationNoNameNoPreview,
    NotificationNameNoPreview,
    NotificationNamePreview,
};

@class PhoneNumber;

@interface PropertyListPreferences (PropertyUtil)

-(PhoneNumberDirectoryFilter*) tryGetSavedPhoneNumberDirectory;
-(void) setSavedPhoneNumberDirectory:(PhoneNumberDirectoryFilter*)phoneNumberDirectoryFilter;
-(NSTimeInterval) getCachedOrDefaultDesiredBufferDepth;
-(void) setCachedDesiredBufferDepth:(double)value;

-(BOOL)loggingIsEnabled;
-(void)setLoggingEnabled:(BOOL)flag;

-(BOOL)screenSecurityIsEnabled;
-(void)setScreenSecurity:(BOOL)flag;

-(NotificationType)notificationPreviewType;
-(void)setNotificationPreviewType:(NotificationType)type;

-(NSString*)lastRanVersion;
-(NSString*)setAndGetCurrentVersion;

@end
