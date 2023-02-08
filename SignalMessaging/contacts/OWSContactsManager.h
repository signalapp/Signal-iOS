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
@class OWSContactsManagerSwiftValues;
@class SDSAnyReadTransaction;
@class SDSKeyValueStore;
@class SignalAccount;
@class SignalServiceAddress;
@class UIFont;

@protocol ContactsManagerCache;

typedef NS_CLOSED_ENUM(NSUInteger, RawContactAuthorizationStatus) {
    RawContactAuthorizationStatusNotDetermined,
    RawContactAuthorizationStatusDenied,
    RawContactAuthorizationStatusRestricted,
    RawContactAuthorizationStatusAuthorized,
};

typedef NS_CLOSED_ENUM(NSUInteger, ContactAuthorizationForEditing) {
    ContactAuthorizationForEditingNotAllowed,
    ContactAuthorizationForEditingDenied,
    ContactAuthorizationForEditingRestricted,
    ContactAuthorizationForEditingAuthorized,
};

typedef NS_CLOSED_ENUM(NSUInteger, ContactAuthorizationForSharing) {
    ContactAuthorizationForSharingNotDetermined,
    ContactAuthorizationForSharingDenied,
    ContactAuthorizationForSharingAuthorized,
};

/**
 * Get latest Signal contacts, and be notified when they change.
 */
@interface OWSContactsManager : NSObject <ContactsManagerProtocol>

- (id)new NS_UNAVAILABLE;

- (id)init NS_UNAVAILABLE;

- (id)initWithSwiftValues:(OWSContactsManagerSwiftValues *)swiftValues;

@property (nonatomic, readonly) BOOL shouldSortByGivenName;

@property (nonatomic, readonly) OWSContactsManagerSwiftValues *swiftValues;

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

@property (nonatomic, readonly) BOOL isEditingAllowed;

// Must call `requestSystemContactsOnce` before accessing this method
@property (nonatomic, readonly) ContactAuthorizationForEditing editingAuthorization;

@property (nonatomic, readonly) ContactAuthorizationForSharing sharingAuthorization;

@property (atomic, readonly) BOOL isSetup;

/// Whether or not we've fetched system contacts on this launch.
///
/// This property is set to true even if the user doesn't have any system
/// contacts.
///
/// This property is only valid if the user has granted contacts access.
/// Otherwise, it's value is undefined.
@property (nonatomic) BOOL hasLoadedSystemContacts;

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

- (NSString *)comparableNameForContact:(Contact *)contact;

/**
 * Used for sorting, respects system contacts name sort order preference.
 */
- (NSString *)comparableNameForSignalAccount:(SignalAccount *)signalAccount
                                 transaction:(SDSAnyReadTransaction *)transaction;
- (NSString *)comparableNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSData *)profileImageDataForAddressWithSneakyTransaction:(nullable SignalServiceAddress *)address;

- (nullable NSString *)phoneNumberForAddress:(SignalServiceAddress *)address
                                 transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
