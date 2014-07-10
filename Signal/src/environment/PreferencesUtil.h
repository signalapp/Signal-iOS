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
-(void) setSettingsRowExpandedPrefs:(NSArray *)prefs;
-(NSArray *) getOrGenerateSettingsRowExpandedPrefs;
-(NSArray *) getAvailableDateFormats;

-(BOOL) getFreshInstallTutorialsEnabled;
-(BOOL) getContactImagesEnabled;
-(BOOL) getAutocorrectEnabled;
-(BOOL) getHistoryLogEnabled;
-(BOOL) getAnonymousFeedbackEnabled;
-(NSString *) getDateFormat;

-(void) setDateFormat:(NSString *)format;
-(void) setFreshInstallTutorialsEnabled:(BOOL)enabled;
-(void) setContactImagesEnabled:(BOOL)enabled;
-(void) setAutocorrectEnabled:(BOOL)enabled;
-(void) setHistoryLogEnabled:(BOOL)enabled;
-(void) setAnonymousFeedbackEnabled:(BOOL)enabled;

-(NSString *)getDateFormatKey;

@end
