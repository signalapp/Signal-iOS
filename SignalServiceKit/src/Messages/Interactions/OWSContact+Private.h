//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSContact.h>

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

@property (nonatomic) NSArray<OWSContactPhoneNumber *> *phoneNumbers;
@property (nonatomic) NSArray<OWSContactEmail *> *emails;
@property (nonatomic) NSArray<OWSContactAddress *> *addresses;

@property (nonatomic) BOOL isProfileAvatar;

@end

NS_ASSUME_NONNULL_END
