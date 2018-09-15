//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ContactsViewHelper.h"
#import "Environment.h"
#import "NSString+OWS.h"
#import "UIUtil.h"
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSAccountManager.h>

@import ContactsUI;

NS_ASSUME_NONNULL_BEGIN

@interface ContactsViewHelper () <OWSBlockListCacheDelegate>

// This property is a cached value that is lazy-populated.
@property (nonatomic, nullable) NSArray<Contact *> *nonSignalContacts;

@property (nonatomic) NSDictionary<NSString *, SignalAccount *> *signalAccountMap;
@property (nonatomic) NSArray<SignalAccount *> *signalAccounts;

@property (nonatomic, readonly) OWSBlockListCache *blockListCache;

@property (nonatomic) BOOL shouldNotifyDelegateOfUpdatedContacts;
@property (nonatomic) BOOL hasUpdatedContactsAtLeastOnce;
@property (nonatomic) OWSProfileManager *profileManager;
@property (nonatomic, readonly) ConversationSearcher *conversationSearcher;

@end

#pragma mark -

@implementation ContactsViewHelper

- (instancetype)initWithDelegate:(id<ContactsViewHelperDelegate>)delegate
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(delegate);
    _delegate = delegate;

    _blockingManager = [OWSBlockingManager sharedManager];
    _blockListCache = [OWSBlockListCache new];
    [_blockListCache startObservingAndSyncStateWithDelegate:self];

    _conversationSearcher = ConversationSearcher.shared;

    _contactsManager = Environment.shared.contactsManager;
    _profileManager = [OWSProfileManager sharedManager];

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
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)signalAccountsDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateContacts];
}

#pragma mark - Contacts

- (nullable SignalAccount *)fetchSignalAccountForRecipientId:(NSString *)recipientId
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(recipientId.length > 0);

    return self.signalAccountMap[recipientId];
}

- (SignalAccount *)fetchOrBuildSignalAccountForRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForRecipientId:recipientId];
    return (signalAccount ?: [[SignalAccount alloc] initWithRecipientId:recipientId]);
}

- (BOOL)isSignalAccountHidden:(SignalAccount *)signalAccount
{
    OWSAssertIsOnMainThread();

    if ([self.delegate respondsToSelector:@selector(shouldHideLocalNumber)] && [self.delegate shouldHideLocalNumber] &&
        [self isCurrentUser:signalAccount]) {

        return YES;
    }

    return NO;
}

- (BOOL)isCurrentUser:(SignalAccount *)signalAccount
{
    OWSAssertIsOnMainThread();

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
    OWSAssertIsOnMainThread();

    return [self.blockListCache isRecipientIdBlocked:recipientId];
}

- (BOOL)isGroupIdBlocked:(NSData *)groupId
{
    OWSAssertIsOnMainThread();

    return [self.blockListCache isGroupIdBlocked:groupId];
}

- (BOOL)isThreadBlocked:(TSThread *)thread
{
    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        return [self isRecipientIdBlocked:contactThread.contactIdentifier];
    } else if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        return [self isGroupIdBlocked:groupThread.groupModel.groupId];
    } else {
        OWSFailDebug(@"%@ failure: unexpected thread: %@", self.logTag, thread.class);
        return NO;
    }
}

- (void)updateContacts
{
    OWSAssertIsOnMainThread();

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

- (NSArray<NSString *> *)searchTermsForSearchString:(NSString *)searchText
{
    return [[[searchText ows_stripped]
        componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *_Nullable searchTerm,
                                        NSDictionary<NSString *, id> *_Nullable bindings) {
            return searchTerm.length > 0;
        }]];
}

- (NSArray<SignalAccount *> *)signalAccountsMatchingSearchString:(NSString *)searchText
{
    return [self.conversationSearcher filterSignalAccounts:self.signalAccounts withSearchText:searchText];
}

- (BOOL)doesContact:(Contact *)contact matchSearchTerm:(NSString *)searchTerm
{
    OWSAssertDebug(contact);
    OWSAssertDebug(searchTerm.length > 0);

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
    OWSAssertDebug(contact);
    OWSAssertDebug(searchTerms.count > 0);

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
        [OWSPrimaryStorage.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
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

- (void)presentMissingContactAccessAlertControllerFromViewController:(UIViewController *)viewController
{
    [ContactsViewHelper presentMissingContactAccessAlertControllerFromViewController:viewController];
}

+ (void)presentMissingContactAccessAlertControllerFromViewController:(UIViewController *)viewController
{
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

    UIAlertAction *_Nullable openSystemSettingsAction = CurrentAppContext().openSystemSettingsAction;
    if (openSystemSettingsAction) {
        [alertController addAction:openSystemSettingsAction];
    }

    [viewController presentViewController:alertController animated:YES completion:nil];
}

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
                            addToExistingCnContact:(CNContact *_Nullable)existingContact
{
    SignalAccount *signalAccount = [self fetchSignalAccountForRecipientId:recipientId];

    if (!self.contactsManager.supportsContactEditing) {
        // Should not expose UI that lets the user get here.
        OWSFailDebug(@"Contact editing not supported.");
        return;
    }

    if (!self.contactsManager.isSystemContactsAuthorized) {
        [self presentMissingContactAccessAlertControllerFromViewController:fromViewController];
        return;
    }

    CNContactViewController *_Nullable contactViewController;
    CNContact *_Nullable cnContact = nil;
    if (existingContact) {
        CNMutableContact *updatedContact = [existingContact mutableCopy];
        NSMutableArray<CNLabeledValue *> *phoneNumbers
            = (updatedContact.phoneNumbers ? [updatedContact.phoneNumbers mutableCopy] : [NSMutableArray new]);
        // Only add recipientId as a phone number for the existing contact
        // if its not already present.
        BOOL hasPhoneNumber = NO;
        for (CNLabeledValue *existingPhoneNumber in phoneNumbers) {
            CNPhoneNumber *phoneNumber = existingPhoneNumber.value;
            if ([phoneNumber.stringValue isEqualToString:recipientId]) {
                OWSFailDebug(@"We currently only should the 'add to existing contact' UI for phone numbers that don't "
                             @"correspond to an existing user.");
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
        cnContact = [self.contactsManager cnContactWithId:signalAccount.contact.cnContactId];
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

        newContact.givenName = [self.profileManager profileNameForRecipientId:recipientId];

        contactViewController = [CNContactViewController viewControllerForNewContact:newContact];
    }

    contactViewController.delegate = fromViewController;
    contactViewController.allowsActions = NO;
    contactViewController.allowsEditing = YES;
    contactViewController.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:CommonStrings.cancelButton
                                         style:UIBarButtonItemStylePlain
                                        target:fromViewController
                                        action:@selector(didFinishEditingContact)];

    OWSNavigationController *modal = [[OWSNavigationController alloc] initWithRootViewController:contactViewController];

    // We want the presentation to imply a "replacement" in this case.
    if (shouldEditImmediately) {
        modal.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    [fromViewController presentViewController:modal animated:YES completion:nil];
}

- (void)blockListCacheDidUpdate:(OWSBlockListCache *)blocklistCache
{
    OWSAssertIsOnMainThread();
    [self updateContacts];
}

@end

NS_ASSUME_NONNULL_END
