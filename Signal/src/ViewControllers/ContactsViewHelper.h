//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ContactsViewHelper;
@class Contact;
@class ContactAccount;

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

// A list of all of the current user's contacts which have
// at least one signal account.
- (nullable NSArray<Contact *> *)allRecipientContacts;

// A list of all of the current user's ContactAccounts.
// See the comments on the ContactAccount class.
//
// The list is ordered by contact sorting (by OWSContactsManager)
// and within contacts by phone number, alphabetically.
- (nullable NSArray<ContactAccount *> *)allRecipientContactAccounts;

- (nullable ContactAccount *)contactAccountForRecipientId:(NSString *)recipientId;

- (nullable NSArray<NSString *> *)blockedPhoneNumbers;

// This method is faster than OWSBlockingManager but
// is only safe to be called on the main thread.
//
// Returns true if _any_ number associated with this contact
// is blocked.
- (BOOL)isContactBlocked:(Contact *)contact;

// This method is faster than OWSBlockingManager but
// is only safe to be called on the main thread.
- (BOOL)isRecipientIdBlocked:(NSString *)recipientId;

- (NSString *)localNumber;

- (NSArray<ContactAccount *> *)contactAccountsMatchingSearchString:(NSString *)searchText;

@end

NS_ASSUME_NONNULL_END
