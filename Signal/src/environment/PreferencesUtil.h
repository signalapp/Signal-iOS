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

-(PhoneNumberDirectoryFilter*) tryGetSavedPhoneNumberDirectory;
-(void) setSavedPhoneNumberDirectory:(PhoneNumberDirectoryFilter*)phoneNumberDirectoryFilter;
-(NSTimeInterval) getCachedOrDefaultDesiredBufferDepth;
-(void) setCachedDesiredBufferDepth:(double)value;

- (BOOL) getHasSentAMessage;
- (void) setHasSentAMessage:(BOOL)enabled;

- (BOOL) getHasArchivedAMessage;
- (void) setHasArchivedAMessage:(BOOL)enabled;

@property (nonatomic, readwrite, assign, getter = loggingIsEnabled) BOOL loggingEnabled;
@property (nonatomic, readwrite, assign, getter = screenSecurityIsEnabled) BOOL screenSecurity;
@property (nonatomic, readwrite, assign) NotificationType notificationPreviewType;
@property (nonatomic, readwrite, assign) TSImageQuality imageUploadQuality;

-(NSString*)lastRanVersion;
-(NSString*)setAndGetCurrentVersion;


@end
