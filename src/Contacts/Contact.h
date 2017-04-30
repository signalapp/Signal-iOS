//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <AddressBook/AddressBook.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, OWSPhoneNumberType) {
    OWSPhoneNumberTypeUnknown,
    OWSPhoneNumberTypeMobile,
    OWSPhoneNumberTypeIPhone,
    OWSPhoneNumberTypeMain,
    OWSPhoneNumberTypeHomeFAX,
    OWSPhoneNumberTypeWorkFAX,
    OWSPhoneNumberTypeOtherFAX,
    OWSPhoneNumberTypePager,
};

/**
 *
 * Contact represents relevant information related to a contact from the user's
 * contact list.
 *
 */

@class CNContact;
@class PhoneNumber;
@class UIImage;

@interface Contact : NSObject

@property (nullable, readonly, nonatomic) NSString *firstName;
@property (nullable, readonly, nonatomic) NSString *lastName;
@property (readonly, nonatomic) NSString *fullName;
@property (readonly, nonatomic) NSString *comparableNameFirstLast;
@property (readonly, nonatomic) NSString *comparableNameLastFirst;
@property (readonly, nonatomic) NSArray<PhoneNumber *> *parsedPhoneNumbers;
@property (readonly, nonatomic) NSArray<NSString *> *userTextPhoneNumbers;
@property (readonly, nonatomic) NSArray<NSString *> *emails;
@property (readonly, nonatomic) NSString *uniqueId;
#if TARGET_OS_IOS
@property (nullable, readonly, nonatomic) UIImage *image;
@property (readonly, nonatomic) ABRecordID recordID;
@property (nullable, nonatomic, readonly) CNContact *cnContact;
#endif // TARGET_OS_IOS

- (BOOL)isSignalContact;
- (NSArray<NSString *> *)textSecureIdentifiers;

#if TARGET_OS_IOS

- (instancetype)initWithContactWithFirstName:(nullable NSString *)firstName
                                 andLastName:(nullable NSString *)lastName
                     andUserTextPhoneNumbers:(NSArray<NSString *> *)phoneNumbers
                          phoneNumberTypeMap:(nullable NSDictionary<NSString *, NSNumber *> *)phoneNumberTypeMap
                                    andImage:(nullable UIImage *)image
                                andContactID:(ABRecordID)record;

- (instancetype)initWithContact:(CNContact *)contact;

- (OWSPhoneNumberType)phoneNumberTypeForPhoneNumber:(NSString *)recipientId;

#endif // TARGET_OS_IOS

+ (NSComparator)comparatorSortingNamesByFirstThenLast:(BOOL)firstNameOrdering;

@end

NS_ASSUME_NONNULL_END
