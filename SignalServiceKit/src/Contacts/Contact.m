//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Contact.h"
#import "Cryptography.h"
#import "NSString+SSK.h"
#import "OWSPrimaryStorage.h"
#import "PhoneNumber.h"
#import "SSKEnvironment.h"
#import "SignalRecipient.h"
#import "TSAccountManager.h"

@import Contacts;

NS_ASSUME_NONNULL_BEGIN

@interface Contact ()

@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSString *> *phoneNumberNameMap;
@property (nonatomic, readonly) NSUInteger imageHash;

@end

#pragma mark -

@implementation Contact

@synthesize comparableNameFirstLast = _comparableNameFirstLast;
@synthesize comparableNameLastFirst = _comparableNameLastFirst;

#if TARGET_OS_IOS

- (instancetype)initWithSystemContact:(CNContact *)cnContact
{
    self = [super init];
    if (!self) {
        return self;
    }

    _cnContactId = cnContact.identifier;
    _firstName = cnContact.givenName.ows_stripped;
    _lastName = cnContact.familyName.ows_stripped;
    _fullName = [Contact formattedFullNameWithCNContact:cnContact];

    NSMutableArray<NSString *> *phoneNumbers = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSString *> *phoneNumberNameMap = [NSMutableDictionary new];
    for (CNLabeledValue *phoneNumberField in cnContact.phoneNumbers) {
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
    for (CNLabeledValue *emailField in cnContact.emailAddresses) {
        if ([emailField.value isKindOfClass:[NSString class]]) {
            [emailAddresses addObject:(NSString *)emailField.value];
        }
    }
    _emails = [emailAddresses copy];

    NSData *_Nullable avatarData = [Contact avatarDataForCNContact:cnContact];
    if (avatarData) {
        NSUInteger hashValue = 0;
        NSData *_Nullable hashData = [Cryptography computeSHA256Digest:avatarData truncatedToBytes:sizeof(hashValue)];
        if (!hashData) {
            OWSFailDebug(@"could not compute hash for avatar.");
        }
        [hashData getBytes:&hashValue length:sizeof(hashValue)];
        _imageHash = hashValue;
    } else {
        _imageHash = 0;
    }

    return self;
}

- (NSString *)uniqueId
{
    return self.cnContactId;
}

+ (nullable Contact *)contactWithVCardData:(NSData *)data
{
    CNContact *_Nullable cnContact = [self cnContactWithVCardData:data];

    if (!cnContact) {
        OWSLogError(@"Could not parse vcard data.");
        return nil;
    }

    return [[self alloc] initWithSystemContact:cnContact];
}

#endif // TARGET_OS_IOS

- (NSArray<PhoneNumber *> *)parsedPhoneNumbersFromUserTextPhoneNumbers:(NSArray<NSString *> *)userTextPhoneNumbers
                                                    phoneNumberNameMap:(nullable NSDictionary<NSString *, NSString *> *)
                                                                           phoneNumberNameMap
{
    OWSAssertDebug(self.phoneNumberNameMap);

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
        SignalRecipient *_Nullable signalRecipient =
            [SignalRecipient registeredRecipientForRecipientId:number.toE164 transaction:transaction];
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
            if ([SignalRecipient isRegisteredRecipient:number.toE164 transaction:transaction]) {
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

+ (NSString *)formattedFullNameWithCNContact:(CNContact *)cnContact
{
    return [CNContactFormatter stringFromContact:cnContact style:CNContactFormatterStyleFullName].ows_stripped;
}

- (NSString *)nameForPhoneNumber:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug([self.textSecureIdentifiers containsObject:recipientId]);

    NSString *value = self.phoneNumberNameMap[recipientId];
    OWSAssertDebug(value);
    if (!value) {
        return NSLocalizedString(@"PHONE_NUMBER_TYPE_UNKNOWN",
            @"Label used when we don't what kind of phone number it is (e.g. mobile/work/home).");
    }
    return value;
}

+ (nullable NSData *)avatarDataForCNContact:(nullable CNContact *)cnContact
{
    if (cnContact.thumbnailImageData) {
        return cnContact.thumbnailImageData.copy;
    } else if (cnContact.imageData) {
        // This only occurs when sharing a contact via the share extension
        return cnContact.imageData.copy;
    } else {
        return nil;
    }
}

// This method is used to de-bounce system contact fetch notifications
// by checking for changes in the contact data.
- (NSUInteger)hash
{
    // base hash is some arbitrary number
    NSUInteger hash = 1825038313;

    hash = hash ^ self.fullName.hash;

    hash = hash ^ self.imageHash;

    for (PhoneNumber *phoneNumber in self.parsedPhoneNumbers) {
        hash = hash ^ phoneNumber.toE164.hash;
    }

    for (NSString *email in self.emails) {
        hash = hash ^ email.hash;
    }

    return hash;
}

#pragma mark - CNContactConverters

+ (nullable CNContact *)cnContactWithVCardData:(NSData *)data
{
    OWSAssertDebug(data);

    NSError *error;
    NSArray<CNContact *> *_Nullable contacts = [CNContactVCardSerialization contactsWithData:data error:&error];
    if (!contacts || error) {
        OWSFailDebug(@"could not parse vcard: %@", error);
        return nil;
    }
    if (contacts.count < 1) {
        OWSFailDebug(@"empty vcard: %@", error);
        return nil;
    }
    if (contacts.count > 1) {
        OWSFailDebug(@"more than one contact in vcard: %@", error);
    }
    return contacts.firstObject;
}

+ (CNContact *)mergeCNContact:(CNContact *)oldCNContact newCNContact:(CNContact *)newCNContact
{
    OWSAssertDebug(oldCNContact);
    OWSAssertDebug(newCNContact);

    Contact *oldContact = [[Contact alloc] initWithSystemContact:oldCNContact];

    CNMutableContact *_Nullable mergedCNContact = [oldCNContact mutableCopy];
    if (!mergedCNContact) {
        OWSFailDebug(@"mergedCNContact was unexpectedly nil");
        return [CNContact new];
    }
    
    // Name
    NSString *formattedFullName =  [self.class formattedFullNameWithCNContact:mergedCNContact];

    // merged all or nothing - do not try to piece-meal merge.
    if (formattedFullName.length == 0) {
        mergedCNContact.namePrefix = newCNContact.namePrefix.ows_stripped;
        mergedCNContact.givenName = newCNContact.givenName.ows_stripped;
        mergedCNContact.middleName = newCNContact.middleName.ows_stripped;
        mergedCNContact.familyName = newCNContact.familyName.ows_stripped;
        mergedCNContact.nameSuffix = newCNContact.nameSuffix.ows_stripped;
    }

    if (mergedCNContact.organizationName.ows_stripped.length < 1) {
        mergedCNContact.organizationName = newCNContact.organizationName.ows_stripped;
    }

    // Phone Numbers
    NSSet<PhoneNumber *> *existingParsedPhoneNumberSet = [NSSet setWithArray:oldContact.parsedPhoneNumbers];
    NSSet<NSString *> *existingUnparsedPhoneNumberSet = [NSSet setWithArray:oldContact.userTextPhoneNumbers];

    NSMutableArray<CNLabeledValue<CNPhoneNumber *> *> *mergedPhoneNumbers = [mergedCNContact.phoneNumbers mutableCopy];
    for (CNLabeledValue<CNPhoneNumber *> *labeledPhoneNumber in newCNContact.phoneNumbers) {
        NSString *_Nullable unparsedPhoneNumber = labeledPhoneNumber.value.stringValue;
        if ([existingUnparsedPhoneNumberSet containsObject:unparsedPhoneNumber]) {
            // Skip phone number if "unparsed" form is a duplicate.
            continue;
        }
        PhoneNumber *_Nullable parsedPhoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:labeledPhoneNumber.value.stringValue];
        if (parsedPhoneNumber && [existingParsedPhoneNumberSet containsObject:parsedPhoneNumber]) {
            // Skip phone number if "parsed" form is a duplicate.
            continue;
        }
        [mergedPhoneNumbers addObject:labeledPhoneNumber];
    }
    mergedCNContact.phoneNumbers = mergedPhoneNumbers;
    
    // Emails
    NSSet<NSString *> *existingEmailSet = [NSSet setWithArray:oldContact.emails];
    NSMutableArray<CNLabeledValue<NSString *> *> *mergedEmailAddresses = [mergedCNContact.emailAddresses mutableCopy];
    for (CNLabeledValue<NSString *> *labeledEmail in newCNContact.emailAddresses) {
        NSString *normalizedValue = labeledEmail.value.ows_stripped;
        if (![existingEmailSet containsObject:normalizedValue]) {
            [mergedEmailAddresses addObject:labeledEmail];
        }
    }
    mergedCNContact.emailAddresses = mergedEmailAddresses;
    
    // Address
    // merged all or nothing - do not try to piece-meal merge.
    if (mergedCNContact.postalAddresses.count == 0) {
        mergedCNContact.postalAddresses = newCNContact.postalAddresses;
    }

    // Avatar
    if (!mergedCNContact.imageData) {
        mergedCNContact.imageData = newCNContact.imageData;
    }

    return [mergedCNContact copy];
}

+ (nullable NSString *)localizedStringForCNLabel:(nullable NSString *)cnLabel
{
    if (cnLabel.length == 0) {
        return nil;
    }

    NSString *_Nullable localizedLabel = [CNLabeledValue localizedStringForLabel:cnLabel];

    // Docs for localizedStringForLabel say it returns:
    // > The localized string if a Contacts framework defined label, otherwise just returns the label.
    // But in practice, at least on iOS11, if the label is not one of CNContacts known labels (like CNLabelHome)
    // kUnlocalizedStringLabel is returned, rather than the unadultered label.
    NSString *const kUnlocalizedStringLabel = @"__ABUNLOCALIZEDSTRING";

    if ([localizedLabel isEqual:kUnlocalizedStringLabel]) {
        return cnLabel;
    }

    return localizedLabel;
}

@end

NS_ASSUME_NONNULL_END
