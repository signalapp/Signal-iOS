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

// This method is faster than OWSBlockingManager but
// is only safe to be called on the main thread.
- (BOOL)isRecipientIdBlocked:(NSString *)recipientId;

// NOTE: This method uses a transaction.
- (NSString *)localNumber;

- (NSArray<SignalAccount *> *)signalAccountsMatchingSearchString:(NSString *)searchText;

@end

NS_ASSUME_NONNULL_END
