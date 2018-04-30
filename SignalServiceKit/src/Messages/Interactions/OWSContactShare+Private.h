//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContactShare.h"

NS_ASSUME_NONNULL_BEGIN

// These private interfaces expose setter accessors to facilitate
// construction of fake messages, etc.
@interface OWSContactSharePhoneNumber (Private)

@property (nonatomic) OWSContactSharePhoneType phoneType;
@property (nonatomic, nullable) NSString *label;

@property (nonatomic) NSString *phoneNumber;

@end

#pragma mark -

@interface OWSContactShareEmail (Private)

@property (nonatomic) OWSContactShareEmailType emailType;
@property (nonatomic, nullable) NSString *label;

@property (nonatomic) NSString *email;

@end

#pragma mark -

@interface OWSContactShareAddress (Private)

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

@interface OWSContactShare (Private)

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

NS_ASSUME_NONNULL_END
