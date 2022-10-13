//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class Contact;
@class ContactsViewHelper;
@class SDSAnyReadTransaction;
@class SignalAccount;
@class TSThread;

@protocol ContactsViewHelperObserver <NSObject>

- (void)contactsViewHelperDidUpdateContacts;

@end

#pragma mark -

@class CNContact;
@class CNContactViewController;
@class SignalServiceAddress;

@interface ContactsViewHelper : NSObject

// Useful to differentiate between having no signal accounts vs. haven't checked yet
@property (nonatomic, readonly) BOOL hasUpdatedContactsAtLeastOnce;

// Suitable when the user tries to perform an action which is not possible due to the user having
// previously denied contact access.
- (void)presentMissingContactAccessAlertControllerFromViewController:(UIViewController *)viewController;

- (void)addObserver:(id<ContactsViewHelperObserver>)observer NS_SWIFT_NAME(addObserver(_:));


@property (nonatomic, readonly) NSArray<SignalAccount *> *allSignalAccounts;

- (nullable SignalAccount *)fetchSignalAccountForAddress:(SignalServiceAddress *)address;
- (SignalAccount *)fetchOrBuildSignalAccountForAddress:(SignalServiceAddress *)address;

- (SignalServiceAddress *)localAddress;

- (NSArray<SignalAccount *> *)signalAccountsMatchingSearchString:(NSString *)searchText
                                                     transaction:(SDSAnyReadTransaction *)transaction;

- (void)warmNonSignalContactsCacheAsync;
- (NSArray<Contact *> *)nonSignalContactsMatchingSearchString:(NSString *)searchText;

- (nullable CNContactViewController *)contactViewControllerForAddress:(SignalServiceAddress *)address
                                                      editImmediately:(BOOL)shouldEditImmediately;

// This method can be used to edit existing contacts.
- (nullable CNContactViewController *)contactViewControllerForAddress:(SignalServiceAddress *)address
                                                      editImmediately:(BOOL)shouldEditImmediately
                                               addToExistingCnContact:(CNContact *_Nullable)existingContact
                                                updatedNameComponents:
                                                    (nullable NSPersonNameComponents *)updatedNameComponents;

+ (void)presentMissingContactAccessAlertControllerFromViewController:(UIViewController *)viewController;

@end

NS_ASSUME_NONNULL_END
