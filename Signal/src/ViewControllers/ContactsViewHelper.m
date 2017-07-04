//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ContactsViewHelper.h"
#import "ContactTableViewCell.h"
#import "Environment.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSAccountManager.h>

@import ContactsUI;

NS_ASSUME_NONNULL_BEGIN

@interface ContactsViewHelper ()

// This property is a cached value that is lazy-populated.
@property (nonatomic, nullable) NSArray<Contact *> *nonSignalContacts;

@property (nonatomic) NSDictionary<NSString *, SignalAccount *> *signalAccountMap;
@property (nonatomic) NSArray<SignalAccount *> *signalAccounts;

@property (nonatomic) NSArray<NSString *> *blockedPhoneNumbers;

@property (nonatomic) BOOL shouldNotifyDelegateOfUpdatedContacts;
@property (nonatomic) BOOL hasUpdatedContactsAtLeastOnce;

@end

#pragma mark -

@implementation ContactsViewHelper

- (instancetype)initWithDelegate:(id<ContactsViewHelperDelegate>)delegate
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssert(delegate);
    _delegate = delegate;

    _blockingManager = [OWSBlockingManager sharedManager];
    _blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];

    _contactsManager = [Environment getCurrent].contactsManager;

    // We don't want to notify the delegate in the `updateContacts`.
    self.shouldNotifyDelegateOfUpdatedContacts = YES;
    [self updateContacts];
    self.shouldNotifyDelegateOfUpdatedContacts = NO;

    [self observeNotifications];

    return self;
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalAccountsDidChange:)
                                                 name:OWSContactsManagerSignalAccountsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockedPhoneNumbersDidChange:)
                                                 name:kNSNotificationName_BlockedPhoneNumbersDidChange
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)signalAccountsDidChange:(NSNotification *)notification
{
    OWSAssert([NSThread isMainThread]);

    [self updateContacts];
}

- (void)blockedPhoneNumbersDidChange:(id)notification
{
    OWSAssert([NSThread isMainThread]);

    self.blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];

    [self updateContacts];
}

#pragma mark - Contacts

- (nullable SignalAccount *)signalAccountForRecipientId:(NSString *)recipientId
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(recipientId.length > 0);

    return self.signalAccountMap[recipientId];
}

- (BOOL)isSignalAccountHidden:(SignalAccount *)signalAccount
{
    OWSAssert([NSThread isMainThread]);

    if ([self.delegate respondsToSelector:@selector(shouldHideLocalNumber)] && [self.delegate shouldHideLocalNumber] &&
        [self isCurrentUser:signalAccount]) {

        return YES;
    }

    return NO;
}

- (BOOL)isCurrentUser:(SignalAccount *)signalAccount
{
    OWSAssert([NSThread isMainThread]);

    NSString *localNumber = [TSAccountManager localNumber];
    if ([signalAccount.recipientId isEqualToString:localNumber]) {
        return YES;
    }

    for (PhoneNumber *phoneNumber in signalAccount.contact.parsedPhoneNumbers) {
        if ([[phoneNumber toE164] isEqualToString:localNumber]) {
            return YES;
        }
    }

    return NO;
}

- (NSString *)localNumber
{
    return [TSAccountManager localNumber];
}

- (BOOL)isRecipientIdBlocked:(NSString *)recipientId
{
    AssertIsOnMainThread();

    return [_blockedPhoneNumbers containsObject:recipientId];
}

- (void)updateContacts
{
    AssertIsOnMainThread();

    NSMutableDictionary<NSString *, SignalAccount *> *signalAccountMap = [NSMutableDictionary new];
    NSMutableArray<SignalAccount *> *signalAccounts = [NSMutableArray new];
    for (SignalAccount *signalAccount in self.contactsManager.signalAccounts) {
        if (![self isSignalAccountHidden:signalAccount]) {
            signalAccountMap[signalAccount.recipientId] = signalAccount;
            [signalAccounts addObject:signalAccount];
        }
    }
    self.signalAccountMap = [signalAccountMap copy];
    self.signalAccounts = [signalAccounts copy];
    self.nonSignalContacts = nil;

    // Don't fire delegate "change" events during initialization.
    if (!self.shouldNotifyDelegateOfUpdatedContacts) {
        [self.delegate contactsViewHelperDidUpdateContacts];
        self.hasUpdatedContactsAtLeastOnce = YES;
    }
}

- (BOOL)doesSignalAccount:(SignalAccount *)signalAccount matchSearchTerm:(NSString *)searchTerm
{
    OWSAssert(signalAccount);
    OWSAssert(searchTerm.length > 0);

    if ([signalAccount.contact.fullName.lowercaseString containsString:searchTerm.lowercaseString]) {
        return YES;
    }

    NSString *asPhoneNumber = [PhoneNumber removeFormattingCharacters:searchTerm];
    if (asPhoneNumber.length > 0 && [signalAccount.recipientId containsString:asPhoneNumber]) {
        return YES;
    }

    return NO;
}

- (BOOL)doesSignalAccount:(SignalAccount *)signalAccount matchSearchTerms:(NSArray<NSString *> *)searchTerms
{
    OWSAssert(signalAccount);
    OWSAssert(searchTerms.count > 0);

    for (NSString *searchTerm in searchTerms) {
        if (![self doesSignalAccount:signalAccount matchSearchTerm:searchTerm]) {
            return NO;
        }
    }

    return YES;
}

- (NSArray<NSString *> *)searchTermsForSearchString:(NSString *)searchText
{
    return [[[searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *_Nullable searchTerm,
                                        NSDictionary<NSString *, id> *_Nullable bindings) {
            return searchTerm.length > 0;
        }]];
}

- (NSArray<SignalAccount *> *)signalAccountsMatchingSearchString:(NSString *)searchText
{
    NSArray<NSString *> *searchTerms = [self searchTermsForSearchString:searchText];

    if (searchTerms.count < 1) {
        return self.signalAccounts;
    }

    return [self.signalAccounts
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SignalAccount *signalAccount,
                                        NSDictionary<NSString *, id> *_Nullable bindings) {
            return [self doesSignalAccount:signalAccount matchSearchTerms:searchTerms];
        }]];
}

- (BOOL)doesContact:(Contact *)contact matchSearchTerm:(NSString *)searchTerm
{
    OWSAssert(contact);
    OWSAssert(searchTerm.length > 0);

    if ([contact.fullName.lowercaseString containsString:searchTerm.lowercaseString]) {
        return YES;
    }

    NSString *asPhoneNumber = [PhoneNumber removeFormattingCharacters:searchTerm];
    if (asPhoneNumber.length > 0) {
        for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
            if ([phoneNumber.toE164 containsString:asPhoneNumber]) {
                return YES;
            }
        }
    }

    return NO;
}

- (BOOL)doesContact:(Contact *)contact matchSearchTerms:(NSArray<NSString *> *)searchTerms
{
    OWSAssert(contact);
    OWSAssert(searchTerms.count > 0);

    for (NSString *searchTerm in searchTerms) {
        if (![self doesContact:contact matchSearchTerm:searchTerm]) {
            return NO;
        }
    }

    return YES;
}

- (NSArray<Contact *> *)nonSignalContactsMatchingSearchString:(NSString *)searchText
{
    NSArray<NSString *> *searchTerms = [self searchTermsForSearchString:searchText];

    if (searchTerms.count < 1) {
        return [NSArray new];
    }

    return [self.nonSignalContacts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Contact *contact,
                                                                   NSDictionary<NSString *, id> *_Nullable bindings) {
        return [self doesContact:contact matchSearchTerms:searchTerms];
    }]];
}

- (nullable NSArray<Contact *> *)nonSignalContacts
{
    if (!_nonSignalContacts) {
        NSMutableSet<Contact *> *nonSignalContacts = [NSMutableSet new];
        [[TSStorageManager sharedManager].dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            for (Contact *contact in self.contactsManager.allContactsMap.allValues) {
                NSArray<SignalRecipient *> *signalRecipients = [contact signalRecipientsWithTransaction:transaction];
                if (signalRecipients.count < 1) {
                    [nonSignalContacts addObject:contact];
                }
            }
        }];
        _nonSignalContacts = [nonSignalContacts.allObjects
            sortedArrayUsingComparator:^NSComparisonResult(Contact *_Nonnull left, Contact *_Nonnull right) {
                return [left.fullName compare:right.fullName];
            }];
    }

    return _nonSignalContacts;
}

#pragma mark - Editing

- (void)presentContactViewControllerForRecipientId:(NSString *)recipientId
                                fromViewController:(UIViewController<ContactEditingDelegate> *)fromViewController
                                   editImmediately:(BOOL)shouldEditImmediately
{
    [self presentContactViewControllerForRecipientId:recipientId
                                  fromViewController:fromViewController
                                     editImmediately:shouldEditImmediately
                              addToExistingCnContact:nil];
}

- (void)presentContactViewControllerForRecipientId:(NSString *)recipientId
                                fromViewController:(UIViewController<ContactEditingDelegate> *)fromViewController
                                   editImmediately:(BOOL)shouldEditImmediately
                            addToExistingCnContact:(CNContact *_Nullable)addToExistingCnContact
{
    SignalAccount *signalAccount = [self signalAccountForRecipientId:recipientId];

    if (!self.contactsManager.supportsContactEditing) {
        DDLogError(@"%@ Contact editing not supported.", self.tag);
        // Should not expose UI that lets the user get here.
        OWSAssert(NO);
        return;
    }

    if (!self.contactsManager.isSystemContactsAuthorized) {
        UIAlertController *alertController = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"EDIT_CONTACT_WITHOUT_CONTACTS_PERMISSION_ALERT_TITLE", comment
                                                       : @"Alert title for when the user has just tried to edit a "
                                                         @"contacts after declining to give Signal contacts "
                                                         @"permissions")
                             message:NSLocalizedString(@"EDIT_CONTACT_WITHOUT_CONTACTS_PERMISSION_ALERT_BODY", comment
                                                       : @"Alert body for when the user has just tried to edit a "
                                                         @"contacts after declining to give Signal contacts "
                                                         @"permissions")
                      preferredStyle:UIAlertControllerStyleAlert];

        [alertController
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"AB_PERMISSION_MISSING_ACTION_NOT_NOW",
                                                         @"Button text to dismiss missing contacts permission alert")
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];

        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OPEN_SETTINGS_BUTTON",
                                                                      @"Button text which opens the settings app")
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *_Nonnull action) {
                                                              [[UIApplication sharedApplication] openSystemSettings];
                                                          }]];

        [fromViewController presentViewController:alertController animated:YES completion:nil];
        return;
    }

    CNContactViewController *_Nullable contactViewController;
    CNContact *_Nullable cnContact = nil;
    if (addToExistingCnContact) {
        CNMutableContact *updatedContact = [addToExistingCnContact mutableCopy];
        NSMutableArray<CNLabeledValue *> *phoneNumbers
            = (updatedContact.phoneNumbers ? [updatedContact.phoneNumbers mutableCopy] : [NSMutableArray new]);
        // Only add recipientId as a phone number for the existing contact
        // if its not already present.
        BOOL hasPhoneNumber = NO;
        for (CNLabeledValue *existingPhoneNumber in phoneNumbers) {
            CNPhoneNumber *phoneNumber = existingPhoneNumber.value;
            if ([phoneNumber.stringValue isEqualToString:recipientId]) {
                hasPhoneNumber = YES;
                break;
            }
        }
        if (!hasPhoneNumber) {
            CNPhoneNumber *phoneNumber = [CNPhoneNumber phoneNumberWithStringValue:recipientId];
            CNLabeledValue<CNPhoneNumber *> *labeledPhoneNumber =
                [CNLabeledValue labeledValueWithLabel:CNLabelPhoneNumberMain value:phoneNumber];
            [phoneNumbers addObject:labeledPhoneNumber];
            updatedContact.phoneNumbers = phoneNumbers;

            // When adding a phone number to an existing contact, immediately enter
            // "edit" mode.
            shouldEditImmediately = YES;
        }
        cnContact = updatedContact;
    }
    if (signalAccount && !cnContact) {
        cnContact = signalAccount.contact.cnContact;
    }
    if (cnContact) {
        if (shouldEditImmediately) {
            // Not actually a "new" contact, but this brings up the edit form rather than the "Read" form
            // saving our users a tap in some cases when we already know they want to edit.
            contactViewController = [CNContactViewController viewControllerForNewContact:cnContact];

            // Default title is "New Contact". We could give a more descriptive title, but anything
            // seems redundant - the context is sufficiently clear.
            contactViewController.title = @"";
        } else {
            contactViewController = [CNContactViewController viewControllerForContact:cnContact];
        }
    }

    if (!contactViewController) {
        CNMutableContact *newContact = [CNMutableContact new];
        CNPhoneNumber *phoneNumber = [CNPhoneNumber phoneNumberWithStringValue:recipientId];
        CNLabeledValue<CNPhoneNumber *> *labeledPhoneNumber =
            [CNLabeledValue labeledValueWithLabel:CNLabelPhoneNumberMain value:phoneNumber];
        newContact.phoneNumbers = @[ labeledPhoneNumber ];

        contactViewController = [CNContactViewController viewControllerForNewContact:newContact];
    }

    contactViewController.delegate = fromViewController;
    contactViewController.allowsActions = NO;
    contactViewController.allowsEditing = YES;
    contactViewController.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", nil)
                                         style:UIBarButtonItemStylePlain
                                        target:fromViewController
                                        action:@selector(didFinishEditingContact)];

    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:contactViewController];

    // We want the presentation to imply a "replacement" in this case.
    if (shouldEditImmediately) {
        navigationController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    [fromViewController presentViewController:navigationController animated:YES completion:nil];

    // HACK otherwise CNContactViewController Navbar is shown as black.
    // RADAR rdar://28433898 http://www.openradar.me/28433898
    // CNContactViewController incompatible with opaque navigation bar
    [UIUtil applyDefaultSystemAppearence];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
