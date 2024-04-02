//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Mantle/MTLModel.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * An adapter for the system contacts
 */

@class CNContact;

@interface Contact : MTLModel

@property (nullable, readonly, nonatomic) NSString *firstName;
@property (nullable, readonly, nonatomic) NSString *lastName;
@property (nullable, readonly, nonatomic) NSString *nickname;
@property (readonly, nonatomic) NSString *fullName;
@property (readonly, nonatomic) NSArray<NSString *> *userTextPhoneNumbers;
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *userTextPhoneNumberLabels;
@property (readonly, nonatomic) NSArray<NSString *> *emails;
@property (readonly, nonatomic) NSString *uniqueId;
@property (nonatomic, readonly, nullable) NSString *cnContactId;

@property (nonatomic, readonly) BOOL isFromLocalAddressBook;

#if TARGET_OS_IOS

- (instancetype)initWithSystemContact:(CNContact *)cnContact;

- (instancetype)initWithUniqueId:(NSString *)uniqueId
                     cnContactId:(nullable NSString *)cnContactId
                       firstName:(nullable NSString *)firstName
                        lastName:(nullable NSString *)lastName
                        nickname:(nullable NSString *)nickname
                        fullName:(NSString *)fullName
            userTextPhoneNumbers:(NSArray<NSString *> *)userTextPhoneNumbers
       userTextPhoneNumberLabels:(NSDictionary<NSString *, NSString *> *)userTextPhoneNumberLabels
                          emails:(NSArray<NSString *> *)emails NS_DESIGNATED_INITIALIZER;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (nullable Contact *)contactWithVCardData:(NSData *)data;
+ (nullable CNContact *)cnContactWithVCardData:(NSData *)data;

#endif // TARGET_OS_IOS

+ (NSString *)formattedFullNameWithCNContact:(CNContact *)cnContact NS_SWIFT_NAME(formattedFullName(cnContact:));
+ (nullable NSString *)localizedStringForCNLabel:(nullable NSString *)cnLabel;

+ (nullable NSData *)avatarDataForCNContact:(nullable CNContact *)cnContact;

@end

NS_ASSUME_NONNULL_END
