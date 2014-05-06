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
-(int64_t) getAndIncrementOneTimeCounter;
-(PhoneNumber*) forceGetLocalNumber;
-(PhoneNumber*)tryGetLocalNumber;
-(void) setLocalNumberTo:(PhoneNumber*)localNumber;
-(Zid*) getOrGenerateZid;
-(NSString*) getOrGenerateSavedPassword;
-(NSData*) getOrGenerateSignalingMacKey;
-(NSData*) getOrGenerateSignalingCipherKey;
-(NSData*) getOrGenerateSignalingExtraKey;
-(void) setSettingsRowExpandedPrefs:(NSArray *)prefs;
-(NSArray *) getOrGenerateSettingsRowExpandedPrefs;
-(NSArray *) getAvailableDateFormats;

-(BOOL) getFreshInstallTutorialsEnabled;
-(BOOL) getContactImagesEnabled;
-(BOOL) getAutocorrectEnabled;
-(BOOL) getHistoryLogEnabled;
-(BOOL) getAnonymousFeedbackEnabled;
-(BOOL)	getIsRegistered;
-(NSString *) getDateFormat;

-(void) setDateFormat:(NSString *)format;
-(void) setFreshInstallTutorialsEnabled:(BOOL)enabled;
-(void) setContactImagesEnabled:(BOOL)enabled;
-(void) setAutocorrectEnabled:(BOOL)enabled;
-(void) setHistoryLogEnabled:(BOOL)enabled;
-(void) setAnonymousFeedbackEnabled:(BOOL)enabled;
-(void) setIsRegistered:(BOOL)registered;

-(NSString *)getDateFormatKey;

@end
