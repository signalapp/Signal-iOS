#import "Contact.h"
#import "PhoneNumber.h"
#import "SignalRecipient.h"
#import "TSStorageManager.h"

@import Contacts;

NS_ASSUME_NONNULL_BEGIN

@implementation Contact

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
    NSMutableString *fullName = [NSMutableString string];
    if (self.firstName)
        [fullName appendString:self.firstName];
    if (self.lastName) {
        [fullName appendString:[NSString stringWithFormat:@" %@", self.lastName]];
    }
    return fullName;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ %@: %@", self.firstName, self.lastName, self.userTextPhoneNumbers];
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
    return identifiers;
}

@end

NS_ASSUME_NONNULL_END
