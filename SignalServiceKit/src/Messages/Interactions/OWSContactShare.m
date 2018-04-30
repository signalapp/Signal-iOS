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
            contactShare.givenName = nameProto.givenName;
        }
        if (nameProto.hasFamilyName) {
            contactShare.familyName = nameProto.familyName;
        }
        if (nameProto.hasPrefix) {
            contactShare.namePrefix = nameProto.prefix;
        }
        if (nameProto.hasSuffix) {
            contactShare.nameSuffix = nameProto.suffix;
        }
        if (nameProto.hasMiddleName) {
            contactShare.middleName = nameProto.middleName;
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
        result.label = phoneNumberProto.label;
    }
    if (phoneNumberProto.hasValue) {
        result.phoneNumber = phoneNumberProto.value;
    } else {
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
        result.label = emailProto.label;
    }
    if (emailProto.hasValue) {
        result.email = emailProto.value;
    } else {
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
        result.label = addressProto.label;
    }
    if (addressProto.hasStreet) {
        result.street = addressProto.street;
    }
    if (addressProto.hasPobox) {
        result.pobox = addressProto.pobox;
    }
    if (addressProto.hasNeighborhood) {
        result.neighborhood = addressProto.neighborhood;
    }
    if (addressProto.hasCity) {
        result.city = addressProto.city;
    }
    if (addressProto.hasRegion) {
        result.region = addressProto.region;
    }
    if (addressProto.hasPostcode) {
        result.postcode = addressProto.postcode;
    }
    if (addressProto.hasCountry) {
        result.country = addressProto.country;
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

NS_ASSUME_NONNULL_END
