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

- (BOOL)isValid
{
    if (![PhoneNumber tryParsePhoneNumberFromE164:self.phoneNumber]) {
        return NO;
    }
    switch (self.phoneType) {
        case OWSContactPhoneType_Home:
        case OWSContactPhoneType_Mobile:
        case OWSContactPhoneType_Work:
            return YES;
        default:
            return self.label.ows_stripped.length > 0;
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

- (BOOL)isValid
{
    if (self.email.ows_stripped.length < 1) {
        return NO;
    }
    switch (self.emailType) {
        case OWSContactEmailType_Home:
        case OWSContactEmailType_Mobile:
        case OWSContactEmailType_Work:
            return YES;
        default:
            return self.label.ows_stripped.length > 0;
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

- (BOOL)isValid
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
        default:
            return self.label.ows_stripped.length > 0;
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

@property (nonatomic, nullable) NSArray<OWSContactPhoneNumber *> *phoneNumbers;
@property (nonatomic, nullable) NSArray<OWSContactEmail *> *emails;
@property (nonatomic, nullable) NSArray<OWSContactAddress *> *addresses;

@property (nonatomic, nullable) TSAttachment *avatar;
@property (nonatomic) BOOL isProfileAvatar;

@end

#pragma mark -

@implementation OWSContact

+ (OWSContact *_Nullable)contactForDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(dataMessage);

    if (dataMessage.contact.count < 1) {
        return nil;
    }
    OWSAssert(dataMessage.contact.count == 1);
    OWSSignalServiceProtosDataMessageContact *contactProto = dataMessage.contact.firstObject;

    OWSContact *contact = [OWSContact new];
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
    if (!result.isValid) {
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
    if (!result.isValid) {
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
    if (!result.isValid) {
        return nil;
    }
    return result;
}

- (BOOL)isValid
{
    if (self.givenName.ows_stripped.length < 1 && self.familyName.ows_stripped.length) {
        return NO;
    }

    for (OWSContactPhoneNumber *phoneNumber in self.phoneNumbers) {
        if (phoneNumber.isValid) {
            return YES;
        }
    }
    for (OWSContactEmail *email in self.emails) {
        if (email.isValid) {
            return YES;
        }
    }
    for (OWSContactAddress *address in self.addresses) {
        if (address.isValid) {
            return YES;
        }
    }
    return NO;
}

@end

#pragma mark -

@implementation OWSContacts

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
    // TODO: Display name.
    //    contact.displayName = [CNContactFormatter stringFromContact:contact
    //    style:CNContactFormatterStyleFullName]; contact.organizationName = contact.organizationName.ows_stripped;

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
        if (phoneNumber.isValid) {
            [phoneNumbers addObject:phoneNumber];
        }
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
        if (email.isValid) {
            [emails addObject:email];
        }
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
        if (address.isValid) {
            [addresses addObject:address];
        }
    }
    contact.addresses = addresses;

    // TODO: Avatar

    //    @property (readonly, copy, nullable, NS_NONATOMIC_IOSONLY) NSData *imageData;
    //    @property (readonly, copy, nullable, NS_NONATOMIC_IOSONLY) NSData *thumbnailImageData;

    if (contact.isValid) {
        return contact;
    } else {
        return nil;
    }
}

+ (nullable OWSContact *)contactForVCardData:(NSData *)data
{
    CNContact *_Nullable systemContact = [self systemContactForVCardData:data];
    if (!systemContact) {
        return nil;
    }
    return [self contactForSystemContact:systemContact];
}

@end

NS_ASSUME_NONNULL_END
