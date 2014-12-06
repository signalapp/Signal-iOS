#import <Foundation/Foundation.h>
#import "PhoneNumberDirectoryFilter.h"
#import "PropertyListPreferences.h"
#import "Zid.h"

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

-(NSString*)lastRanVersion;
-(NSString*)setAndGetCurrentVersion;

@end
