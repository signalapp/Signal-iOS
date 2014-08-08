#import <Foundation/Foundation.h>
#import "PhoneNumberDirectoryFilter.h"
#import "PropertyListPreferences.h"
#import "CallLogViewController.h"
#import "Zid.h"

@class PhoneNumber;

@interface PropertyListPreferences (PropertyUtil)

-(PhoneNumberDirectoryFilter*) tryGetSavedPhoneNumberDirectory;
-(void) setSavedPhoneNumberDirectory:(PhoneNumberDirectoryFilter*)phoneNumberDirectoryFilter;
-(NSTimeInterval) getCachedOrDefaultDesiredBufferDepth;
-(void) setCachedDesiredBufferDepth:(double)value;

-(BOOL) getFreshInstallTutorialsEnabled;
-(BOOL) getContactImagesEnabled;
-(BOOL) getAutocorrectEnabled;
-(BOOL) getHistoryLogEnabled;

-(void) setFreshInstallTutorialsEnabled:(BOOL)enabled;
-(void) setContactImagesEnabled:(BOOL)enabled;
-(void) setAutocorrectEnabled:(BOOL)enabled;
-(void) setHistoryLogEnabled:(BOOL)enabled;
-(BOOL) encounteredRevokedPushPermission;
-(void) setRevokedPushPermission:(BOOL)revoked;

-(BOOL)loggingIsEnabled;
-(void)setLoggingEnabled:(BOOL)flag;

-(NSString*)lastRanVersion;
-(NSString*)setAndGetCurrentVersion;

@end
