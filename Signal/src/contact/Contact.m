#import "Contact.h"
#import "ContactsManager.h"
#import "TSStorageManager.h"
#import "Environment.h"
#import "TSRecipient.h"

static NSString *const DEFAULTS_KEY_CONTACT = @"DefaultsKeyContact";
static NSString *const DEFAULTS_KEY_PHONE_NUMBER = @"DefaultsKeyPhoneNumber";
static NSString *const DEFAULTS_KEY_CALL_TYPE = @"DefaultsKeycallType";
static NSString *const DEFAULTS_KEY_DATE = @"DefaultsKeyDate";

@implementation Contact

@synthesize firstName, lastName, emails, image, recordID, notes, parsedPhoneNumbers, userTextPhoneNumbers;

+ (Contact*)contactWithFirstName:(NSString*)firstName
                     andLastName:(NSString *)lastName
         andUserTextPhoneNumbers:(NSArray*)phoneNumbers
                       andEmails:(NSArray*)emails
                    andContactID:(ABRecordID)record {

	Contact* contact = [Contact new];
	contact->firstName = firstName;
	contact->lastName = lastName;
	contact->userTextPhoneNumbers = phoneNumbers;
	contact->emails = emails;
	contact->recordID = record;

	NSMutableArray *parsedPhoneNumbers = [NSMutableArray array];

	for (NSString *phoneNumberString in phoneNumbers) {
		PhoneNumber *phoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumberString];
		if (phoneNumber) {
			[parsedPhoneNumbers addObject:phoneNumber];
		}
	}

	contact->parsedPhoneNumbers = parsedPhoneNumbers.copy;

	return contact;
}

+ (Contact*)contactWithFirstName:(NSString*)firstName
                     andLastName:(NSString *)lastName
         andUserTextPhoneNumbers:(NSArray*)numbers
                       andEmails:(NSArray*)emails
                        andImage:(UIImage *)image
                    andContactID:(ABRecordID)record
                        andNotes:(NSString *)notes {
	
	Contact* contact = [Contact contactWithFirstName:firstName
                                         andLastName:lastName
                             andUserTextPhoneNumbers:numbers
                                           andEmails:emails
                                        andContactID:record];

	contact->image = image;
	contact->notes = notes;
	return contact;
}

- (NSString *)fullName {
	NSMutableString *fullName = [NSMutableString string];
	if (firstName) [fullName appendString:firstName];
	if (lastName) {
		[fullName appendString:[NSString stringWithFormat:@" %@",lastName]];
	}
	return fullName;
}

- (NSString *)allPhoneNumbers {
    NSString * allNumbers = @"";
    for (PhoneNumber *number in self.parsedPhoneNumbers) {
        allNumbers = [allNumbers stringByAppendingString:number.toE164];
        allNumbers = [allNumbers stringByAppendingString:@";"];
    }
    return allNumbers;
}

-(NSString *)description {
    return [NSString stringWithFormat:@"%@ %@: %@", firstName, lastName, userTextPhoneNumbers];
}

- (UIImage *)image {
    return image;
}

- (BOOL)isTextSecureContact{
    __block BOOL isRecipient = NO;
    [[TSStorageManager sharedManager].dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        for (PhoneNumber *number in self.parsedPhoneNumbers) {
            if ([TSRecipient recipientWithTextSecureIdentifier:number.toE164 withTransaction:transaction]) {
                isRecipient = YES;
                break;
            }
        }
    }];
    return isRecipient;
}

- (NSArray*)textSecureIdentifiers{
    __block NSMutableArray *identifiers = [NSMutableArray array];
    
    [[TSStorageManager sharedManager].dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        for (PhoneNumber *number in self.parsedPhoneNumbers) {
            if ([TSRecipient recipientWithTextSecureIdentifier:number.toE164 withTransaction:transaction]) {
                [identifiers addObject:number.toE164];
            }
        }
    }];
    return identifiers;
}

- (BOOL)isRedPhoneContact{
    ContactsManager *contactManager = [Environment getCurrent].contactsManager;
    return [contactManager isContactRegisteredWithRedPhone:self];
}

- (NSArray *)redPhoneIdentifiers{
    __block NSMutableArray *identifiers = [NSMutableArray array];
    
    ContactsManager *contactManager = [Environment getCurrent].contactsManager;
    for (PhoneNumber *number in self.parsedPhoneNumbers) {
        if ([contactManager isPhoneNumberRegisteredWithRedPhone:number]) {
            [identifiers addObject:number];
        }
    }
    
    return identifiers;
}

@end
