//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/ContactsManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const OWSContactsManagerSignalAccountsDidChangeNotification;
extern NSNotificationName const OWSContactsManagerContactsDidChangeNotification;

@class AnyPromise;
@class SDSAnyReadTransaction;
@class SDSKeyValueStore;
@class SignalAccount;
@class SignalServiceAddress;
@class UIFont;

@protocol ContactsManagerCache;

/**
 * Get latest Signal contacts, and be notified when they change.
 */
@interface OWSContactsManager : NSObject <ContactsManagerProtocol>

@property (nonatomic, readonly) BOOL shouldSortByGivenName;

@property (nonatomic, readonly) id<ContactsManagerCache> contactsManagerCache;

#pragma mark - Accessors

@property (nonatomic, readonly) SDSKeyValueStore *keyValueStore;

// This will return an instance of SignalAccount for _known_ signal accounts.
- (nullable SignalAccount *)fetchSignalAccountForAddress:(SignalServiceAddress *)address;

- (nullable SignalAccount *)fetchSignalAccountForAddress:(SignalServiceAddress *)address
                                             transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSString *)nameFromSystemContactsForAddress:(SignalServiceAddress *)address
                                            transaction:(SDSAnyReadTransaction *)transaction;

// This will always return an instance of SignalAccount.
- (SignalAccount *)fetchOrBuildSignalAccountForAddress:(SignalServiceAddress *)address;

#pragma mark - System Contact Fetching

// Must call `requestSystemContactsOnce` before accessing this method
@property (nonatomic, readonly) BOOL isSystemContactsAuthorized;
@property (nonatomic, readonly) BOOL isSystemContactsDenied;
@property (nonatomic, readonly) BOOL systemContactsHaveBeenRequestedAtLeastOnce;

@property (nonatomic, readonly) BOOL supportsContactEditing;

@property (atomic, readonly) BOOL isSetup;

// Not set until a contact fetch has completed.
// Set even if no contacts are found.
@property (nonatomic, readonly) BOOL hasLoadedSystemContacts;

// Request systems contacts and start syncing changes. The user will see an alert
// if they haven't previously.
- (void)requestSystemContactsOnce;
- (void)requestSystemContactsOnceWithCompletion:(void (^_Nullable)(NSError *_Nullable error))completion;

// Ensure's the app has the latest contacts, but won't prompt the user for contact
// access if they haven't granted it.
- (void)fetchSystemContactsOnceIfAlreadyAuthorized;

// This variant will fetch system contacts if contact access has already been granted,
// but not prompt for contact access. Also, it will always notify delegates, even if
// contacts haven't changed, and will clear out any stale cached SignalAccounts
- (AnyPromise *)userRequestedSystemContactsRefresh;

#pragma mark - Util

/**
 * Used for sorting, respects system contacts name sort order preference.
 */
- (NSString *)comparableNameForSignalAccount:(SignalAccount *)signalAccount
                                 transaction:(SDSAnyReadTransaction *)transaction;
- (NSString *)comparableNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSData *)profileImageDataForAddressWithSneakyTransaction:(nullable SignalServiceAddress *)address;

- (nullable NSString *)phoneNumberForAddress:(SignalServiceAddress *)address
                                 transaction:(SDSAnyReadTransaction *)transaction;

- (BOOL)isKnownRegisteredUserWithSneakyTransaction:(SignalServiceAddress *)address
    NS_SWIFT_NAME(isKnownRegisteredUserWithSneakyTransaction(address:));
- (BOOL)isKnownRegisteredUser:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
