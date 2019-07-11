//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Mantle/MTLModel.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * An adapter for the system contacts
 */

@class CNContact;
@class PhoneNumber;
@class SignalRecipient;
@class SignalServiceAddress;
@class UIImage;
@class YapDatabaseReadTransaction;

@interface Contact : MTLModel

@property (nullable, readonly, nonatomic) NSString *firstName;
@property (nullable, readonly, nonatomic) NSString *lastName;
@property (readonly, nonatomic) NSString *fullName;
@property (readonly, nonatomic) NSString *comparableNameFirstLast;
@property (readonly, nonatomic) NSString *comparableNameLastFirst;
@property (readonly, nonatomic) NSArray<PhoneNumber *> *parsedPhoneNumbers;
@property (readonly, nonatomic) NSArray<NSString *> *userTextPhoneNumbers;
@property (readonly, nonatomic) NSArray<NSString *> *emails;
@property (readonly, nonatomic) NSString *uniqueId;
@property (nonatomic, readonly) BOOL isSignalContact;
@property (nonatomic, readonly) NSString *cnContactId;

- (NSArray<SignalRecipient *> *)signalRecipientsWithTransaction:(YapDatabaseReadTransaction *)transaction;
// TODO: Remove this method.
- (NSArray<SignalServiceAddress *> *)registeredAddresses;

#if TARGET_OS_IOS

- (instancetype)initWithSystemContact:(CNContact *)cnContact NS_AVAILABLE_IOS(9_0);
+ (nullable Contact *)contactWithVCardData:(NSData *)data;
+ (nullable CNContact *)cnContactWithVCardData:(NSData *)data;

- (NSString *)nameForAddress:(SignalServiceAddress *)address;

#endif // TARGET_OS_IOS

+ (NSComparator)comparatorSortingNamesByFirstThenLast:(BOOL)firstNameOrdering;
+ (NSString *)formattedFullNameWithCNContact:(CNContact *)cnContact NS_SWIFT_NAME(formattedFullName(cnContact:));
+ (nullable NSString *)localizedStringForCNLabel:(nullable NSString *)cnLabel;

+ (CNContact *)mergeCNContact:(CNContact *)oldCNContact
                 newCNContact:(CNContact *)newCNContact NS_SWIFT_NAME(merge(cnContact:newCNContact:));

+ (nullable NSData *)avatarDataForCNContact:(nullable CNContact *)cnContact;

@end

NS_ASSUME_NONNULL_END
