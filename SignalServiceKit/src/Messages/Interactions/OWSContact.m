//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContact.h"
#import "Contact.h"
#import "MimeTypeUtil.h"
#import "NSString+SSK.h"
#import "OWSContact+Private.h"
#import "PhoneNumber.h"
#import "TSAttachment.h"
#import "TSAttachmentPointer.h"
#import "TSAttachmentStream.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabaseTransaction.h>

@import Contacts;

NS_ASSUME_NONNULL_BEGIN

// NOTE: When changing the value of this feature flag, you also need
// to update the filtering in the SAE's info.plist.
BOOL kIsSendingContactSharesEnabled = YES;

NSString *NSStringForContactPhoneType(OWSContactPhoneType value)
{
    switch (value) {
        case OWSContactPhoneType_Home:
            return @"Home";
        case OWSContactPhoneType_Mobile:
            return @"Mobile";
        case OWSContactPhoneType_Work:
            return @"Work";
        case OWSContactPhoneType_Custom:
            return @"Custom";
    }
}

@interface OWSContactPhoneNumber ()

@property (nonatomic) OWSContactPhoneType phoneType;
@property (nonatomic, nullable) NSString *label;

@property (nonatomic) NSString *phoneNumber;

@end

#pragma mark -

@implementation OWSContactPhoneNumber

- (BOOL)ows_isValid
{
    if (self.phoneNumber.ows_stripped.length < 1) {
        OWSLogWarn(@"invalid phone number: %@.", self.phoneNumber);
        return NO;
    }
    return YES;
}

- (NSString *)localizedLabel
{
    switch (self.phoneType) {
        case OWSContactPhoneType_Home:
            return [CNLabeledValue localizedStringForLabel:CNLabelHome];
        case OWSContactPhoneType_Mobile:
            return [CNLabeledValue localizedStringForLabel:CNLabelPhoneNumberMobile];
        case OWSContactPhoneType_Work:
            return [CNLabeledValue localizedStringForLabel:CNLabelWork];
        default:
            if (self.label.ows_stripped.length < 1) {
                return NSLocalizedString(@"CONTACT_PHONE", @"Label for a contact's phone number.");
            }
            return self.label.ows_stripped;
    }
}

- (NSString *)debugDescription
{
    NSMutableString *result = [NSMutableString new];
    [result appendFormat:@"[Phone Number: %@, ", NSStringForContactPhoneType(self.phoneType)];

    if (self.label.length > 0) {
        [result appendFormat:@"label: %@, ", self.label];
    }
    if (self.phoneNumber.length > 0) {
        [result appendFormat:@"phoneNumber: %@, ", self.phoneNumber];
    }

    [result appendString:@"]"];
    return result;
}

- (nullable NSString *)tryToConvertToE164
{
    PhoneNumber *_Nullable parsedPhoneNumber;
    parsedPhoneNumber = [PhoneNumber tryParsePhoneNumberFromE164:self.phoneNumber];
    if (!parsedPhoneNumber) {
        parsedPhoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:self.phoneNumber];
    }
    if (parsedPhoneNumber) {
        return parsedPhoneNumber.toE164;
    }
    return nil;
}

@end

#pragma mark -

NSString *NSStringForContactEmailType(OWSContactEmailType value)
{
    switch (value) {
        case OWSContactEmailType_Home:
            return @"Home";
        case OWSContactEmailType_Mobile:
            return @"Mobile";
        case OWSContactEmailType_Work:
            return @"Work";
        case OWSContactEmailType_Custom:
            return @"Custom";
    }
}

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
        OWSLogWarn(@"invalid email: %@.", self.email);
        return NO;
    }
    return YES;
}

- (NSString *)localizedLabel
{
    switch (self.emailType) {
        case OWSContactEmailType_Home:
            return [CNLabeledValue localizedStringForLabel:CNLabelHome];
        case OWSContactEmailType_Mobile:
            return [CNLabeledValue localizedStringForLabel:CNLabelPhoneNumberMobile];
        case OWSContactEmailType_Work:
            return [CNLabeledValue localizedStringForLabel:CNLabelWork];
        default:
            if (self.label.ows_stripped.length < 1) {
                return NSLocalizedString(@"CONTACT_EMAIL", @"Label for a contact's email address.");
            }
            return self.label.ows_stripped;
    }
}

- (NSString *)debugDescription
{
    NSMutableString *result = [NSMutableString new];
    [result appendFormat:@"[Email: %@, ", NSStringForContactEmailType(self.emailType)];

    if (self.label.length > 0) {
        [result appendFormat:@"label: %@, ", self.label];
    }
    if (self.email.length > 0) {
        [result appendFormat:@"email: %@, ", self.email];
    }

    [result appendString:@"]"];
    return result;
}

@end

#pragma mark -

NSString *NSStringForContactAddressType(OWSContactAddressType value)
{
    switch (value) {
        case OWSContactAddressType_Home:
            return @"Home";
        case OWSContactAddressType_Work:
            return @"Work";
        case OWSContactAddressType_Custom:
            return @"Custom";
    }
}
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
        OWSLogWarn(@"invalid address; empty.");
        return NO;
    }
    return YES;
}

- (NSString *)localizedLabel
{
    switch (self.addressType) {
        case OWSContactAddressType_Home:
            return [CNLabeledValue localizedStringForLabel:CNLabelHome];
        case OWSContactAddressType_Work:
            return [CNLabeledValue localizedStringForLabel:CNLabelWork];
        default:
            if (self.label.ows_stripped.length < 1) {
                return NSLocalizedString(@"CONTACT_ADDRESS", @"Label for a contact's postal address.");
            }
            return self.label.ows_stripped;
    }
}

- (NSString *)debugDescription
{
    NSMutableString *result = [NSMutableString new];
    [result appendFormat:@"[Address: %@, ", NSStringForContactAddressType(self.addressType)];

    if (self.label.length > 0) {
        [result appendFormat:@"label: %@, ", self.label];
    }
    if (self.street.length > 0) {
        [result appendFormat:@"street: %@, ", self.street];
    }
    if (self.pobox.length > 0) {
        [result appendFormat:@"pobox: %@, ", self.pobox];
    }
    if (self.neighborhood.length > 0) {
        [result appendFormat:@"neighborhood: %@, ", self.neighborhood];
    }
    if (self.city.length > 0) {
        [result appendFormat:@"city: %@, ", self.city];
    }
    if (self.region.length > 0) {
        [result appendFormat:@"region: %@, ", self.region];
    }
    if (self.postcode.length > 0) {
        [result appendFormat:@"postcode: %@, ", self.postcode];
    }
    if (self.country.length > 0) {
        [result appendFormat:@"country: %@, ", self.country];
    }

    [result appendString:@"]"];
    return result;
}

@end

#pragma mark -

@implementation OWSContactName

- (NSString *)logDescription
{
    NSMutableString *result = [NSMutableString new];
    [result appendString:@"["];

    if (self.givenName.length > 0) {
        [result appendFormat:@"givenName: %@, ", self.givenName];
    }
    if (self.familyName.length > 0) {
        [result appendFormat:@"familyName: %@, ", self.familyName];
    }
    if (self.middleName.length > 0) {
        [result appendFormat:@"middleName: %@, ", self.middleName];
    }
    if (self.namePrefix.length > 0) {
        [result appendFormat:@"namePrefix: %@, ", self.namePrefix];
    }
    if (self.nameSuffix.length > 0) {
        [result appendFormat:@"nameSuffix: %@, ", self.nameSuffix];
    }
    if (self.displayName.length > 0) {
        [result appendFormat:@"displayName: %@, ", self.displayName];
    }

    [result appendString:@"]"];
    return result;
}

- (NSString *)displayName
{
    [self ensureDisplayName];

    if (_displayName.length < 1) {
        OWSFailDebug(@"could not derive a valid display name.");
        return NSLocalizedString(@"CONTACT_WITHOUT_NAME", @"Indicates that a contact has no name.");
    }
    return _displayName;
}

- (void)ensureDisplayName
{
    if (_displayName.length < 1) {
        CNContact *_Nullable cnContact = [self systemContactForName];
        _displayName = [CNContactFormatter stringFromContact:cnContact style:CNContactFormatterStyleFullName];
    }
    if (_displayName.length < 1) {
        // Fall back to using the organization name.
        _displayName = self.organizationName;
    }
}

- (void)updateDisplayName
{
    _displayName = nil;

    [self ensureDisplayName];
}

- (nullable CNContact *)systemContactForName
{
    CNMutableContact *systemContact = [CNMutableContact new];
    systemContact.givenName = self.givenName.ows_stripped;
    systemContact.middleName = self.middleName.ows_stripped;
    systemContact.familyName = self.familyName.ows_stripped;
    systemContact.namePrefix = self.namePrefix.ows_stripped;
    systemContact.nameSuffix = self.nameSuffix.ows_stripped;
    // We don't need to set display name, it's implicit for system contacts.
    systemContact.organizationName = self.organizationName.ows_stripped;
    return systemContact;
}

- (BOOL)hasAnyNamePart
{
    return (self.givenName.ows_stripped.length > 0 || self.middleName.ows_stripped.length > 0
        || self.familyName.ows_stripped.length > 0 || self.namePrefix.ows_stripped.length > 0
        || self.nameSuffix.ows_stripped.length > 0);
}

@end

#pragma mark -

@interface OWSContact ()

@property (nonatomic) NSArray<OWSContactPhoneNumber *> *phoneNumbers;
@property (nonatomic) NSArray<OWSContactEmail *> *emails;
@property (nonatomic) NSArray<OWSContactAddress *> *addresses;

@property (nonatomic, nullable) NSString *avatarAttachmentId;
@property (nonatomic) BOOL isProfileAvatar;

@property (nonatomic, nullable) NSArray<NSString *> *e164PhoneNumbersCached;

@end

#pragma mark -

@implementation OWSContact

- (instancetype)init
{
    if (self = [super init]) {
        _name = [OWSContactName new];
        _phoneNumbers = @[];
        _emails = @[];
        _addresses = @[];
    }

    return self;
}

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
    if (self.name.displayName.ows_stripped.length < 1) {
        OWSLogWarn(@"invalid contact; no display name.");
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

- (NSString *)debugDescription
{
    NSMutableString *result = [NSMutableString new];
    [result appendString:@"["];

    [result appendFormat:@"%@, ", self.name.logDescription];

    for (OWSContactPhoneNumber *phoneNumber in self.phoneNumbers) {
        [result appendFormat:@"%@, ", phoneNumber.debugDescription];
    }
    for (OWSContactEmail *email in self.emails) {
        [result appendFormat:@"%@, ", email.debugDescription];
    }
    for (OWSContactAddress *address in self.addresses) {
        [result appendFormat:@"%@, ", address.debugDescription];
    }

    [result appendString:@"]"];
    return result;
}

- (OWSContact *)newContactWithName:(OWSContactName *)name
{
    OWSAssertDebug(name);

    OWSContact *newContact = [OWSContact new];

    newContact.name = name;

    [name updateDisplayName];

    return newContact;
}

- (OWSContact *)copyContactWithName:(OWSContactName *)name
{
    OWSAssertDebug(name);

    OWSContact *contactCopy = [self copy];

    contactCopy.name = name;

    [name updateDisplayName];

    return contactCopy;
}

#pragma mark - Avatar

- (nullable TSAttachment *)avatarAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return [TSAttachment fetchObjectWithUniqueID:self.avatarAttachmentId transaction:transaction];
}


- (void)saveAvatarImage:(UIImage *)image transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSData *imageData = UIImageJPEGRepresentation(image, (CGFloat)0.9);

    TSAttachmentStream *attachmentStream = [[TSAttachmentStream alloc] initWithContentType:OWSMimeTypeImageJpeg
                                                                                 byteCount:(UInt32)imageData.length
                                                                            sourceFilename:nil];

    NSError *error;
    BOOL success = [attachmentStream writeData:imageData error:&error];
    OWSAssertDebug(success && !error);

    [attachmentStream saveWithTransaction:transaction];
    self.avatarAttachmentId = attachmentStream.uniqueId;
}

- (void)removeAvatarAttachmentWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    TSAttachmentStream *_Nullable attachment =
        [TSAttachmentStream fetchObjectWithUniqueID:self.avatarAttachmentId transaction:transaction];
    [attachment removeWithTransaction:transaction];
}

#pragma mark - Phone Numbers and Recipient IDs

- (NSArray<NSString *> *)systemContactsWithSignalAccountPhoneNumbers:(id<ContactsManagerProtocol>)contactsManager
{
    OWSAssertDebug(contactsManager);

    return [self.e164PhoneNumbers
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *_Nullable recipientId,
                                        NSDictionary<NSString *, id> *_Nullable bindings) {
            return [contactsManager isSystemContactWithSignalAccount:recipientId];
        }]];
}

- (NSArray<NSString *> *)systemContactPhoneNumbers:(id<ContactsManagerProtocol>)contactsManager
{
    OWSAssertDebug(contactsManager);

    return [self.e164PhoneNumbers
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *_Nullable recipientId,
                                        NSDictionary<NSString *, id> *_Nullable bindings) {
            return [contactsManager isSystemContact:recipientId];
        }]];
}

- (NSArray<NSString *> *)e164PhoneNumbers
{
    if (self.e164PhoneNumbersCached) {
        return self.e164PhoneNumbersCached;
    }
    NSMutableArray<NSString *> *e164PhoneNumbers = [NSMutableArray new];
    for (OWSContactPhoneNumber *phoneNumber in self.phoneNumbers) {
        PhoneNumber *_Nullable parsedPhoneNumber;
        parsedPhoneNumber = [PhoneNumber tryParsePhoneNumberFromE164:phoneNumber.phoneNumber];
        if (!parsedPhoneNumber) {
            parsedPhoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumber.phoneNumber];
        }
        if (parsedPhoneNumber) {
            [e164PhoneNumbers addObject:parsedPhoneNumber.toE164];
        }
    }
    self.e164PhoneNumbersCached = e164PhoneNumbers;
    return e164PhoneNumbers;
}

@end

#pragma mark -

@implementation OWSContacts

#pragma mark - System Contact Conversion

// `contactForSystemContact` does *not* handle avatars. That must be delt with by the caller
+ (nullable OWSContact *)contactForSystemContact:(CNContact *)systemContact
{
    if (!systemContact) {
        OWSFailDebug(@"Missing contact.");
        return nil;
    }

    OWSContact *contact = [OWSContact new];

    OWSContactName *contactName = [OWSContactName new];
    contactName.givenName = systemContact.givenName.ows_stripped;
    contactName.middleName = systemContact.middleName.ows_stripped;
    contactName.familyName = systemContact.familyName.ows_stripped;
    contactName.namePrefix = systemContact.namePrefix.ows_stripped;
    contactName.nameSuffix = systemContact.nameSuffix.ows_stripped;
    contactName.organizationName = systemContact.organizationName.ows_stripped;
    [contactName ensureDisplayName];
    contact.name = contactName;

    NSMutableArray<OWSContactPhoneNumber *> *phoneNumbers = [NSMutableArray new];
    for (CNLabeledValue<CNPhoneNumber *> *phoneNumberField in systemContact.phoneNumbers) {
        OWSContactPhoneNumber *phoneNumber = [OWSContactPhoneNumber new];

        // Make a best effort to parse the phone number to e164.
        NSString *unparsedPhoneNumber = phoneNumberField.value.stringValue;
        PhoneNumber *_Nullable parsedPhoneNumber;
        parsedPhoneNumber = [PhoneNumber tryParsePhoneNumberFromE164:unparsedPhoneNumber];
        if (!parsedPhoneNumber) {
            parsedPhoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:unparsedPhoneNumber];
        }
        if (parsedPhoneNumber) {
            phoneNumber.phoneNumber = parsedPhoneNumber.toE164;
        } else {
            phoneNumber.phoneNumber = unparsedPhoneNumber;
        }

        if ([phoneNumberField.label isEqualToString:CNLabelHome]) {
            phoneNumber.phoneType = OWSContactPhoneType_Home;
        } else if ([phoneNumberField.label isEqualToString:CNLabelWork]) {
            phoneNumber.phoneType = OWSContactPhoneType_Work;
        } else if ([phoneNumberField.label isEqualToString:CNLabelPhoneNumberMobile]) {
            phoneNumber.phoneType = OWSContactPhoneType_Mobile;
        } else {
            phoneNumber.phoneType = OWSContactPhoneType_Custom;
            phoneNumber.label = [Contact localizedStringForCNLabel:phoneNumberField.label];
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
            email.label = [Contact localizedStringForCNLabel:emailField.label];
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
            address.label = [Contact localizedStringForCNLabel:addressField.label];
        }
        [addresses addObject:address];
    }
    contact.addresses = addresses;

    return contact;
}

+ (nullable CNContact *)systemContactForContact:(OWSContact *)contact imageData:(nullable NSData *)imageData
{
    if (!contact) {
        OWSFailDebug(@"Missing contact.");
        return nil;
    }

    CNMutableContact *systemContact = [CNMutableContact new];

    systemContact.givenName = contact.name.givenName;
    systemContact.middleName = contact.name.middleName;
    systemContact.familyName = contact.name.familyName;
    systemContact.namePrefix = contact.name.namePrefix;
    systemContact.nameSuffix = contact.name.nameSuffix;
    // We don't need to set display name, it's implicit for system contacts.
    systemContact.organizationName = contact.name.organizationName;

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
    systemContact.imageData = imageData;

    return systemContact;
}

#pragma mark - Proto Serialization

+ (nullable SSKProtoDataMessageContact *)protoForContact:(OWSContact *)contact
{
    OWSAssertDebug(contact);

    SSKProtoDataMessageContactBuilder *contactBuilder =
        [SSKProtoDataMessageContactBuilder new];

    SSKProtoDataMessageContactNameBuilder *nameBuilder =
        [SSKProtoDataMessageContactNameBuilder new];

    OWSContactName *contactName = contact.name;
    if (contactName.givenName.ows_stripped.length > 0) {
        nameBuilder.givenName = contactName.givenName.ows_stripped;
    }
    if (contactName.familyName.ows_stripped.length > 0) {
        nameBuilder.familyName = contactName.familyName.ows_stripped;
    }
    if (contactName.middleName.ows_stripped.length > 0) {
        nameBuilder.middleName = contactName.middleName.ows_stripped;
    }
    if (contactName.namePrefix.ows_stripped.length > 0) {
        nameBuilder.prefix = contactName.namePrefix.ows_stripped;
    }
    if (contactName.nameSuffix.ows_stripped.length > 0) {
        nameBuilder.suffix = contactName.nameSuffix.ows_stripped;
    }
    if (contactName.organizationName.ows_stripped.length > 0) {
        contactBuilder.organization = contactName.organizationName.ows_stripped;
    }
    nameBuilder.displayName = contactName.displayName;

    NSError *error;
    SSKProtoDataMessageContactName *_Nullable nameProto = [nameBuilder buildAndReturnError:&error];
    if (error || !nameProto) {
        OWSLogError(@"could not build protobuf: %@", error);
    } else {
        [contactBuilder setName:nameProto];
    }

    for (OWSContactPhoneNumber *phoneNumber in contact.phoneNumbers) {
        SSKProtoDataMessageContactPhoneBuilder *phoneBuilder =
            [SSKProtoDataMessageContactPhoneBuilder new];
        phoneBuilder.value = phoneNumber.phoneNumber;
        if (phoneNumber.label.ows_stripped.length > 0) {
            phoneBuilder.label = phoneNumber.label.ows_stripped;
        }
        switch (phoneNumber.phoneType) {
            case OWSContactPhoneType_Home:
                phoneBuilder.type = SSKProtoDataMessageContactPhoneTypeHome;
                break;
            case OWSContactPhoneType_Mobile:
                phoneBuilder.type = SSKProtoDataMessageContactPhoneTypeMobile;
                break;
            case OWSContactPhoneType_Work:
                phoneBuilder.type = SSKProtoDataMessageContactPhoneTypeWork;
                break;
            case OWSContactPhoneType_Custom:
                phoneBuilder.type = SSKProtoDataMessageContactPhoneTypeCustom;
                break;
        }
        SSKProtoDataMessageContactPhone *_Nullable numberProto = [phoneBuilder buildAndReturnError:&error];
        if (error || !numberProto) {
            OWSLogError(@"could not build protobuf: %@", error);
        } else {
            [contactBuilder addNumber:numberProto];
        }
    }

    for (OWSContactEmail *email in contact.emails) {
        SSKProtoDataMessageContactEmailBuilder *emailBuilder =
            [SSKProtoDataMessageContactEmailBuilder new];
        emailBuilder.value = email.email;
        if (email.label.ows_stripped.length > 0) {
            emailBuilder.label = email.label.ows_stripped;
        }
        switch (email.emailType) {
            case OWSContactEmailType_Home:
                emailBuilder.type = SSKProtoDataMessageContactEmailTypeHome;
                break;
            case OWSContactEmailType_Mobile:
                emailBuilder.type = SSKProtoDataMessageContactEmailTypeMobile;
                break;
            case OWSContactEmailType_Work:
                emailBuilder.type = SSKProtoDataMessageContactEmailTypeWork;
                break;
            case OWSContactEmailType_Custom:
                emailBuilder.type = SSKProtoDataMessageContactEmailTypeCustom;
                break;
        }
        SSKProtoDataMessageContactEmail *_Nullable emailProto = [emailBuilder buildAndReturnError:&error];
        if (error || !emailProto) {
            OWSLogError(@"could not build protobuf: %@", error);
        } else {
            [contactBuilder addEmail:emailProto];
        }
    }

    for (OWSContactAddress *address in contact.addresses) {
        SSKProtoDataMessageContactPostalAddressBuilder *addressBuilder =
            [SSKProtoDataMessageContactPostalAddressBuilder new];
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
        SSKProtoDataMessageContactPostalAddress *_Nullable addressProto = [addressBuilder buildAndReturnError:&error];
        if (error || !addressProto) {
            OWSLogError(@"could not build protobuf: %@", error);
        } else {
            [contactBuilder addAddress:addressProto];
        }
    }

    if (contact.avatarAttachmentId) {
        SSKProtoAttachmentPointer *_Nullable attachmentProto =
            [TSAttachmentStream buildProtoForAttachmentId:contact.avatarAttachmentId];
        if (!attachmentProto) {
            OWSLogError(@"could not build protobuf: %@", error);
        } else {
            SSKProtoDataMessageContactAvatarBuilder *avatarBuilder = [SSKProtoDataMessageContactAvatarBuilder new];
            avatarBuilder.avatar = attachmentProto;
            SSKProtoDataMessageContactAvatar *_Nullable avatarProto = [avatarBuilder buildAndReturnError:&error];
            if (error || !avatarProto) {
                OWSLogError(@"could not build protobuf: %@", error);
            } else {
                contactBuilder.avatar = avatarProto;
            }
        }
    }

    SSKProtoDataMessageContact *_Nullable contactProto = [contactBuilder buildAndReturnError:&error];
    if (error || !contactProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }
    if (contactProto.number.count < 1 && contactProto.email.count < 1 && contactProto.address.count < 1) {
        OWSFailDebug(@"contact has neither phone, email or address.");
        return nil;
    }
    return contactProto;
}

+ (nullable OWSContact *)contactForDataMessage:(SSKProtoDataMessage *)dataMessage
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(dataMessage);

    if (dataMessage.contact.count < 1) {
        return nil;
    }
    OWSAssertDebug(dataMessage.contact.count == 1);
    SSKProtoDataMessageContact *contactProto = dataMessage.contact.firstObject;

    OWSContact *contact = [OWSContact new];

    OWSContactName *contactName = [OWSContactName new];
    if (contactProto.name) {
        SSKProtoDataMessageContactName *nameProto = contactProto.name;

        if (nameProto.givenName) {
            contactName.givenName = nameProto.givenName.ows_stripped;
        }
        if (nameProto.familyName) {
            contactName.familyName = nameProto.familyName.ows_stripped;
        }
        if (nameProto.prefix) {
            contactName.namePrefix = nameProto.prefix.ows_stripped;
        }
        if (nameProto.suffix) {
            contactName.nameSuffix = nameProto.suffix.ows_stripped;
        }
        if (nameProto.middleName) {
            contactName.middleName = nameProto.middleName.ows_stripped;
        }
        if (nameProto.displayName) {
            contactName.displayName = nameProto.displayName.ows_stripped;
        }
    }
    if (contactProto.organization) {
        contactName.organizationName = contactProto.organization.ows_stripped;
    }
    [contactName ensureDisplayName];
    contact.name = contactName;

    NSMutableArray<OWSContactPhoneNumber *> *phoneNumbers = [NSMutableArray new];
    for (SSKProtoDataMessageContactPhone *phoneNumberProto in contactProto.number) {
        OWSContactPhoneNumber *_Nullable phoneNumber = [self phoneNumberForProto:phoneNumberProto];
        if (phoneNumber) {
            [phoneNumbers addObject:phoneNumber];
        }
    }
    contact.phoneNumbers = [phoneNumbers copy];

    NSMutableArray<OWSContactEmail *> *emails = [NSMutableArray new];
    for (SSKProtoDataMessageContactEmail *emailProto in contactProto.email) {
        OWSContactEmail *_Nullable email = [self emailForProto:emailProto];
        if (email) {
            [emails addObject:email];
        }
    }
    contact.emails = [emails copy];

    NSMutableArray<OWSContactAddress *> *addresses = [NSMutableArray new];
    for (SSKProtoDataMessageContactPostalAddress *addressProto in contactProto.address) {
        OWSContactAddress *_Nullable address = [self addressForProto:addressProto];
        if (address) {
            [addresses addObject:address];
        }
    }
    contact.addresses = [addresses copy];

    if (contactProto.avatar) {
        SSKProtoDataMessageContactAvatar *avatarInfo = contactProto.avatar;

        if (avatarInfo.avatar) {
            SSKProtoAttachmentPointer *avatarAttachment = avatarInfo.avatar;

            TSAttachmentPointer *_Nullable attachmentPointer =
                [TSAttachmentPointer attachmentPointerFromProto:avatarAttachment];
            if (attachmentPointer) {
                [attachmentPointer saveWithTransaction:transaction];
                contact.avatarAttachmentId = attachmentPointer.uniqueId;
                contact.isProfileAvatar = avatarInfo.isProfile;
            } else {
                OWSFailDebug(@"Invalid avatar attachment.");
            }
        } else {
            OWSFailDebug(@"avatarInfo.hasAvatar was unexpectedly false");
        }
    }


    return contact;
}

+ (nullable OWSContactPhoneNumber *)phoneNumberForProto:
    (SSKProtoDataMessageContactPhone *)phoneNumberProto
{
    OWSContactPhoneNumber *result = [OWSContactPhoneNumber new];
    result.phoneType = OWSContactPhoneType_Custom;
    if (phoneNumberProto.hasType) {
        switch (phoneNumberProto.type) {
            case SSKProtoDataMessageContactPhoneTypeHome:
                result.phoneType = OWSContactPhoneType_Home;
                break;
            case SSKProtoDataMessageContactPhoneTypeMobile:
                result.phoneType = OWSContactPhoneType_Mobile;
                break;
            case SSKProtoDataMessageContactPhoneTypeWork:
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

+ (nullable OWSContactEmail *)emailForProto:(SSKProtoDataMessageContactEmail *)emailProto
{
    OWSContactEmail *result = [OWSContactEmail new];
    result.emailType = OWSContactEmailType_Custom;
    if (emailProto.hasType) {
        switch (emailProto.type) {
            case SSKProtoDataMessageContactEmailTypeHome:
                result.emailType = OWSContactEmailType_Home;
                break;
            case SSKProtoDataMessageContactEmailTypeMobile:
                result.emailType = OWSContactEmailType_Mobile;
                break;
            case SSKProtoDataMessageContactEmailTypeWork:
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

+ (nullable OWSContactAddress *)addressForProto:(SSKProtoDataMessageContactPostalAddress *)addressProto
{
    OWSContactAddress *result = [OWSContactAddress new];
    result.addressType = OWSContactAddressType_Custom;
    if (addressProto.hasType) {
        switch (addressProto.type) {
            case SSKProtoDataMessageContactPostalAddressTypeHome:
                result.addressType = OWSContactAddressType_Home;
                break;
            case SSKProtoDataMessageContactPostalAddressTypeWork:
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
