//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ContactsViewHelper;
@class Contact;
@class SignalAccount;

@protocol ContactsViewHelperDelegate <NSObject>

- (void)contactsViewHelperDidUpdateContacts;

- (BOOL)shouldHideLocalNumber;

@end

#pragma mark -

@class OWSContactsManager;
@class OWSBlockingManager;

@interface ContactsViewHelper : NSObject

@property (nonatomic, weak) id<ContactsViewHelperDelegate> delegate;

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;

@property (nonatomic, readonly) NSDictionary<NSString *, SignalAccount *> *signalAccountMap;
@property (nonatomic, readonly) NSArray<SignalAccount *> *signalAccounts;

@property (nonatomic, readonly) NSArray<NSString *> *blockedPhoneNumbers;

- (nullable SignalAccount *)signalAccountForRecipientId:(NSString *)recipientId;

- (nullable NSArray<NSString *> *)blockedPhoneNumbers;

// This method is faster than OWSBlockingManager but
// is only safe to be called on the main thread.
//
// Returns true if _any_ number associated with this contact
// is blocked.
//
// TODO: Is this obsolete?
- (BOOL)isContactBlocked:(Contact *)contact;

// This method is faster than OWSBlockingManager but
// is only safe to be called on the main thread.
- (BOOL)isRecipientIdBlocked:(NSString *)recipientId;

- (NSString *)localNumber;

- (NSArray<SignalAccount *> *)signalAccountsMatchingSearchString:(NSString *)searchText;

@end

NS_ASSUME_NONNULL_END
