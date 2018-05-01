//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Mantle/MTLModel.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosDataMessage;
@class TSAttachment;
@class YapDatabaseReadWriteTransaction;

typedef NS_ENUM(NSUInteger, OWSContactSharePhoneType) {
    OWSContactSharePhoneType_Home = 1,
    OWSContactSharePhoneType_Mobile,
    OWSContactSharePhoneType_Work,
    OWSContactSharePhoneType_Custom,
};

@interface OWSContactSharePhoneNumber : MTLModel

@property (nonatomic, readonly) OWSContactSharePhoneType phoneType;
// Applies in the OWSContactSharePhoneType_Custom case.
@property (nonatomic, readonly, nullable) NSString *label;

@property (nonatomic, readonly) NSString *phoneNumber;

- (BOOL)isValid;

@end

#pragma mark -

typedef NS_ENUM(NSUInteger, OWSContactShareEmailType) {
    OWSContactShareEmailType_Home = 1,
    OWSContactShareEmailType_Mobile,
    OWSContactShareEmailType_Work,
    OWSContactShareEmailType_Custom,
};

@interface OWSContactShareEmail : MTLModel

@property (nonatomic, readonly) OWSContactShareEmailType emailType;
// Applies in the OWSContactShareEmailType_Custom case.
@property (nonatomic, readonly, nullable) NSString *label;

@property (nonatomic, readonly) NSString *email;

- (BOOL)isValid;

@end

#pragma mark -

typedef NS_ENUM(NSUInteger, OWSContactShareAddressType) {
    OWSContactShareAddressType_Home = 1,
    OWSContactShareAddressType_Work,
    OWSContactShareAddressType_Custom,
};

@interface OWSContactShareAddress : MTLModel

@property (nonatomic, readonly) OWSContactShareAddressType addressType;
// Applies in the OWSContactShareAddressType_Custom case.
@property (nonatomic, readonly, nullable) NSString *label;

@property (nonatomic, readonly, nullable) NSString *street;
@property (nonatomic, readonly, nullable) NSString *pobox;
@property (nonatomic, readonly, nullable) NSString *neighborhood;
@property (nonatomic, readonly, nullable) NSString *city;
@property (nonatomic, readonly, nullable) NSString *region;
@property (nonatomic, readonly, nullable) NSString *postcode;
@property (nonatomic, readonly, nullable) NSString *country;

- (BOOL)isValid;

@end

#pragma mark -

@interface OWSContactShare : MTLModel

@property (nonatomic, readonly, nullable) NSString *givenName;
@property (nonatomic, readonly, nullable) NSString *familyName;
@property (nonatomic, readonly, nullable) NSString *nameSuffix;
@property (nonatomic, readonly, nullable) NSString *namePrefix;
@property (nonatomic, readonly, nullable) NSString *middleName;

@property (nonatomic, readonly, nullable) NSArray<OWSContactSharePhoneNumber *> *phoneNumbers;
@property (nonatomic, readonly, nullable) NSArray<OWSContactShareEmail *> *emails;
@property (nonatomic, readonly, nullable) NSArray<OWSContactShareAddress *> *addresses;

// TODO: This is provisional.
@property (nonatomic, readonly, nullable) TSAttachment *avatar;
// "Profile" avatars should _not_ be saved to device contacts.
@property (nonatomic, readonly) BOOL isProfileAvatar;

- (instancetype)init NS_UNAVAILABLE;

+ (OWSContactShare *_Nullable)contactShareForDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
                                             transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (BOOL)isValid;

@end

#pragma mark -

@interface OWSContacts : NSObject

@end

NS_ASSUME_NONNULL_END
