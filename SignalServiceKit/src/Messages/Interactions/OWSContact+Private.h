//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContact.h"

NS_ASSUME_NONNULL_BEGIN

// These private interfaces expose setter accessors to facilitate
// construction of fake messages, etc.
@interface OWSContactPhoneNumber (Private)

@property (nonatomic) OWSContactPhoneType phoneType;
@property (nonatomic, nullable) NSString *label;

@property (nonatomic) NSString *phoneNumber;

@end

#pragma mark -

@interface OWSContactEmail (Private)

@property (nonatomic) OWSContactEmailType emailType;
@property (nonatomic, nullable) NSString *label;

@property (nonatomic) NSString *email;

@end

#pragma mark -

@interface OWSContactAddress (Private)

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

@interface OWSContact (Private)

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

NS_ASSUME_NONNULL_END
