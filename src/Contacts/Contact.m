#import "Contact.h"
#import "PhoneNumber.h"
#import "SignalRecipient.h"
#import "TSStorageManager.h"

@import Contacts;

NS_ASSUME_NONNULL_BEGIN

@implementation Contact

@synthesize fullName = _fullName;
@synthesize comparableNameFirstLast = _comparableNameFirstLast;
@synthesize comparableNameLastFirst = _comparableNameLastFirst;

#if TARGET_OS_IOS
- (instancetype)initWithContactWithFirstName:(nullable NSString *)firstName
                                 andLastName:(nullable NSString *)lastName
                     andUserTextPhoneNumbers:(NSArray *)phoneNumbers
                                    andImage:(nullable UIImage *)image
                                andContactID:(ABRecordID)record
{
    self = [super init];
    if (!self) {
        return self;
    }

    _firstName = firstName;
    _lastName = lastName;
    _uniqueId = [self.class uniqueIdFromABRecordId:record];
    _recordID = record;
    _userTextPhoneNumbers = phoneNumbers;
    _parsedPhoneNumbers = [self.class parsedPhoneNumbersFromUserTextPhoneNumbers:phoneNumbers];
    _image = image;
    // Not using emails for old AB style contacts.
    _emails = [NSMutableArray new];

    return self;
}

- (instancetype)initWithContact:(CNContact *)contact
{
    self = [super init];
    if (!self) {
        return self;
    }

    _cnContact = contact;
    _firstName = contact.givenName;
    _lastName = contact.familyName;
    _uniqueId = contact.identifier;

    NSMutableArray<NSString *> *phoneNumbers = [NSMutableArray new];
    for (CNLabeledValue *phoneNumberField in contact.phoneNumbers) {
        if ([phoneNumberField.value isKindOfClass:[CNPhoneNumber class]]) {
            CNPhoneNumber *phoneNumber = (CNPhoneNumber *)phoneNumberField.value;
            [phoneNumbers addObject:phoneNumber.stringValue];
        }
    }
    _userTextPhoneNumbers = [phoneNumbers copy];
    _parsedPhoneNumbers = [self.class parsedPhoneNumbersFromUserTextPhoneNumbers:phoneNumbers];

    NSMutableArray<NSString *> *emailAddresses = [NSMutableArray new];
    for (CNLabeledValue *emailField in contact.emailAddresses) {
        if ([emailField.value isKindOfClass:[NSString class]]) {
            [emailAddresses addObject:(NSString *)emailField.value];
        }
    }
    _emails = [emailAddresses copy];

    if (contact.thumbnailImageData) {
        _image = [UIImage imageWithData:contact.thumbnailImageData];
    }

    return self;
}

+ (NSString *)uniqueIdFromABRecordId:(ABRecordID)recordId
{
    return [NSString stringWithFormat:@"ABRecordId:%d", recordId];
}

#endif // TARGET_OS_IOS

+ (NSArray<PhoneNumber *> *)parsedPhoneNumbersFromUserTextPhoneNumbers:(NSArray<NSString *> *)userTextPhoneNumbers
{
    NSMutableArray<PhoneNumber *> *parsedPhoneNumbers = [NSMutableArray new];
    for (NSString *phoneNumberString in userTextPhoneNumbers) {
        PhoneNumber *phoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumberString];
        if (phoneNumber) {
            [parsedPhoneNumbers addObject:phoneNumber];
        }
    }
    return [parsedPhoneNumbers copy];
}

- (NSString *)fullName {
    if (_fullName == nil) {
        if (ABPersonGetCompositeNameFormat() == kABPersonCompositeNameFormatFirstNameFirst) {
            _fullName = [self combineLeftName:_firstName withRightName:_lastName usingSeparator:@" "];
        } else {
            _fullName = [self combineLeftName:_lastName withRightName:_firstName usingSeparator:@" "];
        }
    }
    
    return _fullName;
}

- (NSString *)comparableNameFirstLast {
    if (_comparableNameFirstLast == nil) {
        // Combine the two names with a tab separator, which has a lower ascii code than space, so that first names
        // that contain a space ("Mary Jo\tCatlett") will sort after those that do not ("Mary\tOliver")
        _comparableNameFirstLast = [self combineLeftName:_firstName withRightName:_lastName usingSeparator:@"\t"];
    }
    
    return _comparableNameFirstLast;
}

- (NSString *)comparableNameLastFirst {
    if (_comparableNameLastFirst == nil) {
        // Combine the two names with a tab separator, which has a lower ascii code than space, so that last names
        // that contain a space ("Van Der Beek\tJames") will sort after those that do not ("Van\tJames")
        _comparableNameLastFirst = [self combineLeftName:_lastName withRightName:_firstName usingSeparator:@"\t"];
    }
    
    return _comparableNameLastFirst;
}

- (NSString *)combineLeftName:(NSString *)leftName withRightName:(NSString *)rightName usingSeparator:(NSString *)separator {
    const BOOL leftNameNonEmpty = (leftName.length > 0);
    const BOOL rightNameNonEmpty = (rightName.length > 0);
    
    if (leftNameNonEmpty && rightNameNonEmpty) {
        return [NSString stringWithFormat:@"%@%@%@", leftName, separator, rightName];
    } else if (leftNameNonEmpty) {
        return [leftName copy];
    } else if (rightNameNonEmpty) {
        return [rightName copy];
    } else {
        return @"";
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@: %@", self.fullName, self.userTextPhoneNumbers];
}

- (BOOL)isSignalContact {
    NSArray *identifiers = [self textSecureIdentifiers];

    return [identifiers count] > 0;
}

- (NSArray<NSString *> *)textSecureIdentifiers {
    __block NSMutableArray *identifiers = [NSMutableArray array];

    [[TSStorageManager sharedManager]
            .dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      for (PhoneNumber *number in self.parsedPhoneNumbers) {
          if ([SignalRecipient recipientWithTextSecureIdentifier:number.toE164 withTransaction:transaction]) {
              [identifiers addObject:number.toE164];
          }
      }
    }];
    return [identifiers copy];
}

+ (NSComparator)comparatorSortingNamesByFirstThenLast:(BOOL)firstNameOrdering {
    return ^NSComparisonResult(id obj1, id obj2) {
        Contact *contact1 = (Contact *)obj1;
        Contact *contact2 = (Contact *)obj2;
        
        if (firstNameOrdering) {
            return [contact1.comparableNameFirstLast caseInsensitiveCompare:contact2.comparableNameFirstLast];
        } else {
            return [contact1.comparableNameLastFirst caseInsensitiveCompare:contact2.comparableNameLastFirst];
        }
    };
}

@end

NS_ASSUME_NONNULL_END
