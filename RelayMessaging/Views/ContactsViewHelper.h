//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

//@class Contact;
@class ContactsViewHelper;
@class SignalAccount;
@class RelayRecipient;
@class FLTag;

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

//@class CNContact;
@class OWSBlockingManager;
@class FLContactsManager;

@interface ContactsViewHelper : NSObject

@property (nonatomic, readonly, weak) id<ContactsViewHelperDelegate> delegate;

@property (nonatomic, readonly) FLContactsManager *contactsManager;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;

@property (nonatomic, readonly) NSDictionary<NSString *, SignalAccount *> *signalAccountMap __deprecated;
@property (nonatomic, readonly) NSArray<SignalAccount *> *signalAccounts __deprecated;

@property (nonatomic, readonly) NSArray<RelayRecipient *> *relayRecipients;
@property (nonatomic, readonly) NSArray<FLTag *> *relayTags;
@property (nonatomic, readonly) NSDictionary<NSString *, FLTag *> *relayTagMap;

// Useful to differentiate between having no signal accounts vs. haven't checked yet
@property (nonatomic, readonly) BOOL hasUpdatedContactsAtLeastOnce;

@property (nonatomic, readonly) NSArray<NSString *> *blockedPhoneNumbers;

// Suitable when the user tries to perform an action which is not possible due to the user having
// previously denied contact access.
- (void)presentMissingContactAccessAlertControllerFromViewController:(UIViewController *)viewController;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDelegate:(id<ContactsViewHelperDelegate>)delegate;

- (nullable SignalAccount *)fetchSignalAccountForRecipientId:(NSString *)recipientId;
- (SignalAccount *)fetchOrBuildSignalAccountForRecipientId:(NSString *)recipientId;

// This method is faster than OWSBlockingManager but
// is only safe to be called on the main thread.
- (BOOL)isRecipientIdBlocked:(NSString *)recipientId;

// NOTE: This method uses a transaction.
- (NSString *)localUID;

- (NSArray<FLTag *> *)relayTagsMatchingSearchString:(NSString *)searchText;
- (NSArray<SignalAccount *> *)signalAccountsMatchingSearchString:(NSString *)searchText __deprecated;

//- (NSArray<Contact *> *)nonSignalContactsMatchingSearchString:(NSString *)searchText;

- (void)presentContactViewControllerForRecipientId:(NSString *)recipientId
                                fromViewController:(UIViewController<ContactEditingDelegate> *)fromViewController
                                   editImmediately:(BOOL)shouldEditImmediately;

// This method can be used to edit existing contacts.
//- (void)presentContactViewControllerForRecipientId:(NSString *)recipientId
//                                fromViewController:(UIViewController<ContactEditingDelegate> *)fromViewController
//                                   editImmediately:(BOOL)shouldEditImmediately
//                            addToExistingCnContact:(CNContact *_Nullable)cnContact;

+ (void)presentMissingContactAccessAlertControllerFromViewController:(UIViewController *)viewController;

@end

NS_ASSUME_NONNULL_END
