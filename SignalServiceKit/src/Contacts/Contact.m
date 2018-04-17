//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Contact.h"
#import "Cryptography.h"
#import "OWSPrimaryStorage.h"
#import "PhoneNumber.h"
#import "SignalRecipient.h"
#import "TSAccountManager.h"

@import Contacts;

NS_ASSUME_NONNULL_BEGIN

@interface Contact ()

@property (readonly, nonatomic) NSMutableDictionary<NSString *, NSString *> *phoneNumberNameMap;
@property (readonly, nonatomic) NSData *imageData;

@end

#pragma mark -

@implementation Contact

@synthesize comparableNameFirstLast = _comparableNameFirstLast;
@synthesize comparableNameLastFirst = _comparableNameLastFirst;
@synthesize image = _image;

#if TARGET_OS_IOS

- (instancetype)initWithSystemContact:(CNContact *)contact
{
    self = [super init];
    if (!self) {
        return self;
    }

    _cnContact = contact;
    _firstName = [self trimName:contact.givenName];
    _lastName = [self trimName:contact.familyName];
    _fullName = [CNContactFormatter stringFromContact:contact style:CNContactFormatterStyleFullName];
    _uniqueId = contact.identifier;

    NSMutableArray<NSString *> *phoneNumbers = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSString *> *phoneNumberNameMap = [NSMutableDictionary new];
    for (CNLabeledValue *phoneNumberField in contact.phoneNumbers) {
        if ([phoneNumberField.value isKindOfClass:[CNPhoneNumber class]]) {
            CNPhoneNumber *phoneNumber = (CNPhoneNumber *)phoneNumberField.value;
            [phoneNumbers addObject:phoneNumber.stringValue];
            if ([phoneNumberField.label isEqualToString:CNLabelHome]) {
                phoneNumberNameMap[phoneNumber.stringValue]
                    = NSLocalizedString(@"PHONE_NUMBER_TYPE_HOME", @"Label for 'Home' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelWork]) {
                phoneNumberNameMap[phoneNumber.stringValue]
                    = NSLocalizedString(@"PHONE_NUMBER_TYPE_WORK", @"Label for 'Work' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberiPhone]) {
                phoneNumberNameMap[phoneNumber.stringValue]
                    = NSLocalizedString(@"PHONE_NUMBER_TYPE_IPHONE", @"Label for 'iPhone' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberMobile]) {
                phoneNumberNameMap[phoneNumber.stringValue]
                    = NSLocalizedString(@"PHONE_NUMBER_TYPE_MOBILE", @"Label for 'Mobile' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberMain]) {
                phoneNumberNameMap[phoneNumber.stringValue]
                    = NSLocalizedString(@"PHONE_NUMBER_TYPE_MAIN", @"Label for 'Main' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberHomeFax]) {
                phoneNumberNameMap[phoneNumber.stringValue]
                    = NSLocalizedString(@"PHONE_NUMBER_TYPE_HOME_FAX", @"Label for 'HomeFAX' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberWorkFax]) {
                phoneNumberNameMap[phoneNumber.stringValue]
                    = NSLocalizedString(@"PHONE_NUMBER_TYPE_WORK_FAX", @"Label for 'Work FAX' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberOtherFax]) {
                phoneNumberNameMap[phoneNumber.stringValue]
                    = NSLocalizedString(@"PHONE_NUMBER_TYPE_OTHER_FAX", @"Label for 'Other FAX' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberPager]) {
                phoneNumberNameMap[phoneNumber.stringValue]
                    = NSLocalizedString(@"PHONE_NUMBER_TYPE_PAGER", @"Label for 'Pager' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelOther]) {
                phoneNumberNameMap[phoneNumber.stringValue]
                    = NSLocalizedString(@"PHONE_NUMBER_TYPE_OTHER", @"Label for 'Other' phone numbers.");
            } else if (phoneNumberField.label.length > 0 && ![phoneNumberField.label hasPrefix:@"_$"]) {
                // We'll reach this case for:
                //
                // * User-defined custom labels, which we want to display.
                // * Labels like "_$!<CompanyMain>!$_", which I'm guessing are synced from other platforms.
                //   We don't want to display these labels. Even some of iOS' default labels (like Radio) show
                //   up this way.
                phoneNumberNameMap[phoneNumber.stringValue] = phoneNumberField.label;
            }
        }
    }

    _userTextPhoneNumbers = [phoneNumbers copy];
    _phoneNumberNameMap = [NSMutableDictionary new];
    _parsedPhoneNumbers =
        [self parsedPhoneNumbersFromUserTextPhoneNumbers:phoneNumbers phoneNumberNameMap:phoneNumberNameMap];

    NSMutableArray<NSString *> *emailAddresses = [NSMutableArray new];
    for (CNLabeledValue *emailField in contact.emailAddresses) {
        if ([emailField.value isKindOfClass:[NSString class]]) {
            [emailAddresses addObject:(NSString *)emailField.value];
        }
    }
    _emails = [emailAddresses copy];

    if (contact.thumbnailImageData) {
        _imageData = [contact.thumbnailImageData copy];
    }

    return self;
}

- (nullable UIImage *)image
{
    if (_image) {
        return _image;
    }

    if (!self.imageData) {
        return nil;
    }

    _image = [UIImage imageWithData:self.imageData];
    return _image;
}

- (NSString *)trimName:(NSString *)name
{
    return [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (MTLPropertyStorage)storageBehaviorForPropertyWithKey:(NSString *)propertyKey
{
    if ([propertyKey isEqualToString:@"cnContact"] || [propertyKey isEqualToString:@"image"]) {
        return MTLPropertyStorageTransitory;
    } else {
        return [super storageBehaviorForPropertyWithKey:propertyKey];
    }
}

#endif // TARGET_OS_IOS

- (NSArray<PhoneNumber *> *)parsedPhoneNumbersFromUserTextPhoneNumbers:(NSArray<NSString *> *)userTextPhoneNumbers
                                                    phoneNumberNameMap:(nullable NSDictionary<NSString *, NSString *> *)
                                                                           phoneNumberNameMap
{
    OWSAssert(self.phoneNumberNameMap);

    NSMutableDictionary<NSString *, PhoneNumber *> *parsedPhoneNumberMap = [NSMutableDictionary new];
    NSMutableArray<PhoneNumber *> *parsedPhoneNumbers = [NSMutableArray new];
    for (NSString *phoneNumberString in userTextPhoneNumbers) {
        for (PhoneNumber *phoneNumber in
            [PhoneNumber tryParsePhoneNumbersFromsUserSpecifiedText:phoneNumberString
                                                  clientPhoneNumber:[TSAccountManager localNumber]]) {
            [parsedPhoneNumbers addObject:phoneNumber];
            parsedPhoneNumberMap[phoneNumber.toE164] = phoneNumber;
            NSString *phoneNumberName = phoneNumberNameMap[phoneNumberString];
            if (phoneNumberName) {
                self.phoneNumberNameMap[phoneNumber.toE164] = phoneNumberName;
            }
        }
    }
    return [parsedPhoneNumbers sortedArrayUsingSelector:@selector(compare:)];
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

- (NSArray<SignalRecipient *> *)signalRecipientsWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    __block NSMutableArray *result = [NSMutableArray array];

    for (PhoneNumber *number in [self.parsedPhoneNumbers sortedArrayUsingSelector:@selector(compare:)]) {
        SignalRecipient *signalRecipient =
            [SignalRecipient recipientWithTextSecureIdentifier:number.toE164 withTransaction:transaction];
        if (signalRecipient) {
            [result addObject:signalRecipient];
        }
    }

    return [result copy];
}

- (NSArray<NSString *> *)textSecureIdentifiers {
    __block NSMutableArray *identifiers = [NSMutableArray array];

    [OWSPrimaryStorage.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
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

- (NSString *)nameForPhoneNumber:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);
    OWSAssert([self.textSecureIdentifiers containsObject:recipientId]);

    NSString *value = self.phoneNumberNameMap[recipientId];
    OWSAssert(value);
    if (!value) {
        return NSLocalizedString(@"PHONE_NUMBER_TYPE_UNKNOWN",
            @"Label used when we don't what kind of phone number it is (e.g. mobile/work/home).");
    }
    return value;
}

- (NSUInteger)hash
{
    // base hash is some arbitrary number
    NSUInteger hash = 1825038313;

    hash = hash ^ self.fullName.hash;

    if (self.imageData) {
        NSUInteger thumbnailHash = 0;
        NSData *thumbnailHashData =
            [Cryptography computeSHA256Digest:self.imageData truncatedToBytes:sizeof(thumbnailHash)];
        [thumbnailHashData getBytes:&thumbnailHash length:sizeof(thumbnailHash)];
        hash = hash ^ thumbnailHash;
    }

    for (PhoneNumber *phoneNumber in self.parsedPhoneNumbers) {
        hash = hash ^ phoneNumber.toE164.hash;
    }

    for (NSString *email in self.emails) {
        hash = hash ^ email.hash;
    }

    return hash;
}

@end

NS_ASSUME_NONNULL_END
