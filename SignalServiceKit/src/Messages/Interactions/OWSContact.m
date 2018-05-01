//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContact.h"
#import "NSString+SSK.h"
#import "OWSContact+Private.h"
#import "OWSSignalServiceProtos.pb.h"
#import "PhoneNumber.h"
#import "TSAttachment.h"
#import <YapDatabase/YapDatabaseTransaction.h>

@import Contacts;

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactPhoneNumber ()

@property (nonatomic) OWSContactPhoneType phoneType;
@property (nonatomic, nullable) NSString *label;

@property (nonatomic) NSString *phoneNumber;

@end

#pragma mark -

@implementation OWSContactPhoneNumber

- (BOOL)ows_isValid
{
    if (![PhoneNumber tryParsePhoneNumberFromE164:self.phoneNumber]) {
        return NO;
    }
    switch (self.phoneType) {
        case OWSContactPhoneType_Home:
        case OWSContactPhoneType_Mobile:
        case OWSContactPhoneType_Work:
            return YES;
        case OWSContactPhoneType_Custom:
            return self.label.ows_stripped.length > 0;
    }
}

- (NSString *)labelString
{
    switch (self.phoneType) {
        case OWSContactPhoneType_Home:
            return [CNLabeledValue localizedStringForLabel:CNLabelHome];
        case OWSContactPhoneType_Mobile:
            return [CNLabeledValue localizedStringForLabel:CNLabelPhoneNumberMobile];
        case OWSContactPhoneType_Work:
            return [CNLabeledValue localizedStringForLabel:CNLabelWork];
        default:
            return self.label;
    }
}

@end

#pragma mark -

@interface OWSContactEmail ()

@property (nonatomic) OWSContactEmailType emailType;
@property (nonatomic, nullable) NSString *label;

@property (nonatomic) NSString *email;

@end

#pragma mark -

@implementation OWSContactEmail

- (BOOL)ows_isValid
{
    if (self.email.ows_stripped.length < 1) {
        return NO;
    }
    switch (self.emailType) {
        case OWSContactEmailType_Home:
        case OWSContactEmailType_Mobile:
        case OWSContactEmailType_Work:
            return YES;
        case OWSContactEmailType_Custom:
            return self.label.ows_stripped.length > 0;
    }
}

- (NSString *)labelString
{
    switch (self.emailType) {
        case OWSContactEmailType_Home:
            return [CNLabeledValue localizedStringForLabel:CNLabelHome];
        case OWSContactEmailType_Mobile:
            return [CNLabeledValue localizedStringForLabel:CNLabelPhoneNumberMobile];
        case OWSContactEmailType_Work:
            return [CNLabeledValue localizedStringForLabel:CNLabelWork];
        default:
            return self.label;
    }
}

@end

#pragma mark -

@interface OWSContactAddress ()

@property (nonatomic) OWSContactAddressType addressType;
@property (nonatomic, nullable) NSString *label;

@property (nonatomic, nullable) NSString *street;
@property (nonatomic, nullable) NSString *pobox;
@property (nonatomic, nullable) NSString *neighborhood;
@property (nonatomic, nullable) NSString *city;
@property (nonatomic, nullable) NSString *region;
@property (nonatomic, nullable) NSString *postcode;
@property (nonatomic, nullable) NSString *country;

@end

#pragma mark -

@implementation OWSContactAddress

- (BOOL)ows_isValid
{
    if (self.street.ows_stripped.length < 1 && self.pobox.ows_stripped.length < 1
        && self.neighborhood.ows_stripped.length < 1 && self.city.ows_stripped.length < 1
        && self.region.ows_stripped.length < 1 && self.postcode.ows_stripped.length < 1
        && self.country.ows_stripped.length < 1) {
        return NO;
    }
    switch (self.addressType) {
        case OWSContactAddressType_Home:
        case OWSContactAddressType_Work:
            return YES;
        case OWSContactAddressType_Custom:
            return self.label.ows_stripped.length > 0;
    }
}

- (NSString *)labelString
{
    switch (self.addressType) {
        case OWSContactAddressType_Home:
            return [CNLabeledValue localizedStringForLabel:CNLabelHome];
        case OWSContactAddressType_Work:
            return [CNLabeledValue localizedStringForLabel:CNLabelWork];
        default:
            return self.label;
    }
}

@end

#pragma mark -

@interface OWSContact ()

@property (nonatomic, nullable) NSString *givenName;
@property (nonatomic, nullable) NSString *familyName;
@property (nonatomic, nullable) NSString *nameSuffix;
@property (nonatomic, nullable) NSString *namePrefix;
@property (nonatomic, nullable) NSString *middleName;
@property (nonatomic, nullable) NSString *organizationName;
@property (nonatomic, nullable) NSString *displayName;

@property (nonatomic, nullable) NSArray<OWSContactPhoneNumber *> *phoneNumbers;
@property (nonatomic, nullable) NSArray<OWSContactEmail *> *emails;
@property (nonatomic, nullable) NSArray<OWSContactAddress *> *addresses;

@property (nonatomic, nullable) TSAttachment *avatar;
@property (nonatomic) BOOL isProfileAvatar;

@end

#pragma mark -

@implementation OWSContact

- (void)normalize
{
    self.phoneNumbers = [self.phoneNumbers
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(OWSContactPhoneNumber *value,
                                        NSDictionary<NSString *, id> *_Nullable bindings) {
            return value.ows_isValid;
        }]];
    self.emails = [self.emails filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(OWSContactEmail *value,
                                                               NSDictionary<NSString *, id> *_Nullable bindings) {
        return value.ows_isValid;
    }]];
    self.addresses =
        [self.addresses filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(OWSContactAddress *value,
                                                        NSDictionary<NSString *, id> *_Nullable bindings) {
            return value.ows_isValid;
        }]];
}

- (BOOL)ows_isValid
{
    if (self.displayName.ows_stripped.length) {
        return NO;
    }
    BOOL hasValue = NO;
    for (OWSContactPhoneNumber *phoneNumber in self.phoneNumbers) {
        if (!phoneNumber.ows_isValid) {
            return NO;
        }
        hasValue = YES;
    }
    for (OWSContactEmail *email in self.emails) {
        if (!email.ows_isValid) {
            return NO;
        }
        hasValue = YES;
    }
    for (OWSContactAddress *address in self.addresses) {
        if (!address.ows_isValid) {
            return NO;
        }
        hasValue = YES;
    }
    return hasValue;
}

- (nullable NSString *)displayName
{
    [self ensureDisplayName];

    return _displayName;
}

- (void)ensureDisplayName
{
    if (_displayName.length < 1) {
        CNContact *_Nullable systemContact = [OWSContacts systemContactForContact:self];
        _displayName = [CNContactFormatter stringFromContact:systemContact style:CNContactFormatterStyleFullName];
    }
    if (_displayName.length < 1) {
        // Fall back to using the organization name.
        _displayName = self.organizationName;
    }
    if (_displayName.length < 1) {
        OWSProdLogAndFail(@"%@ could not derive a valid display name.", self.logTag);
    }
}

@end

#pragma mark -

@implementation OWSContacts

#pragma mark - VCard Serialization

+ (nullable CNContact *)systemContactForVCardData:(NSData *)data
{
    OWSAssert(data);

    NSError *error;
    NSArray<CNContact *> *_Nullable contacts = [CNContactVCardSerialization contactsWithData:data error:&error];
    if (!contacts || error) {
        OWSProdLogAndFail(@"%@ could not parse vcard: %@", self.logTag, error);
        return nil;
    }
    if (contacts.count < 1) {
        OWSProdLogAndFail(@"%@ empty vcard: %@", self.logTag, error);
        return nil;
    }
    if (contacts.count > 1) {
        OWSProdLogAndFail(@"%@ more than one contact in vcard: %@", self.logTag, error);
    }
    return contacts.firstObject;
}

+ (nullable NSData *)vCardDataForSystemContact:(CNContact *)systemContact
{
    OWSAssert(systemContact);

    NSError *error;
    NSData *_Nullable data = [CNContactVCardSerialization dataWithContacts:@[
        systemContact,
    ]
                                                                     error:&error];
    if (!data || error) {
        OWSProdLogAndFail(@"%@ could not serialize to vcard: %@", self.logTag, error);
        return nil;
    }
    if (data.length < 1) {
        OWSProdLogAndFail(@"%@ empty vcard data: %@", self.logTag, error);
        return nil;
    }
    return data;
}

#pragma mark - System Contact Conversion

+ (nullable OWSContact *)contactForSystemContact:(CNContact *)systemContact
{
    if (!systemContact) {
        OWSProdLogAndFail(@"%@ Missing contact.", self.logTag);
        return nil;
    }

    OWSContact *contact = [OWSContact new];
    contact.givenName = systemContact.givenName.ows_stripped;
    contact.middleName = systemContact.middleName.ows_stripped;
    contact.familyName = systemContact.familyName.ows_stripped;
    contact.namePrefix = systemContact.namePrefix.ows_stripped;
    contact.nameSuffix = systemContact.nameSuffix.ows_stripped;
    // TODO: Verify.
    contact.displayName = [CNContactFormatter stringFromContact:systemContact style:CNContactFormatterStyleFullName];
    contact.organizationName = systemContact.organizationName.ows_stripped;

    NSMutableArray<OWSContactPhoneNumber *> *phoneNumbers = [NSMutableArray new];
    for (CNLabeledValue<CNPhoneNumber *> *phoneNumberField in systemContact.phoneNumbers) {
        OWSContactPhoneNumber *phoneNumber = [OWSContactPhoneNumber new];
        phoneNumber.phoneNumber = phoneNumberField.value.stringValue;
        if ([phoneNumberField.label isEqualToString:CNLabelHome]) {
            phoneNumber.phoneType = OWSContactPhoneType_Home;
        } else if ([phoneNumberField.label isEqualToString:CNLabelWork]) {
            phoneNumber.phoneType = OWSContactPhoneType_Work;
        } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberMobile]) {
            phoneNumber.phoneType = OWSContactPhoneType_Mobile;
        } else {
            phoneNumber.phoneType = OWSContactPhoneType_Custom;
            phoneNumber.label = phoneNumberField.label;
        }
        [phoneNumbers addObject:phoneNumber];
    }
    contact.phoneNumbers = phoneNumbers;

    NSMutableArray<OWSContactEmail *> *emails = [NSMutableArray new];
    for (CNLabeledValue *emailField in systemContact.emailAddresses) {
        OWSContactEmail *email = [OWSContactEmail new];
        email.email = emailField.value;
        if ([emailField.label isEqualToString:CNLabelHome]) {
            email.emailType = OWSContactEmailType_Home;
        } else if ([emailField.label isEqualToString:CNLabelWork]) {
            email.emailType = OWSContactEmailType_Work;
        } else {
            email.emailType = OWSContactEmailType_Custom;
            email.label = emailField.label;
        }
        [emails addObject:email];
    }
    contact.emails = emails;

    NSMutableArray<OWSContactAddress *> *addresses = [NSMutableArray new];
    for (CNLabeledValue<CNPostalAddress *> *addressField in systemContact.postalAddresses) {
        OWSContactAddress *address = [OWSContactAddress new];
        address.street = addressField.value.street;
        // TODO: Is this the correct mapping?
        //        address.neighborhood = addressField.value.subLocality;
        address.city = addressField.value.city;
        // TODO: Is this the correct mapping?
        //        address.region = addressField.value.subAdministrativeArea;
        address.region = addressField.value.state;
        address.postcode = addressField.value.postalCode;
        // TODO: Should we be using 2-letter codes, 3-letter codes or names?
        address.country = addressField.value.ISOCountryCode;

        if ([addressField.label isEqualToString:CNLabelHome]) {
            address.addressType = OWSContactAddressType_Home;
        } else if ([addressField.label isEqualToString:CNLabelWork]) {
            address.addressType = OWSContactAddressType_Work;
        } else {
            address.addressType = OWSContactAddressType_Custom;
            address.label = addressField.label;
        }
        [addresses addObject:address];
    }
    contact.addresses = addresses;

    // TODO: Avatar

    //    @property (readonly, copy, nullable, NS_NONATOMIC_IOSONLY) NSData *imageData;
    //    @property (readonly, copy, nullable, NS_NONATOMIC_IOSONLY) NSData *thumbnailImageData;

    [contact ensureDisplayName];

    return contact;
}

+ (nullable CNContact *)systemContactForContact:(OWSContact *)contact
{
    if (!contact) {
        OWSProdLogAndFail(@"%@ Missing contact.", self.logTag);
        return nil;
    }

    CNMutableContact *systemContact = [CNMutableContact new];
    systemContact.givenName = contact.givenName;
    systemContact.middleName = contact.middleName;
    systemContact.familyName = contact.familyName;
    systemContact.namePrefix = contact.namePrefix;
    systemContact.nameSuffix = contact.nameSuffix;
    // We don't need to set display name, it's implicit for system contacts.
    systemContact.organizationName = contact.organizationName;

    NSMutableArray<CNLabeledValue<CNPhoneNumber *> *> *systemPhoneNumbers = [NSMutableArray new];
    for (OWSContactPhoneNumber *phoneNumber in contact.phoneNumbers) {
        switch (phoneNumber.phoneType) {
            case OWSContactPhoneType_Home:
                [systemPhoneNumbers
                    addObject:[CNLabeledValue
                                  labeledValueWithLabel:CNLabelHome
                                                  value:[CNPhoneNumber
                                                            phoneNumberWithStringValue:phoneNumber.phoneNumber]]];
                break;
            case OWSContactPhoneType_Mobile:
                [systemPhoneNumbers
                    addObject:[CNLabeledValue
                                  labeledValueWithLabel:CNLabelPhoneNumberMobile
                                                  value:[CNPhoneNumber
                                                            phoneNumberWithStringValue:phoneNumber.phoneNumber]]];
                break;
            case OWSContactPhoneType_Work:
                [systemPhoneNumbers
                    addObject:[CNLabeledValue
                                  labeledValueWithLabel:CNLabelWork
                                                  value:[CNPhoneNumber
                                                            phoneNumberWithStringValue:phoneNumber.phoneNumber]]];
                break;
            case OWSContactPhoneType_Custom:
                [systemPhoneNumbers
                    addObject:[CNLabeledValue
                                  labeledValueWithLabel:phoneNumber.label
                                                  value:[CNPhoneNumber
                                                            phoneNumberWithStringValue:phoneNumber.phoneNumber]]];
                break;
        }
    }
    systemContact.phoneNumbers = systemPhoneNumbers;

    NSMutableArray<CNLabeledValue<NSString *> *> *systemEmails = [NSMutableArray new];
    for (OWSContactEmail *email in contact.emails) {
        switch (email.emailType) {
            case OWSContactEmailType_Home:
                [systemEmails addObject:[CNLabeledValue labeledValueWithLabel:CNLabelHome value:email.email]];
                break;
            case OWSContactEmailType_Mobile:
                [systemEmails addObject:[CNLabeledValue labeledValueWithLabel:@"Mobile" value:email.email]];
                break;
            case OWSContactEmailType_Work:
                [systemEmails addObject:[CNLabeledValue labeledValueWithLabel:CNLabelWork value:email.email]];
                break;
            case OWSContactEmailType_Custom:
                [systemEmails addObject:[CNLabeledValue labeledValueWithLabel:email.label value:email.email]];
                break;
        }
    }
    systemContact.emailAddresses = systemEmails;

    NSMutableArray<CNLabeledValue<CNPostalAddress *> *> *systemAddresses = [NSMutableArray new];
    for (OWSContactAddress *address in contact.addresses) {
        CNMutablePostalAddress *systemAddress = [CNMutablePostalAddress new];
        systemAddress.street = address.street;
        // TODO: Is this the correct mapping?
        //        systemAddress.subLocality = address.neighborhood;
        systemAddress.city = address.city;
        // TODO: Is this the correct mapping?
        //        systemAddress.subAdministrativeArea = address.region;
        systemAddress.state = address.region;
        systemAddress.postalCode = address.postcode;
        // TODO: Should we be using 2-letter codes, 3-letter codes or names?
        systemAddress.ISOCountryCode = address.country;

        switch (address.addressType) {
            case OWSContactAddressType_Home:
                [systemAddresses addObject:[CNLabeledValue labeledValueWithLabel:CNLabelHome value:systemAddress]];
                break;
            case OWSContactAddressType_Work:
                [systemAddresses addObject:[CNLabeledValue labeledValueWithLabel:CNLabelWork value:systemAddress]];
                break;
            case OWSContactAddressType_Custom:
                [systemAddresses addObject:[CNLabeledValue labeledValueWithLabel:address.label value:systemAddress]];
                break;
        }
    }
    systemContact.postalAddresses = systemAddresses;

    // TODO: Avatar

    //    @property (readonly, copy, nullable, NS_NONATOMIC_IOSONLY) NSData *imageData;
    //    @property (readonly, copy, nullable, NS_NONATOMIC_IOSONLY) NSData *thumbnailImageData;

    return systemContact;
}

#pragma mark -

+ (nullable OWSContact *)contactForVCardData:(NSData *)data
{
    OWSAssert(data);

    CNContact *_Nullable systemContact = [self systemContactForVCardData:data];
    if (!systemContact) {
        return nil;
    }
    return [self contactForSystemContact:systemContact];
}

+ (nullable NSData *)vCardDataContact:(OWSContact *)contact
{
    OWSAssert(contact);

    CNContact *_Nullable systemContact = [self systemContactForContact:contact];
    if (!systemContact) {
        return nil;
    }
    return [self vCardDataForSystemContact:systemContact];
}

#pragma mark - Proto Serialization

+ (nullable OWSSignalServiceProtosDataMessageContact *)protoForContact:(OWSContact *)contact
{
    OWSAssert(contact);

    OWSSignalServiceProtosDataMessageContactBuilder *contactBuilder =
        [OWSSignalServiceProtosDataMessageContactBuilder new];

    OWSSignalServiceProtosDataMessageContactNameBuilder *nameBuilder =
        [OWSSignalServiceProtosDataMessageContactNameBuilder new];
    if (contact.givenName.ows_stripped.length > 0) {
        nameBuilder.givenName = contact.givenName.ows_stripped;
    }
    if (contact.familyName.ows_stripped.length > 0) {
        nameBuilder.familyName = contact.familyName.ows_stripped;
    }
    if (contact.middleName.ows_stripped.length > 0) {
        nameBuilder.middleName = contact.middleName.ows_stripped;
    }
    if (contact.namePrefix.ows_stripped.length > 0) {
        nameBuilder.prefix = contact.namePrefix.ows_stripped;
    }
    if (contact.nameSuffix.ows_stripped.length > 0) {
        nameBuilder.suffix = contact.nameSuffix.ows_stripped;
    }
    [contactBuilder setNameBuilder:nameBuilder];

    for (OWSContactPhoneNumber *phoneNumber in contact.phoneNumbers) {
        OWSSignalServiceProtosDataMessageContactPhoneBuilder *phoneBuilder =
            [OWSSignalServiceProtosDataMessageContactPhoneBuilder new];
        phoneBuilder.value = phoneNumber.phoneNumber;
        if (phoneNumber.label.ows_stripped.length > 0) {
            phoneBuilder.label = phoneNumber.label.ows_stripped;
        }
        switch (phoneNumber.phoneType) {
            case OWSContactPhoneType_Home:
                phoneBuilder.type = OWSSignalServiceProtosDataMessageContactPhoneTypeHome;
                break;
            case OWSContactPhoneType_Mobile:
                phoneBuilder.type = OWSSignalServiceProtosDataMessageContactPhoneTypeMobile;
                break;
            case OWSContactPhoneType_Work:
                phoneBuilder.type = OWSSignalServiceProtosDataMessageContactPhoneTypeWork;
                break;
            case OWSContactPhoneType_Custom:
                phoneBuilder.type = OWSSignalServiceProtosDataMessageContactPhoneTypeCustom;
                break;
        }
        [contactBuilder addNumber:phoneBuilder.build];
    }

    for (OWSContactEmail *email in contact.emails) {
        OWSSignalServiceProtosDataMessageContactEmailBuilder *emailBuilder =
            [OWSSignalServiceProtosDataMessageContactEmailBuilder new];
        emailBuilder.value = email.email;
        if (email.label.ows_stripped.length > 0) {
            emailBuilder.label = email.label.ows_stripped;
        }
        switch (email.emailType) {
            case OWSContactEmailType_Home:
                emailBuilder.type = OWSSignalServiceProtosDataMessageContactEmailTypeHome;
                break;
            case OWSContactEmailType_Mobile:
                emailBuilder.type = OWSSignalServiceProtosDataMessageContactEmailTypeMobile;
                break;
            case OWSContactEmailType_Work:
                emailBuilder.type = OWSSignalServiceProtosDataMessageContactEmailTypeWork;
                break;
            case OWSContactEmailType_Custom:
                emailBuilder.type = OWSSignalServiceProtosDataMessageContactEmailTypeCustom;
                break;
        }
        [contactBuilder addEmail:emailBuilder.build];
    }

    for (OWSContactAddress *address in contact.addresses) {
        OWSSignalServiceProtosDataMessageContactPostalAddressBuilder *addressBuilder =
            [OWSSignalServiceProtosDataMessageContactPostalAddressBuilder new];
        if (address.label.ows_stripped.length > 0) {
            addressBuilder.label = address.label.ows_stripped;
        }
        if (address.street.ows_stripped.length > 0) {
            addressBuilder.street = address.street.ows_stripped;
        }
        if (address.pobox.ows_stripped.length > 0) {
            addressBuilder.pobox = address.pobox.ows_stripped;
        }
        if (address.neighborhood.ows_stripped.length > 0) {
            addressBuilder.neighborhood = address.neighborhood.ows_stripped;
        }
        if (address.city.ows_stripped.length > 0) {
            addressBuilder.city = address.city.ows_stripped;
        }
        if (address.region.ows_stripped.length > 0) {
            addressBuilder.region = address.region.ows_stripped;
        }
        if (address.postcode.ows_stripped.length > 0) {
            addressBuilder.postcode = address.postcode.ows_stripped;
        }
        if (address.country.ows_stripped.length > 0) {
            addressBuilder.country = address.country.ows_stripped;
        }
        [contactBuilder addAddress:addressBuilder.build];
    }

    // TODO: avatar

    OWSSignalServiceProtosDataMessageContact *contactProto = [contactBuilder build];
    if (contactProto.number.count < 1 && contactProto.email.count < 1 && contactProto.address.count < 1) {
        OWSProdLogAndFail(@"%@ contact has neither phone, email or address.", self.logTag);
        return nil;
    }
    return contactProto;
}

+ (OWSContact *_Nullable)contactForDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    OWSAssert(dataMessage);

    if (dataMessage.contact.count < 1) {
        return nil;
    }
    OWSAssert(dataMessage.contact.count == 1);
    OWSSignalServiceProtosDataMessageContact *contactProto = dataMessage.contact.firstObject;

    OWSContact *contact = [OWSContact new];

    if (contactProto.hasOrganization) {
        contact.organizationName = contactProto.organization.ows_stripped;
    }

    if (contactProto.hasName) {
        OWSSignalServiceProtosDataMessageContactName *nameProto = contactProto.name;

        if (nameProto.hasGivenName) {
            contact.givenName = nameProto.givenName.ows_stripped;
        }
        if (nameProto.hasFamilyName) {
            contact.familyName = nameProto.familyName.ows_stripped;
        }
        if (nameProto.hasPrefix) {
            contact.namePrefix = nameProto.prefix.ows_stripped;
        }
        if (nameProto.hasSuffix) {
            contact.nameSuffix = nameProto.suffix.ows_stripped;
        }
        if (nameProto.hasMiddleName) {
            contact.middleName = nameProto.middleName.ows_stripped;
        }
        if (nameProto.hasDisplayName) {
            contact.displayName = nameProto.displayName.ows_stripped;
        }
    }

    NSMutableArray<OWSContactPhoneNumber *> *phoneNumbers = [NSMutableArray new];
    for (OWSSignalServiceProtosDataMessageContactPhone *phoneNumberProto in contactProto.number) {
        OWSContactPhoneNumber *_Nullable phoneNumber = [self phoneNumberForProto:phoneNumberProto];
        if (phoneNumber) {
            [phoneNumbers addObject:phoneNumber];
        }
    }
    contact.phoneNumbers = [phoneNumbers copy];

    NSMutableArray<OWSContactEmail *> *emails = [NSMutableArray new];
    for (OWSSignalServiceProtosDataMessageContactEmail *emailProto in contactProto.email) {
        OWSContactEmail *_Nullable email = [self emailForProto:emailProto];
        if (email) {
            [emails addObject:email];
        }
    }
    contact.emails = [emails copy];

    NSMutableArray<OWSContactAddress *> *addresses = [NSMutableArray new];
    for (OWSSignalServiceProtosDataMessageContactPostalAddress *addressProto in contactProto.address) {
        OWSContactAddress *_Nullable address = [self addressForProto:addressProto];
        if (address) {
            [addresses addObject:address];
        }
    }
    contact.addresses = [addresses copy];

    // TODO: Avatar

    [contact ensureDisplayName];

    return contact;
}

+ (nullable OWSContactPhoneNumber *)phoneNumberForProto:
    (OWSSignalServiceProtosDataMessageContactPhone *)phoneNumberProto
{
    OWSContactPhoneNumber *result = [OWSContactPhoneNumber new];
    result.phoneType = OWSContactPhoneType_Custom;
    if (phoneNumberProto.hasType) {
        switch (phoneNumberProto.type) {
            case OWSSignalServiceProtosDataMessageContactPhoneTypeHome:
                result.phoneType = OWSContactPhoneType_Home;
                break;
            case OWSSignalServiceProtosDataMessageContactPhoneTypeMobile:
                result.phoneType = OWSContactPhoneType_Mobile;
                break;
            case OWSSignalServiceProtosDataMessageContactPhoneTypeWork:
                result.phoneType = OWSContactPhoneType_Work;
                break;
            default:
                break;
        }
    }
    if (phoneNumberProto.hasLabel) {
        result.label = phoneNumberProto.label.ows_stripped;
    }
    if (phoneNumberProto.hasValue) {
        result.phoneNumber = phoneNumberProto.value.ows_stripped;
    } else {
        return nil;
    }
    return result;
}

+ (nullable OWSContactEmail *)emailForProto:(OWSSignalServiceProtosDataMessageContactEmail *)emailProto
{
    OWSContactEmail *result = [OWSContactEmail new];
    result.emailType = OWSContactEmailType_Custom;
    if (emailProto.hasType) {
        switch (emailProto.type) {
            case OWSSignalServiceProtosDataMessageContactEmailTypeHome:
                result.emailType = OWSContactEmailType_Home;
                break;
            case OWSSignalServiceProtosDataMessageContactEmailTypeMobile:
                result.emailType = OWSContactEmailType_Mobile;
                break;
            case OWSSignalServiceProtosDataMessageContactEmailTypeWork:
                result.emailType = OWSContactEmailType_Work;
                break;
            default:
                break;
        }
    }
    if (emailProto.hasLabel) {
        result.label = emailProto.label.ows_stripped;
    }
    if (emailProto.hasValue) {
        result.email = emailProto.value.ows_stripped;
    } else {
        return nil;
    }
    return result;
}

+ (nullable OWSContactAddress *)addressForProto:(OWSSignalServiceProtosDataMessageContactPostalAddress *)addressProto
{
    OWSContactAddress *result = [OWSContactAddress new];
    result.addressType = OWSContactAddressType_Custom;
    if (addressProto.hasType) {
        switch (addressProto.type) {
            case OWSSignalServiceProtosDataMessageContactPostalAddressTypeHome:
                result.addressType = OWSContactAddressType_Home;
                break;
            case OWSSignalServiceProtosDataMessageContactPostalAddressTypeWork:
                result.addressType = OWSContactAddressType_Work;
                break;
            default:
                break;
        }
    }
    if (addressProto.hasLabel) {
        result.label = addressProto.label.ows_stripped;
    }
    if (addressProto.hasStreet) {
        result.street = addressProto.street.ows_stripped;
    }
    if (addressProto.hasPobox) {
        result.pobox = addressProto.pobox.ows_stripped;
    }
    if (addressProto.hasNeighborhood) {
        result.neighborhood = addressProto.neighborhood.ows_stripped;
    }
    if (addressProto.hasCity) {
        result.city = addressProto.city.ows_stripped;
    }
    if (addressProto.hasRegion) {
        result.region = addressProto.region.ows_stripped;
    }
    if (addressProto.hasPostcode) {
        result.postcode = addressProto.postcode.ows_stripped;
    }
    if (addressProto.hasCountry) {
        result.country = addressProto.country.ows_stripped;
    }
    return result;
}

@end

NS_ASSUME_NONNULL_END
