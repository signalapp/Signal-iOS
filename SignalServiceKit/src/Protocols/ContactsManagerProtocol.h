//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class CNContact;
@class Contact;
@class ModelReadCacheSizeLease;
@class NSPersonNameComponents;
@class PhoneNumber;
@class SDSAnyReadTransaction;
@class SignalAccount;
@class SignalServiceAddress;
@class TSThread;
@class UIImage;

@protocol ContactsManagerProtocol <NSObject>

/// Get the ``SignalAccount`` backed by the given address, if any.
- (nullable SignalAccount *)fetchSignalAccountForAddress:(SignalServiceAddress *)address
                                             transaction:(SDSAnyReadTransaction *)transaction;
/// The name representing this address.
///
/// This will be the first of the following that exists for this address:
/// - The matching name from system contacts
/// - The name provided on the profile
/// - The address' phone number
/// - The address' UUID
- (NSString *)displayNameForAddress:(SignalServiceAddress *)address;
- (NSString *)displayNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

- (NSArray<NSString *> *)displayNamesForAddresses:(NSArray<SignalServiceAddress *> *)addresses
                                      transaction:(SDSAnyReadTransaction *)transaction;

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

- (nullable NSPersonNameComponents *)nameComponentsForAddress:(SignalServiceAddress *)address
                                                  transaction:(SDSAnyReadTransaction *)transaction;

- (NSString *)displayNameForThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;
- (NSString *)displayNameForThreadWithSneakyTransaction:(TSThread *)thread
    NS_SWIFT_NAME(displayNameWithSneakyTransaction(thread:));

- (BOOL)isSystemContactWithPhoneNumberWithSneakyTransaction:(NSString *)phoneNumber NS_SWIFT_NAME(isSystemContactWithSneakyTransaction(phoneNumber:));
- (BOOL)isSystemContactWithPhoneNumber:(NSString *)phoneNumber
                           transaction:(SDSAnyReadTransaction *)transaction NS_SWIFT_NAME(isSystemContact(phoneNumber:transaction:));
- (BOOL)isSystemContactWithAddressWithSneakyTransaction:(SignalServiceAddress *)address
NS_SWIFT_NAME(isSystemContactWithSneakyTransaction(address:));
- (BOOL)isSystemContactWithAddress:(SignalServiceAddress *)address
                       transaction:(SDSAnyReadTransaction *)transaction NS_SWIFT_NAME(isSystemContact(address:transaction:));
- (BOOL)isSystemContactWithSignalAccount:(SignalServiceAddress *)address
    NS_SWIFT_NAME(isSystemContactWithSignalAccount(_:));
- (BOOL)isSystemContactWithSignalAccount:(SignalServiceAddress *)address
                             transaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(isSystemContactWithSignalAccount(_:transaction:));
- (BOOL)hasNameInSystemContactsForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction;

- (NSArray<SignalServiceAddress *> *)sortSignalServiceAddressesObjC:(NSArray<SignalServiceAddress *> *)addresses
                                                        transaction:(SDSAnyReadTransaction *)transaction;

- (NSString *)comparableNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;
- (NSString *)comparableNameForSignalAccount:(SignalAccount *)signalAccount
                                 transaction:(SDSAnyReadTransaction *)transaction;

@property (nonatomic, readonly) NSString *unknownUserLabel;

- (nullable ModelReadCacheSizeLease *)leaseCacheSize:(NSInteger)size;

#pragma mark - CNContacts

- (nullable CNContact *)cnContactWithId:(nullable NSString *)contactId;
- (nullable NSData *)avatarDataForCNContactId:(nullable NSString *)contactId;
- (nullable UIImage *)avatarImageForCNContactId:(nullable NSString *)contactId;

@end

NS_ASSUME_NONNULL_END
