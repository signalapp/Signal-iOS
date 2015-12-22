//
//  ShowGroupMembersViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "ShowGroupMembersViewController.h"


#import "SignalsViewController.h"

#import "ContactsManager.h"
#import "Environment.h"
#import "GroupContactsResult.h"

#import "UIUtil.h"

#import <AddressBookUI/AddressBookUI.h>

static NSString *const kUnwindToMessagesViewSegue = @"UnwindToMessagesViewSegue";

@interface ShowGroupMembersViewController ()

@property GroupContactsResult *groupContacts;
@property TSGroupThread *thread;

@end

@implementation ShowGroupMembersViewController

- (void)configWithThread:(TSGroupThread *)gThread {
    _thread = gThread;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    self.title = _thread.groupModel.groupName;

    [self initializeTableView];

    self.groupContacts =
        [[GroupContactsResult alloc] initWithMembersId:self.thread.groupModel.groupMemberIds without:nil];

    [[Environment.getCurrent contactsManager]
            .getObservableContacts watchLatestValue:^(id latestValue) {
      self.groupContacts =
          [[GroupContactsResult alloc] initWithMembersId:self.thread.groupModel.groupMemberIds without:nil];
      [self.tableView reloadData];
    }
                                           onThread:[NSThread mainThread]
                                     untilCancelled:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Initializers


- (void)initializeTableView {
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

#pragma mark - Actions

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self.groupContacts numberOfMembers] + 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SearchCell"];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:indexPath.row == 0 ? @"HeaderCell" : @"GroupSearchCell"];
    }
    if (indexPath.row > 0) {
        NSIndexPath *relativeIndexPath = [NSIndexPath indexPathForRow:indexPath.row - 1 inSection:indexPath.section];
        if ([self.groupContacts isContactAtIndexPath:relativeIndexPath]) {
            Contact *contact              = [self contactForIndexPath:relativeIndexPath];
            cell.textLabel.attributedText = [self attributedStringForContact:contact inCell:cell];
        } else {
            cell.textLabel.text = [self.groupContacts identifierForIndexPath:relativeIndexPath];
        }
    } else {
        cell.textLabel.text      = @"Group Members:";
        cell.textLabel.textColor = [UIColor lightGrayColor];
        cell.selectionStyle      = UITableViewCellSelectionStyleNone;
    }

    tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    return cell;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSIndexPath *relativeIndexPath = [NSIndexPath indexPathForRow:indexPath.row - 1 inSection:indexPath.section];

    if (indexPath.row > 0 && [self.groupContacts isContactAtIndexPath:relativeIndexPath]) {
        ABPersonViewController *view = [[ABPersonViewController alloc] init];

        Contact *contact                = [self.groupContacts contactForIndexPath:relativeIndexPath];
        ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);
        view.displayedPerson =
            ABAddressBookGetPersonWithRecordID(addressBookRef, contact.recordID); // Assume person is already defined.
        view.allowsActions = NO;
        view.allowsEditing = YES;

        [self.navigationController pushViewController:view animated:YES];
    } else {
        ABUnknownPersonViewController *view = [[ABUnknownPersonViewController alloc] init];

        ABRecordRef aContact = ABPersonCreate();
        CFErrorRef anError   = NULL;

        ABMultiValueRef phone = ABMultiValueCreateMutable(kABMultiStringPropertyType);
        ABMultiValueAddValueAndLabel(
            phone,
            (__bridge CFTypeRef)[self.tableView cellForRowAtIndexPath:indexPath].textLabel.text,
            kABPersonPhoneMainLabel,
            NULL);

        ABRecordSetValue(aContact, kABPersonPhoneProperty, phone, &anError);
        CFRelease(phone);

        if (!anError && aContact) {
            view.displayedPerson           = aContact; // Assume person is already defined.
            view.allowsAddingToAddressBook = YES;
            [self.navigationController pushViewController:view animated:YES];
        }
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (Contact *)contactForIndexPath:(NSIndexPath *)indexPath {
    Contact *contact = [self.groupContacts contactForIndexPath:indexPath];
    return contact;
}

#pragma mark - Cell Utility

- (NSAttributedString *)attributedStringForContact:(Contact *)contact inCell:(UITableViewCell *)cell {
    NSMutableAttributedString *fullNameAttributedString =
        [[NSMutableAttributedString alloc] initWithString:contact.fullName];

    UIFont *firstNameFont;
    UIFont *lastNameFont;

    if (ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst) {
        firstNameFont = [UIFont ows_mediumFontWithSize:cell.textLabel.font.pointSize];
        lastNameFont  = [UIFont ows_regularFontWithSize:cell.textLabel.font.pointSize];
    } else {
        firstNameFont = [UIFont ows_regularFontWithSize:cell.textLabel.font.pointSize];
        lastNameFont  = [UIFont ows_mediumFontWithSize:cell.textLabel.font.pointSize];
    }
    [fullNameAttributedString addAttribute:NSFontAttributeName
                                     value:firstNameFont
                                     range:NSMakeRange(0, contact.firstName.length)];
    [fullNameAttributedString addAttribute:NSFontAttributeName
                                     value:lastNameFont
                                     range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];

    [fullNameAttributedString addAttribute:NSForegroundColorAttributeName
                                     value:[UIColor blackColor]
                                     range:NSMakeRange(0, contact.fullName.length)];

    if (ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst) {
        [fullNameAttributedString addAttribute:NSForegroundColorAttributeName
                                         value:[UIColor ows_darkGrayColor]
                                         range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];
    } else {
        [fullNameAttributedString addAttribute:NSForegroundColorAttributeName
                                         value:[UIColor ows_darkGrayColor]
                                         range:NSMakeRange(0, contact.firstName.length)];
    }
    return fullNameAttributedString;
}

@end
