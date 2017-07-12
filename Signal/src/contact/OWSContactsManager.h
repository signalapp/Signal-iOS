//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "Contact.h"
#import <SignalServiceKit/ContactsManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSContactsManagerSignalAccountsDidChangeNotification;

@class UIFont;
@class SignalAccount;

/**
 * Get latest Signal contacts, and be notified when they change.
 */
@interface OWSContactsManager : NSObject <ContactsManagerProtocol>

@property (nonnull, readonly) NSCache<NSString *, UIImage *> *avatarCache;

@property (atomic, readonly) NSArray<Contact *> *allContacts;

@property (atomic, readonly) NSDictionary<NSString *, Contact *> *allContactsMap;

// signalAccountMap and signalAccounts hold the same data.
// signalAccountMap is for lookup. signalAccounts contains the accounts
// ordered by display order.
@property (atomic, readonly) NSDictionary<NSString *, SignalAccount *> *signalAccountMap;
@property (atomic, readonly) NSArray<SignalAccount *> *signalAccounts;

- (nullable SignalAccount *)signalAccountForRecipientId:(NSString *)recipientId;

- (Contact *)getOrBuildContactForPhoneIdentifier:(NSString *)identifier;

#pragma mark - System Contact Fetching

// Must call `requestSystemContactsOnce` before accessing this method
@property (nonatomic, readonly) BOOL isSystemContactsAuthorized;

@property (nonatomic, readonly) BOOL supportsContactEditing;

// Request systems contacts and start syncing changes. The user will see an alert
// if they haven't previously.
- (void)requestSystemContactsOnce;
- (void)requestSystemContactsOnceWithCompletion:(void (^_Nullable)(NSError *_Nullable error))completion;

// Ensure's the app has the latest contacts, but won't prompt the user for contact
// access if they haven't granted it.
- (void)fetchSystemContactsIfAlreadyAuthorized;

#pragma mark - Util

- (NSString *)displayNameForPhoneIdentifier:(nullable NSString *)identifier;
- (NSString *)displayNameForSignalAccount:(SignalAccount *)signalAccount;
- (nullable UIImage *)imageForPhoneIdentifier:(nullable NSString *)identifier;
- (NSAttributedString *)formattedDisplayNameForSignalAccount:(SignalAccount *)signalAccount font:(UIFont *_Nonnull)font;
- (NSAttributedString *)formattedFullNameForRecipientId:(NSString *)recipientId font:(UIFont *)font;

@end

NS_ASSUME_NONNULL_END
