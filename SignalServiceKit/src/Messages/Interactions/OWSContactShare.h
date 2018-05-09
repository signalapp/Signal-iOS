//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Mantle/MTLModel.h>
#import <SignalServiceKit/ContactsManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

@class CNContact;
@class OWSAttachmentInfo;
@class OWSSignalServiceProtosDataMessage;
@class OWSSignalServiceProtosDataMessage;
@class OWSSignalServiceProtosDataMessageContact;
@class TSAttachment;
@class TSAttachmentStream;
@class YapDatabaseReadTransaction;
@class YapDatabaseReadWriteTransaction;

extern BOOL kIsSendingContactSharesEnabled;

typedef NS_ENUM(NSUInteger, OWSContactPhoneType) {
    OWSContactPhoneType_Home = 1,
    OWSContactPhoneType_Mobile,
    OWSContactPhoneType_Work,
    OWSContactPhoneType_Custom,
};

NSString *NSStringForContactPhoneType(OWSContactPhoneType value);

@protocol OWSContactField <NSObject>

- (BOOL)ows_isValid;

- (NSString *)localizedLabel;

- (NSString *)logDescription;

@end

#pragma mark -

@interface OWSContactPhoneNumber : MTLModel <OWSContactField>

@property (nonatomic) OWSContactPhoneType phoneType;
// Applies in the OWSContactPhoneType_Custom case.
@property (nonatomic, nullable) NSString *label;

@property (nonatomic) NSString *phoneNumber;

@end

#pragma mark -

typedef NS_ENUM(NSUInteger, OWSContactEmailType) {
    OWSContactEmailType_Home = 1,
    OWSContactEmailType_Mobile,
    OWSContactEmailType_Work,
    OWSContactEmailType_Custom,
};

NSString *NSStringForContactEmailType(OWSContactEmailType value);

@interface OWSContactEmail : MTLModel <OWSContactField>

@property (nonatomic) OWSContactEmailType emailType;
// Applies in the OWSContactEmailType_Custom case.
@property (nonatomic, nullable) NSString *label;

@property (nonatomic) NSString *email;

@end

#pragma mark -

typedef NS_ENUM(NSUInteger, OWSContactAddressType) {
    OWSContactAddressType_Home = 1,
    OWSContactAddressType_Work,
    OWSContactAddressType_Custom,
};

NSString *NSStringForContactAddressType(OWSContactAddressType value);

@interface OWSContactAddress : MTLModel <OWSContactField>

@property (nonatomic) OWSContactAddressType addressType;
// Applies in the OWSContactAddressType_Custom case.
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

@interface OWSContactName : MTLModel

@property (nonatomic, nullable) NSString *givenName;
@property (nonatomic, nullable) NSString *familyName;
@property (nonatomic, nullable) NSString *nameSuffix;
@property (nonatomic, nullable) NSString *namePrefix;
@property (nonatomic, nullable) NSString *middleName;
@property (nonatomic, nullable) NSString *organizationName;
@property (nonatomic) NSString *displayName;

@end

#pragma mark -

@interface OWSContactShareBase : MTLModel

@property (nonatomic) OWSContactName *name;

@property (nonatomic) NSArray<OWSContactPhoneNumber *> *phoneNumbers;
@property (nonatomic) NSArray<OWSContactEmail *> *emails;
@property (nonatomic) NSArray<OWSContactAddress *> *addresses;

// "Profile" avatars should _not_ be saved to device contacts.
@property (nonatomic) BOOL isProfileAvatar;
@property (nonatomic, readonly) BOOL hasAvatar;

- (void)normalize;

- (BOOL)ows_isValid;

- (NSString *)logDescription;

#pragma mark - Phone Numbers and Recipient IDs

- (NSArray<NSString *> *)systemContactsWithSignalAccountPhoneNumbers:(id<ContactsManagerProtocol>)contactsManager
    NS_SWIFT_NAME(systemContactsWithSignalAccountPhoneNumbers(_:));
- (NSArray<NSString *> *)systemContactPhoneNumbers:(id<ContactsManagerProtocol>)contactsManager
    NS_SWIFT_NAME(systemContactPhoneNumbers(_:));
- (NSArray<NSString *> *)e164PhoneNumbers NS_SWIFT_NAME(e164PhoneNumbers());

@end

#pragma mark -

@interface OWSContactShare : OWSContactShareBase

@property (nonatomic, nullable) NSString *avatarAttachmentId;

- (nullable TSAttachment *)avatarAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (void)saveAvatarImage:(UIImage *)image transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)saveAvatarData:(NSData *)rawAvatarData transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

#pragma mark -

@interface OWSContactShareProposed : OWSContactShareBase

@property (nonatomic, nullable) NSData *avatarData;

@end

#pragma mark -

@interface OWSContactConversion : NSObject

#pragma mark - VCard Serialization

+ (nullable CNContact *)systemContactForVCardData:(NSData *)data;
+ (nullable NSData *)vCardDataForSystemContact:(CNContact *)systemContact;

#pragma mark - System Contact Conversion

+ (nullable OWSContactShareProposed *)contactShareForSystemContact:(CNContact *)systemContact;
+ (nullable CNContact *)systemContactForContactShare:(OWSContactShare *)contact
                                         transaction:(YapDatabaseReadTransaction *)transaction;

#pragma mark -

+ (nullable OWSContactShareProposed *)contactShareForVCardData:(NSData *)data;
+ (nullable NSData *)vCardDataForContactShare:(OWSContactShare *)contact
                                  transaction:(YapDatabaseReadTransaction *)transaction;

#pragma mark - Proto Serialization

+ (nullable OWSSignalServiceProtosDataMessageContact *)protoForContactShare:(OWSContactShare *)contact;

+ (nullable OWSContactShare *)contactShareForDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
                                                   relay:(nullable NSString *)relay
                                             transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
