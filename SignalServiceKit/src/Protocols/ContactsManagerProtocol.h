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
/// - System contact name
/// - Profile name
/// - Username
/// - Phone number
/// - "Unknown"
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

- (BOOL)isSystemContactWithPhoneNumber:(NSString *)phoneNumber
                           transaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(isSystemContact(phoneNumber:transaction:));

- (NSArray<SignalServiceAddress *> *)sortSignalServiceAddressesObjC:(NSArray<SignalServiceAddress *> *)addresses
                                                        transaction:(SDSAnyReadTransaction *)transaction;

- (NSString *)comparableNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSString *)systemContactNameForAddress:(SignalServiceAddress *)address
                                       transaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(systemContactName(for:tx:));

- (nullable ModelReadCacheSizeLease *)leaseCacheSize:(NSInteger)size;

#pragma mark - CNContacts

- (nullable CNContact *)cnContactWithId:(nullable NSString *)contactId;
- (nullable NSData *)avatarDataForCNContactId:(nullable NSString *)contactId;
- (nullable UIImage *)avatarImageForCNContactId:(nullable NSString *)contactId;

@end

NS_ASSUME_NONNULL_END
