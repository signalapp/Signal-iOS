//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ContactsViewHelper;
@class Contact;
@class SignalAccount;
@protocol CNContactViewControllerDelegate;

@protocol ContactsViewHelperDelegate <NSObject>

- (void)contactsViewHelperDidUpdateContacts;

@optional

- (BOOL)shouldHideLocalNumber;

@end

@protocol ContactEditingDelegate <CNContactViewControllerDelegate>

- (void)didFinishEditingContact;

@end

#pragma mark -

@class OWSContactsManager;
@class OWSBlockingManager;
@class CNContact;

@interface ContactsViewHelper : NSObject

@property (nonatomic, readonly, weak) id<ContactsViewHelperDelegate> delegate;

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;

@property (nonatomic, readonly) NSDictionary<NSString *, SignalAccount *> *signalAccountMap;
@property (nonatomic, readonly) NSArray<SignalAccount *> *signalAccounts;

// Useful to differentiate between having no signal accounts vs. haven't checked yet
@property (nonatomic, readonly) BOOL hasUpdatedContactsAtLeastOnce;

@property (nonatomic, readonly) NSArray<NSString *> *blockedPhoneNumbers;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDelegate:(id<ContactsViewHelperDelegate>)delegate;

- (nullable SignalAccount *)signalAccountForRecipientId:(NSString *)recipientId;

// This method is faster than OWSBlockingManager but
// is only safe to be called on the main thread.
- (BOOL)isRecipientIdBlocked:(NSString *)recipientId;

// NOTE: This method uses a transaction.
- (NSString *)localNumber;

- (NSArray<SignalAccount *> *)signalAccountsMatchingSearchString:(NSString *)searchText;

- (NSArray<Contact *> *)nonSignalContactsMatchingSearchString:(NSString *)searchText;

/**
 * NOTE: This method calls `[UIUtil applyDefaultSystemAppearence]`.
 * When using this method, you must call `[UIUtil applySignalAppearence]` once contact editing is   finished;
 */
- (void)presentContactViewControllerForRecipientId:(NSString *)recipientId
                                fromViewController:(UIViewController<ContactEditingDelegate> *)fromViewController
                                   editImmediately:(BOOL)shouldEditImmediately;

// This method can be used to edit existing contacts.
- (void)presentContactViewControllerForRecipientId:(NSString *)recipientId
                                fromViewController:(UIViewController<ContactEditingDelegate> *)fromViewController
                                   editImmediately:(BOOL)shouldEditImmediately
                            addToExistingCnContact:(CNContact *_Nullable)cnContact;

@end

NS_ASSUME_NONNULL_END
