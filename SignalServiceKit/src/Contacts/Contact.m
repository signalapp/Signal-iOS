//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "Contact.h"
#import "PhoneNumber.h"
#import "SSKEnvironment.h"
#import "SignalRecipient.h"
#import "TSAccountManager.h"
#import <Contacts/Contacts.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation Contact

@synthesize comparableNameFirstLast = _comparableNameFirstLast;
@synthesize comparableNameLastFirst = _comparableNameLastFirst;
@synthesize uniqueId = _uniqueId;

#if TARGET_OS_IOS

- (BOOL)isFromLocalAddressBook
{
    return self.cnContactId != nil;
}

- (instancetype)initWithUniqueId:(NSString *)uniqueId
                     cnContactId:(nullable NSString *)cnContactId
                       firstName:(nullable NSString *)firstName
                        lastName:(nullable NSString *)lastName
                        nickname:(nullable NSString *)nickname
                        fullName:(NSString *)fullName
            userTextPhoneNumbers:(NSArray<NSString *> *)userTextPhoneNumbers
              phoneNumberNameMap:(NSDictionary<NSString *, NSString *> *)phoneNumberNameMap
              parsedPhoneNumbers:(NSArray<PhoneNumber *> *)parsedPhoneNumbers
                          emails:(NSArray<NSString *> *)emails
{
    self = [super init];

    if (cnContactId == nil) {
        _cnContactId = nil;
        _uniqueId = [uniqueId copy];
    } else {
        OWSAssertDebug([uniqueId isEqual:cnContactId]);
        _cnContactId = [cnContactId copy];
        _uniqueId = _cnContactId;
    }

    _firstName = [firstName copy];
    _lastName = [lastName copy];
    _fullName = [fullName copy];
    _nickname = [nickname copy];
    _userTextPhoneNumbers = [userTextPhoneNumbers copy];
    _phoneNumberNameMap = [phoneNumberNameMap copy];
    _parsedPhoneNumbers = [parsedPhoneNumbers copy];
    _emails = [emails copy];

    return self;
}

- (instancetype)initWithSystemContact:(CNContact *)cnContact
{
    NSMutableArray<NSString *> *userTextPhoneNumbers = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSString *> *userTextPhoneNumberNameMap = [NSMutableDictionary new];
    const NSUInteger kMaxPhoneNumbersConsidered = 50;

    NSArray<CNLabeledValue *> *consideredPhoneNumbers;
    if (cnContact.phoneNumbers.count <= kMaxPhoneNumbersConsidered) {
        consideredPhoneNumbers = cnContact.phoneNumbers;
    } else {
        OWSLogInfo(@"For perf, only considering the first %lu phone numbers for contact with many numbers.", (unsigned long)kMaxPhoneNumbersConsidered);
        consideredPhoneNumbers = [cnContact.phoneNumbers subarrayWithRange:NSMakeRange(0, kMaxPhoneNumbersConsidered)];
    }
    for (CNLabeledValue *phoneNumberField in consideredPhoneNumbers) {
        if ([phoneNumberField.value isKindOfClass:[CNPhoneNumber class]]) {
            CNPhoneNumber *phoneNumber = (CNPhoneNumber *)phoneNumberField.value;
            [userTextPhoneNumbers addObject:phoneNumber.stringValue];
            if ([phoneNumberField.label isEqualToString:CNLabelHome]) {
                userTextPhoneNumberNameMap[phoneNumber.stringValue]
                    = OWSLocalizedString(@"PHONE_NUMBER_TYPE_HOME", @"Label for 'Home' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelWork]) {
                userTextPhoneNumberNameMap[phoneNumber.stringValue]
                    = OWSLocalizedString(@"PHONE_NUMBER_TYPE_WORK", @"Label for 'Work' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberiPhone]) {
                userTextPhoneNumberNameMap[phoneNumber.stringValue]
                    = OWSLocalizedString(@"PHONE_NUMBER_TYPE_IPHONE", @"Label for 'iPhone' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberMobile]) {
                userTextPhoneNumberNameMap[phoneNumber.stringValue]
                    = OWSLocalizedString(@"PHONE_NUMBER_TYPE_MOBILE", @"Label for 'Mobile' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberMain]) {
                userTextPhoneNumberNameMap[phoneNumber.stringValue]
                    = OWSLocalizedString(@"PHONE_NUMBER_TYPE_MAIN", @"Label for 'Main' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberHomeFax]) {
                userTextPhoneNumberNameMap[phoneNumber.stringValue]
                    = OWSLocalizedString(@"PHONE_NUMBER_TYPE_HOME_FAX", @"Label for 'HomeFAX' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberWorkFax]) {
                userTextPhoneNumberNameMap[phoneNumber.stringValue]
                    = OWSLocalizedString(@"PHONE_NUMBER_TYPE_WORK_FAX", @"Label for 'Work FAX' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberOtherFax]) {
                userTextPhoneNumberNameMap[phoneNumber.stringValue]
                    = OWSLocalizedString(@"PHONE_NUMBER_TYPE_OTHER_FAX", @"Label for 'Other FAX' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberPager]) {
                userTextPhoneNumberNameMap[phoneNumber.stringValue]
                    = OWSLocalizedString(@"PHONE_NUMBER_TYPE_PAGER", @"Label for 'Pager' phone numbers.");
            } else if ([phoneNumberField.label isEqualToString:CNLabelOther]) {
                userTextPhoneNumberNameMap[phoneNumber.stringValue]
                    = OWSLocalizedString(@"PHONE_NUMBER_TYPE_OTHER", @"Label for 'Other' phone numbers.");
            } else if (phoneNumberField.label.length > 0 && ![phoneNumberField.label hasPrefix:@"_$"]) {
                // We'll reach this case for:
                //
                // * User-defined custom labels, which we want to display.
                // * Labels like "_$!<CompanyMain>!$_", which I'm guessing are synced from other platforms.
                //   We don't want to display these labels. Even some of iOS' default labels (like Radio) show
                //   up this way.
                userTextPhoneNumberNameMap[phoneNumber.stringValue] = phoneNumberField.label;
            }
        }
    }

    NSArray<PhoneNumber *> *parsedPhoneNumbers;
    NSDictionary<NSString *, NSString *> *phoneNumberNameMap;
    [self.class parseUserTextPhoneNumbers:userTextPhoneNumbers
               userTextPhoneNumberNameMap:userTextPhoneNumberNameMap
                    outParsedPhoneNumbers:&parsedPhoneNumbers
              outParsedPhoneNumberNameMap:&phoneNumberNameMap];
    OWSAssertDebug(parsedPhoneNumbers != nil);
    OWSAssertDebug(phoneNumberNameMap != nil);

    NSMutableArray<NSString *> *emailAddresses = [NSMutableArray new];
    for (CNLabeledValue *emailField in cnContact.emailAddresses) {
        if ([emailField.value isKindOfClass:[NSString class]]) {
            [emailAddresses addObject:(NSString *)emailField.value];
        }
    }

    return [self initWithUniqueId:cnContact.identifier
                      cnContactId:cnContact.identifier
                        firstName:cnContact.givenName.ows_stripped
                         lastName:cnContact.familyName.ows_stripped
                         nickname:cnContact.nickname.ows_stripped
                         fullName:[Contact formattedFullNameWithCNContact:cnContact]
             userTextPhoneNumbers:userTextPhoneNumbers
               phoneNumberNameMap:phoneNumberNameMap
               parsedPhoneNumbers:parsedPhoneNumbers
                           emails:emailAddresses];
}

- (NSString *)uniqueId
{
    if (_uniqueId == nil) {
        if (_cnContactId) {
            return _cnContactId;
        }
        OWSFailDebug(@"failure: uniqueId was unexpectedly nil");
        return [NSUUID new].UUIDString;
    }

    return _uniqueId;
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

+ (void)parseUserTextPhoneNumbers:(NSArray<NSString *> *)userTextPhoneNumbers
       userTextPhoneNumberNameMap:(NSDictionary<NSString *, NSString *> *)phoneNumberNameMap
            outParsedPhoneNumbers:(NSArray<PhoneNumber *> **)outParsedPhoneNumbers
      outParsedPhoneNumberNameMap:(NSDictionary<NSString *, NSString *> **)outParsedPhoneNumberNameMap
{
    NSMutableDictionary<NSString *, NSString *> *parsedPhoneNumberNameMap = [NSMutableDictionary new];
    NSMutableArray<PhoneNumber *> *parsedPhoneNumbers = [NSMutableArray new];

    for (NSString *phoneNumberString in userTextPhoneNumbers) {
        for (PhoneNumber *phoneNumber in
            [PhoneNumber tryParsePhoneNumbersFromUserSpecifiedText:phoneNumberString
                                                  clientPhoneNumber:[TSAccountManager localNumber]]) {
            [parsedPhoneNumbers addObject:phoneNumber];
            NSString *phoneNumberName = phoneNumberNameMap[phoneNumberString];
            if (phoneNumberName) {
                parsedPhoneNumberNameMap[phoneNumber.toE164] = phoneNumberName;
            }
        }
    }

    *outParsedPhoneNumbers = [parsedPhoneNumbers sortedArrayUsingSelector:@selector(compare:)];
    *outParsedPhoneNumberNameMap = [parsedPhoneNumberNameMap copy];
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

    if (self.nickname.length > 0) {
        return self.nickname;
    }

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

+ (NSString *)formattedFullNameWithCNContact:(CNContact *)cnContact
{
    return [CNContactFormatter stringFromContact:cnContact style:CNContactFormatterStyleFullName].ows_stripped;
}

+ (nullable NSData *)avatarDataForCNContact:(nullable CNContact *)cnContact
{
    NSData *imageData = cnContact.thumbnailImageData;
    if (!imageData) {
        // This only occurs when sharing a contact via the share extension.
        imageData = cnContact.imageData;
    }
    return [imageData copy];
}

- (NSArray<NSString *> *)e164PhoneNumbers
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];
    for (PhoneNumber *phoneNumber in self.parsedPhoneNumbers) {
        [result addObject:phoneNumber.toE164];
    }
    return result;
}

// This method is used to de-bounce system contact fetch notifications
// by checking for changes in the contact data.
- (NSUInteger)hash
{
    // base hash is some arbitrary number
    NSUInteger hash = 1825038313;

    hash ^= self.fullName.hash;

    hash ^= self.nickname.hash;

    for (NSString *phoneNumber in self.e164PhoneNumbers) {
        hash ^= phoneNumber.hash;
    }

    for (NSString *email in self.emails) {
        hash ^= email.hash;
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
        mergedCNContact.nickname = newCNContact.nickname.ows_stripped;
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
