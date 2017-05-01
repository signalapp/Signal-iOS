//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Contacts/Contacts.h>
#import <Foundation/Foundation.h>
#import <SignalServiceKit/ContactsManagerProtocol.h>
#import <SignalServiceKit/PhoneNumber.h>
#import "CollapsingFutures.h"
#import "Contact.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSContactsManagerSignalAccountsDidChangeNotification;

@class UIFont;
@class SignalAccount;

/**
 * Get latest Signal contacts, and be notified when they change.
 */
@interface OWSContactsManager : NSObject <ContactsManagerProtocol>

@property (nonnull, readonly) NSCache<NSString *, UIImage *> *avatarCache;

// signalAccountMap and signalAccounts hold the same data.
// signalAccountMap is for lookup. signalAccounts contains the accounts
// ordered by display order.
@property (atomic, readonly) NSDictionary<NSString *, SignalAccount *> *signalAccountMap;
@property (atomic, readonly) NSArray<SignalAccount *> *signalAccounts;

- (nullable SignalAccount *)signalAccountForRecipientId:(nullable NSString *)recipientId;

- (Contact *)getOrBuildContactForPhoneIdentifier:(NSString *)identifier;

- (void)verifyABPermission;

// TODO: Remove this method.
- (NSArray<Contact *> *)signalContacts;

- (void)doAfterEnvironmentInitSetup;

- (NSString *)displayNameForPhoneIdentifier:(nullable NSString *)identifier;
- (NSString *)displayNameForContact:(Contact *)contact;
- (NSString *_Nonnull)displayNameForSignalAccount:(SignalAccount *)signalAccount;
- (nullable UIImage *)imageForPhoneIdentifier:(nullable NSString *)identifier;
- (NSAttributedString *_Nonnull)formattedDisplayNameForSignalAccount:(SignalAccount *)signalAccount
                                                                font:(UIFont *_Nonnull)font;
- (NSAttributedString *)formattedFullNameForContact:(Contact *)contact font:(UIFont *)font;
- (NSAttributedString *)formattedFullNameForRecipientId:(NSString *)recipientId font:(UIFont *)font;

- (BOOL)hasAddressBook;

+ (NSComparator _Nonnull)contactComparator;

@end

NS_ASSUME_NONNULL_END
