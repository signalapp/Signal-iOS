//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class Contact;
@class ContactsViewHelper;
@class SignalAccount;
@class TSThread;

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

@class CNContact;
@class OWSBlockingManager;
@class OWSContactsManager;
@class OWSProfileManager;
@class SignalServiceAddress;

@interface ContactsViewHelper : NSObject

@property (nonatomic, readonly, weak) id<ContactsViewHelperDelegate> delegate;

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) OWSProfileManager *profileManager;

@property (nonatomic, readonly) NSArray<SignalAccount *> *signalAccounts;

// Useful to differentiate between having no signal accounts vs. haven't checked yet
@property (nonatomic, readonly) BOOL hasUpdatedContactsAtLeastOnce;

// Suitable when the user tries to perform an action which is not possible due to the user having
// previously denied contact access.
- (void)presentMissingContactAccessAlertControllerFromViewController:(UIViewController *)viewController;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDelegate:(id<ContactsViewHelperDelegate>)delegate;

- (nullable SignalAccount *)fetchSignalAccountForAddress:(SignalServiceAddress *)address;
- (SignalAccount *)fetchOrBuildSignalAccountForAddress:(SignalServiceAddress *)address;

// This method is faster than OWSBlockingManager but
// is only safe to be called on the main thread.
- (BOOL)isSignalServiceAddressBlocked:(SignalServiceAddress *)address;

// This method is faster than OWSBlockingManager but
// is only safe to be called on the main thread.
- (BOOL)isThreadBlocked:(TSThread *)thread;

// NOTE: This method uses a transaction.
- (SignalServiceAddress *)localAddress;

- (NSArray<SignalAccount *> *)signalAccountsMatchingSearchString:(NSString *)searchText;

- (void)warmNonSignalContactsCacheAsync;
- (NSArray<Contact *> *)nonSignalContactsMatchingSearchString:(NSString *)searchText;

- (void)presentContactViewControllerForAddress:(SignalServiceAddress *)address
                            fromViewController:(UIViewController<ContactEditingDelegate> *)fromViewController
                               editImmediately:(BOOL)shouldEditImmediately;

// This method can be used to edit existing contacts.
- (void)presentContactViewControllerForAddress:(SignalServiceAddress *)address
                            fromViewController:(UIViewController<ContactEditingDelegate> *)fromViewController
                               editImmediately:(BOOL)shouldEditImmediately
                        addToExistingCnContact:(CNContact *_Nullable)cnContact;

+ (void)presentMissingContactAccessAlertControllerFromViewController:(UIViewController *)viewController;

@end

NS_ASSUME_NONNULL_END
