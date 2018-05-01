//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContactShare.h"
#import "NSString+SSK.h"
#import "OWSContactShare+Private.h"
#import "OWSSignalServiceProtos.pb.h"
#import "PhoneNumber.h"
#import "TSAttachment.h"
#import <YapDatabase/YapDatabaseTransaction.h>

@import Contacts;

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactSharePhoneNumber ()

@property (nonatomic) OWSContactSharePhoneType phoneType;
@property (nonatomic, nullable) NSString *label;

@property (nonatomic) NSString *phoneNumber;

@end

#pragma mark -

@implementation OWSContactSharePhoneNumber

- (BOOL)isValid
{
    if (![PhoneNumber tryParsePhoneNumberFromE164:self.phoneNumber]) {
        return NO;
    }
    switch (self.phoneType) {
        case OWSContactSharePhoneType_Home:
        case OWSContactSharePhoneType_Mobile:
        case OWSContactSharePhoneType_Work:
            return YES;
        default:
            return self.label.ows_stripped.length > 0;
    }
}

@end

#pragma mark -

@interface OWSContactShareEmail ()

@property (nonatomic) OWSContactShareEmailType emailType;
@property (nonatomic, nullable) NSString *label;

@property (nonatomic) NSString *email;

@end

#pragma mark -

@implementation OWSContactShareEmail

- (BOOL)isValid
{
    if (self.email.ows_stripped.length < 1) {
        return NO;
    }
    switch (self.emailType) {
        case OWSContactShareEmailType_Home:
        case OWSContactShareEmailType_Mobile:
        case OWSContactShareEmailType_Work:
            return YES;
        default:
            return self.label.ows_stripped.length > 0;
    }
}

@end

#pragma mark -

@interface OWSContactShareAddress ()

@property (nonatomic) OWSContactShareAddressType addressType;
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

@implementation OWSContactShareAddress

- (BOOL)isValid
{
    if (self.street.ows_stripped.length < 1 && self.pobox.ows_stripped.length < 1
        && self.neighborhood.ows_stripped.length < 1 && self.city.ows_stripped.length < 1
        && self.region.ows_stripped.length < 1 && self.postcode.ows_stripped.length < 1
        && self.country.ows_stripped.length < 1) {
        return NO;
    }
    switch (self.addressType) {
        case OWSContactShareAddressType_Home:
        case OWSContactShareAddressType_Work:
            return YES;
        default:
            return self.label.ows_stripped.length > 0;
    }
}

@end

#pragma mark -

@interface OWSContactShare ()

@property (nonatomic, nullable) NSString *givenName;
@property (nonatomic, nullable) NSString *familyName;
@property (nonatomic, nullable) NSString *nameSuffix;
@property (nonatomic, nullable) NSString *namePrefix;
@property (nonatomic, nullable) NSString *middleName;

@property (nonatomic, nullable) NSArray<OWSContactSharePhoneNumber *> *phoneNumbers;
@property (nonatomic, nullable) NSArray<OWSContactShareEmail *> *emails;
@property (nonatomic, nullable) NSArray<OWSContactShareAddress *> *addresses;

@property (nonatomic, nullable) TSAttachment *avatar;
@property (nonatomic) BOOL isProfileAvatar;

@end

#pragma mark -

@implementation OWSContactShare

+ (OWSContactShare *_Nullable)contactShareForDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
                                             transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(dataMessage);

    if (dataMessage.contact.count < 1) {
        return nil;
    }
    OWSAssert(dataMessage.contact.count == 1);
    OWSSignalServiceProtosDataMessageContact *contactProto = dataMessage.contact.firstObject;

    OWSContactShare *contactShare = [OWSContactShare new];
    if (contactProto.hasName) {
        OWSSignalServiceProtosDataMessageContactName *nameProto = contactProto.name;

        if (nameProto.hasGivenName) {
            contactShare.givenName = nameProto.givenName.ows_stripped;
        }
        if (nameProto.hasFamilyName) {
            contactShare.familyName = nameProto.familyName.ows_stripped;
        }
        if (nameProto.hasPrefix) {
            contactShare.namePrefix = nameProto.prefix.ows_stripped;
        }
        if (nameProto.hasSuffix) {
            contactShare.nameSuffix = nameProto.suffix.ows_stripped;
        }
        if (nameProto.hasMiddleName) {
            contactShare.middleName = nameProto.middleName.ows_stripped;
        }
    }

    NSMutableArray<OWSContactSharePhoneNumber *> *phoneNumbers = [NSMutableArray new];
    for (OWSSignalServiceProtosDataMessageContactPhone *phoneNumberProto in contactProto.number) {
        OWSContactSharePhoneNumber *_Nullable phoneNumber = [self phoneNumberForProto:phoneNumberProto];
        if (phoneNumber) {
            [phoneNumbers addObject:phoneNumber];
        }
    }
    contactShare.phoneNumbers = [phoneNumbers copy];

    NSMutableArray<OWSContactShareEmail *> *emails = [NSMutableArray new];
    for (OWSSignalServiceProtosDataMessageContactEmail *emailProto in contactProto.email) {
        OWSContactShareEmail *_Nullable email = [self emailForProto:emailProto];
        if (email) {
            [emails addObject:email];
        }
    }
    contactShare.emails = [emails copy];

    NSMutableArray<OWSContactShareAddress *> *addresses = [NSMutableArray new];
    for (OWSSignalServiceProtosDataMessageContactPostalAddress *addressProto in contactProto.address) {
        OWSContactShareAddress *_Nullable address = [self addressForProto:addressProto];
        if (address) {
            [addresses addObject:address];
        }
    }
    contactShare.addresses = [addresses copy];

    // TODO: Avatar

    return contactShare;
}

+ (nullable OWSContactSharePhoneNumber *)phoneNumberForProto:
    (OWSSignalServiceProtosDataMessageContactPhone *)phoneNumberProto
{
    OWSContactSharePhoneNumber *result = [OWSContactSharePhoneNumber new];
    result.phoneType = OWSContactSharePhoneType_Custom;
    if (phoneNumberProto.hasType) {
        switch (phoneNumberProto.type) {
            case OWSSignalServiceProtosDataMessageContactPhoneTypeHome:
                result.phoneType = OWSContactSharePhoneType_Home;
                break;
            case OWSSignalServiceProtosDataMessageContactPhoneTypeMobile:
                result.phoneType = OWSContactSharePhoneType_Mobile;
                break;
            case OWSSignalServiceProtosDataMessageContactPhoneTypeWork:
                result.phoneType = OWSContactSharePhoneType_Work;
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

+ (nullable OWSContactShareEmail *)emailForProto:(OWSSignalServiceProtosDataMessageContactEmail *)emailProto
{
    OWSContactShareEmail *result = [OWSContactShareEmail new];
    result.emailType = OWSContactShareEmailType_Custom;
    if (emailProto.hasType) {
        switch (emailProto.type) {
            case OWSSignalServiceProtosDataMessageContactEmailTypeHome:
                result.emailType = OWSContactShareEmailType_Home;
                break;
            case OWSSignalServiceProtosDataMessageContactEmailTypeMobile:
                result.emailType = OWSContactShareEmailType_Mobile;
                break;
            case OWSSignalServiceProtosDataMessageContactEmailTypeWork:
                result.emailType = OWSContactShareEmailType_Work;
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

+ (nullable OWSContactShareAddress *)addressForProto:
    (OWSSignalServiceProtosDataMessageContactPostalAddress *)addressProto
{
    OWSContactShareAddress *result = [OWSContactShareAddress new];
    result.addressType = OWSContactShareAddressType_Custom;
    if (addressProto.hasType) {
        switch (addressProto.type) {
            case OWSSignalServiceProtosDataMessageContactPostalAddressTypeHome:
                result.addressType = OWSContactShareAddressType_Home;
                break;
            case OWSSignalServiceProtosDataMessageContactPostalAddressTypeWork:
                result.addressType = OWSContactShareAddressType_Work;
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

    for (OWSContactSharePhoneNumber *phoneNumber in self.phoneNumbers) {
        if (phoneNumber.isValid) {
            return YES;
        }
    }
    for (OWSContactShareEmail *email in self.emails) {
        if (email.isValid) {
            return YES;
        }
    }
    for (OWSContactShareAddress *address in self.addresses) {
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

+ (nullable OWSContactShare *)contactShareForSystemContact:(CNContact *)contact
{
    if (!contact) {
        OWSProdLogAndFail(@"%@ Missing contact.", self.logTag);
        return nil;
    }

    OWSContactShare *contactShare = [OWSContactShare new];
    contactShare.givenName = contact.givenName.ows_stripped;
    contactShare.middleName = contact.middleName.ows_stripped;
    contactShare.familyName = contact.familyName.ows_stripped;
    contactShare.namePrefix = contact.namePrefix.ows_stripped;
    contactShare.nameSuffix = contact.nameSuffix.ows_stripped;
    // TODO: Display name.
    //    contactShare.displayName = [CNContactFormatter stringFromContact:contact
    //    style:CNContactFormatterStyleFullName]; contactShare.organizationName = contact.organizationName.ows_stripped;

    NSMutableArray<OWSContactSharePhoneNumber *> *phoneNumbers = [NSMutableArray new];
    for (CNLabeledValue<CNPhoneNumber *> *phoneNumberField in contact.phoneNumbers) {
        OWSContactSharePhoneNumber *phoneNumber = [OWSContactSharePhoneNumber new];
        phoneNumber.phoneNumber = phoneNumberField.value.stringValue;
        if ([phoneNumberField.label isEqualToString:CNLabelHome]) {
            phoneNumber.phoneType = OWSContactSharePhoneType_Home;
        } else if ([phoneNumberField.label isEqualToString:CNLabelWork]) {
            phoneNumber.phoneType = OWSContactSharePhoneType_Work;
        } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberMobile]) {
            phoneNumber.phoneType = OWSContactSharePhoneType_Mobile;
        } else {
            phoneNumber.phoneType = OWSContactSharePhoneType_Custom;
            phoneNumber.label = phoneNumberField.label;
        }
        if (phoneNumber.isValid) {
            [phoneNumbers addObject:phoneNumber];
        }
    }
    contactShare.phoneNumbers = phoneNumbers;

    NSMutableArray<OWSContactShareEmail *> *emails = [NSMutableArray new];
    for (CNLabeledValue *emailField in contact.emailAddresses) {
        OWSContactShareEmail *email = [OWSContactShareEmail new];
        email.email = emailField.value;
        if ([emailField.label isEqualToString:CNLabelHome]) {
            email.emailType = OWSContactShareEmailType_Home;
        } else if ([emailField.label isEqualToString:CNLabelWork]) {
            email.emailType = OWSContactShareEmailType_Work;
        } else {
            email.emailType = OWSContactShareEmailType_Custom;
            email.label = emailField.label;
        }
        if (email.isValid) {
            [emails addObject:email];
        }
    }
    contactShare.emails = emails;

    NSMutableArray<OWSContactShareAddress *> *addresses = [NSMutableArray new];
    for (CNLabeledValue<CNPostalAddress *> *addressField in contact.postalAddresses) {
        OWSContactShareAddress *address = [OWSContactShareAddress new];
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
            address.addressType = OWSContactShareAddressType_Home;
        } else if ([addressField.label isEqualToString:CNLabelWork]) {
            address.addressType = OWSContactShareAddressType_Work;
        } else {
            address.addressType = OWSContactShareAddressType_Custom;
            address.label = addressField.label;
        }
        if (address.isValid) {
            [addresses addObject:address];
        }
    }
    contactShare.addresses = addresses;

    // TODO: Avatar

    //    @property (readonly, copy, nullable, NS_NONATOMIC_IOSONLY) NSData *imageData;
    //    @property (readonly, copy, nullable, NS_NONATOMIC_IOSONLY) NSData *thumbnailImageData;

    if (contactShare.isValid) {
        return contactShare;
    } else {
        return nil;
    }
}

+ (nullable OWSContactShare *)contactShareForVCardData:(NSData *)data
{
    CNContact *_Nullable systemContact = [self systemContactForVCardData:data];
    if (!systemContact) {
        return nil;
    }
    return [self contactShareForSystemContact:systemContact];
}

@end

NS_ASSUME_NONNULL_END
