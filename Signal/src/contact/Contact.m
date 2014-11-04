#import "Contact.h"
#import "Util.h"
#import "Environment.h"
#import "PreferencesUtil.h"

static NSString* const DEFAULTS_KEY_CONTACT = @"DefaultsKeyContact";
static NSString* const DEFAULTS_KEY_PHONE_NUMBER = @"DefaultsKeyPhoneNumber";
static NSString* const DEFAULTS_KEY_CALL_TYPE = @"DefaultsKeycallType";
static NSString* const DEFAULTS_KEY_DATE = @"DefaultsKeyDate";

@interface Contact ()

@property (nonatomic, readwrite) NSString* firstName;
@property (nonatomic, readwrite) NSString* lastName;
@property (nonatomic, readwrite) NSString* fullName;
@property (nonatomic, readwrite) NSArray* parsedPhoneNumbers;
@property (nonatomic, readwrite) NSArray* userTextPhoneNumbers;
@property (nonatomic, readwrite) NSArray* emails;
@property (nonatomic, readwrite) UIImage* image;
@property (nonatomic, readwrite) NSString* notes;
@property (nonatomic, readwrite) ABRecordID recordID;

@end

@implementation Contact

- (instancetype)initWithFirstName:(NSString*)firstName
                      andLastName:(NSString*)lastName
          andUserTextPhoneNumbers:(NSArray*)phoneNumbers
                        andEmails:(NSArray*)emails
                     andContactID:(ABRecordID)record {
    
    if (self = [super init]) {
        self.firstName = firstName;
        self.lastName = lastName;
        self.userTextPhoneNumbers = phoneNumbers;
        self.emails = emails;
        self.recordID = record;
        
        NSMutableArray* parsedPhoneNumbers = [[NSMutableArray alloc] init];
        
        for (NSString* phoneNumberString in phoneNumbers) {
            PhoneNumber* phoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumberString];
            if (phoneNumber) {
                [parsedPhoneNumbers addObject:phoneNumber];
            }
        }
        
        self.parsedPhoneNumbers = parsedPhoneNumbers;
    }
    
    return self;
}

- (instancetype)initWithFirstName:(NSString*)firstName
                      andLastName:(NSString*)lastName
          andUserTextPhoneNumbers:(NSArray*)numbers
                        andEmails:(NSArray*)emails
                         andImage:(UIImage*)image
                     andContactID:(ABRecordID)record
                   andIsFavourite:(BOOL)isFavourite
                         andNotes:(NSString*)notes {
    
    self = [self initWithFirstName:firstName
                       andLastName:lastName
           andUserTextPhoneNumbers:numbers
                         andEmails:emails
                      andContactID:record];
    
    if (self) {
        self.isFavourite = isFavourite;
        self.image = image;
        self.notes = notes;
    }
    
    return self;
}

- (void)updateFullName {
	NSMutableString* fullName = [[NSMutableString alloc] init];
	if (self.firstName) [fullName appendString:self.firstName];
	if (self.lastName) [fullName appendString:[NSString stringWithFormat:@" %@",self.lastName]];
    [self setFullName:fullName];
}

- (void)setFirstName:(NSString*)firstName {
    _firstName = firstName;
    [self updateFullName];
}

- (void)setLastName:(NSString*)lastName {
    _lastName = lastName;
    [self updateFullName];
}

- (NSString*)description {
    return [NSString stringWithFormat:@"%@ %@: %@", self.firstName, self.lastName, self.userTextPhoneNumbers];
}

- (UIImage*)image {
	if (Environment.preferences.getContactImagesEnabled) {
		return self.image;
	} else {
		return nil;
	}
}

@end
