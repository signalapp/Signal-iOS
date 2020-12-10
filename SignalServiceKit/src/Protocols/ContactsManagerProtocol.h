//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class CNContact;
@class Contact;
@class NSPersonNameComponents;
@class PhoneNumber;
@class SDSAnyReadTransaction;
@class SignalAccount;
@class SignalServiceAddress;
@class TSThread;
@class UIImage;

typedef NSString *ConversationColorName NS_STRING_ENUM;

@protocol ContactsManagerProtocol <NSObject>

/// The name representing this address.
///
/// This will be the first of the following that exists for this address:
/// - The matching name from system contacts
/// - The name provided on the profile
/// - The address' phone number
/// - The address' UUID
- (NSString *)displayNameForAddress:(SignalServiceAddress *)address;
- (NSString *)displayNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;
- (NSString *)displayNameForSignalAccount:(SignalAccount *)signalAccount;

/// Returns the user's nickname / first name, if supported by the name's locale.
/// If we don't know the user's name components, falls back to displayNameForAddress:
///
/// The user can customize their short name preferences in the system settings app
/// to any of these variants which we respect:
///     * Given Name - Family Initial
///     * Family Name - Given Initial
///     * Given Name Only
///     * Family Name Only
///     * Prefer Nicknames
///     * Full Names Only
- (NSString *)shortDisplayNameForAddress:(SignalServiceAddress *)address
                             transaction:(SDSAnyReadTransaction *)transaction;

- (ConversationColorName)conversationColorNameForAddress:(SignalServiceAddress *)address
                                             transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSPersonNameComponents *)nameComponentsForAddress:(SignalServiceAddress *)address;
- (nullable NSPersonNameComponents *)nameComponentsForAddress:(SignalServiceAddress *)address
                                                  transaction:(SDSAnyReadTransaction *)transaction;

- (NSString *)displayNameForThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;
- (NSString *)displayNameForThreadWithSneakyTransaction:(TSThread *)thread
    NS_SWIFT_NAME(displayNameWithSneakyTransaction(thread:));

- (NSArray<SignalAccount *> *)signalAccounts;

- (BOOL)isSystemContactWithPhoneNumber:(NSString *)phoneNumber NS_SWIFT_NAME(isSystemContact(phoneNumber:));
- (BOOL)isSystemContactWithAddress:(SignalServiceAddress *)address NS_SWIFT_NAME(isSystemContact(address:));
- (BOOL)isSystemContactWithSignalAccount:(NSString *)phoneNumber;
- (BOOL)isSystemContactWithSignalAccount:(NSString *)phoneNumber transaction:(SDSAnyReadTransaction *)transaction;
- (BOOL)hasNameInSystemContactsForAddress:(SignalServiceAddress *)address;
- (BOOL)hasNameInSystemContactsForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction;

- (NSString *)comparableNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;
- (NSString *)comparableNameForSignalAccount:(SignalAccount *)signalAccount
                                 transaction:(SDSAnyReadTransaction *)transaction;

@property (nonatomic, readonly) NSString *unknownUserLabel;

#pragma mark - CNContacts

- (nullable CNContact *)cnContactWithId:(nullable NSString *)contactId;
- (nullable NSData *)avatarDataForCNContactId:(nullable NSString *)contactId;
- (nullable UIImage *)avatarImageForCNContactId:(nullable NSString *)contactId;

@end

NS_ASSUME_NONNULL_END
