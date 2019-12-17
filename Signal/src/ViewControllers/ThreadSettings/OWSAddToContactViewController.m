//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSAddToContactViewController.h"
#import <ContactsUI/ContactsUI.h>
#import <SignalMessaging/ContactsViewHelper.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSAddToContactViewController () <CNContactViewControllerDelegate, ContactsViewHelperDelegate>

@property (nonatomic) SignalServiceAddress *address;

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;

@end

#pragma mark -

@implementation OWSAddToContactViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (void)commonInit
{
    _contactsManager = Environment.shared.contactsManager;
    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];
}

- (void)configureWithAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    _address = address;
}

#pragma mark - CNContactViewControllerDelegate

- (void)contactViewController:(CNContactViewController *)viewController
       didCompleteWithContact:(nullable CNContact *)contact
{
    OWSAssertDebug(self.navigationController);

    // We're done, pop back to the view that presented us.

    NSUInteger selfIndex = [self.navigationController.viewControllers indexOfObject:self];
    if (selfIndex == NSNotFound) {
        OWSFailDebug(@"Unexpectedly not in nav hierarchy");
        return;
    }

    UIViewController *previousVC = self.navigationController.viewControllers[selfIndex - 1];

    [self.navigationController popToViewController:previousVC animated:YES];
}

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateTableContents];
}

#pragma mark - View Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
        @"Label for 'new contact' button in conversation settings view.");

    [self updateTableContents];
}

- (nullable NSString *)displayNameForContact:(Contact *)contact
{
    OWSAssertDebug(contact);

    if (contact.fullName.length > 0) {
        return contact.fullName;
    }

    for (NSString *email in contact.emails) {
        if (email.length > 0) {
            return email;
        }
    }
    for (NSString *phoneNumber in contact.userTextPhoneNumbers) {
        if (phoneNumber.length > 0) {
            return phoneNumber;
        }
    }

    return nil;
}

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];
    contents.title = NSLocalizedString(@"CONVERSATION_SETTINGS", @"title for conversation settings screen");

    __weak OWSAddToContactViewController *weakSelf = self;

    OWSTableSection *section = [OWSTableSection new];
    section.headerTitle = NSLocalizedString(
        @"EDIT_GROUP_CONTACTS_SECTION_TITLE", @"a title for the contacts section of the 'new/update group' view.");

    for (Contact *contact in self.contactsViewHelper.contactsManager.allContacts) {
        NSString *_Nullable displayName = [self displayNameForContact:contact];
        if (displayName.length < 1) {
            continue;
        }

        // TODO: Confirm with nancy if this will work.
        NSString *cellName = [NSString stringWithFormat:@"contact.%@", NSUUID.UUID.UUIDString];
        [section addItem:[OWSTableItem disclosureItemWithText:displayName
                                      accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, cellName)
                                                  actionBlock:^{
                                                      [weakSelf presentContactViewControllerForContact:contact];
                                                  }]];
    }
    [contents addSection:section];

    self.contents = contents;
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

#pragma mark - Actions

- (void)presentContactViewControllerForContact:(Contact *)contact
{
    OWSAssertDebug(contact);
    OWSAssertDebug(self.address.isValid);

    if (!self.contactsManager.supportsContactEditing) {
        OWSFailDebug(@"Contact editing not supported");
        return;
    }
    CNContact *_Nullable cnContact;
    if (contact.cnContactId != nil) {
        cnContact = [self.contactsManager cnContactWithId:contact.cnContactId];
        OWSAssertDebug(cnContact != nil);
    }
    CNContactViewController *_Nullable contactViewController =
        [self.contactsViewHelper contactViewControllerForAddress:self.address
                                                 editImmediately:YES
                                          addToExistingCnContact:cnContact];

    if (!contactViewController) {
        OWSFailDebug(@"Unexpected missing contact VC");
        return;
    }

    contactViewController.delegate = self;

    [self.navigationController pushViewController:contactViewController animated:YES];
}

@end

NS_ASSUME_NONNULL_END
