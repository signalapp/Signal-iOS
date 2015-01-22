//
//  ShowGroupMembersViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "ShowGroupMembersViewController.h"
#import "SignalsViewController.h"
#import "ContactDetailTableViewController.h"
#import "Contact.h"
#import "ContactsManager.h"
#import "Environment.h"
#import "FunctionalUtil.h"


#import "Contact.h"
#import "TSGroupModel.h"
#import "SecurityUtils.h"
#import "SignalKeyingStorage.h"

#import "UIUtil.h"
#import "DJWActionSheet+OWS.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static NSString* const kUnwindToMessagesViewSegue = @"UnwindToMessagesViewSegue";

@interface ShowGroupMembersViewController () {
    NSArray* contacts;
}
@property TSGroupThread* thread;

@end
@implementation ShowGroupMembersViewController

- (void)configWithThread:(TSGroupThread *)gThread{
    _thread = gThread;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _thread.groupModel.groupName;

    NSMutableArray *contactsInGroup = [[NSMutableArray alloc] init];
    // Select the contacts already selected:
    for (Contact* contact in [Environment getCurrent].contactsManager.textSecureContacts) {
        // TODOGROUP this will not scale well; ~same code in NewGroupViewController
        NSMutableSet *usersInGroup = [NSMutableSet setWithArray:_thread.groupModel.groupMemberIds];
        NSMutableArray *contactPhoneNumbers = [[NSMutableArray alloc] init];
        for(PhoneNumber* number in [contact parsedPhoneNumbers]) {
            [contactPhoneNumbers addObject:[number toE164]];
        }
        [usersInGroup intersectSet:[NSSet setWithArray:contactPhoneNumbers]];
        if([usersInGroup count]>0) {
            [contactsInGroup addObject:contact];
        }
    }
    contacts = contactsInGroup;

    
    [self initializeTableView];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Initializers


-(void)initializeTableView
{
    self.tableView.tableFooterView = [[UIView alloc]initWithFrame:CGRectZero];
}

#pragma mark - Keyboard notifications



#pragma mark - Actions

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[contacts count]+1;
    
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SearchCell"];
    
    if (cell == nil) {
        
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier: indexPath.row == 0 ? @"HeaderCell" : @"GroupSearchCell"];
    }
    if (indexPath.row > 0) {
        Contact* contact = [self contactForIndexPath:indexPath];
        
        cell.textLabel.attributedText = [self attributedStringForContact:contact inCell:cell];
    
    } else {
        cell.textLabel.text = @"Group conversation Recipients:";
        cell.textLabel.textColor = [UIColor lightGrayColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    return cell;
}


-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(indexPath.row>0) {
        [self performSegueWithIdentifier:@"DetailSegue" sender:self];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
}

-(Contact*)contactForIndexPath:(NSIndexPath*)indexPath
{
    Contact *contact = contacts[(NSUInteger)(indexPath.row-1)];
    return contact;
}


#pragma mark - Segue

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"DetailSegue"]) {
        ContactDetailTableViewController * detailvc = [segue destinationViewController];
        NSIndexPath * indexPath = [self.tableView indexPathForSelectedRow]; // this is nil
        Contact *contact = [self contactForIndexPath:indexPath];
        detailvc.contact = contact;
    }
}



#pragma mark - Cell Utility

- (NSAttributedString *)attributedStringForContact:(Contact *)contact inCell:(UITableViewCell*)cell {
    NSMutableAttributedString *fullNameAttributedString = [[NSMutableAttributedString alloc] initWithString:contact.fullName];
    
    UIFont *firstNameFont;
    UIFont *lastNameFont;
    
    if (ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst) {
        firstNameFont = [UIFont ows_lightFontWithSize:cell.textLabel.font.pointSize];
        lastNameFont  = [UIFont systemFontOfSize:cell.textLabel.font.pointSize];
    } else{
        firstNameFont = [UIFont ows_lightFontWithSize:cell.textLabel.font.pointSize];
        lastNameFont  = [UIFont systemFontOfSize:cell.textLabel.font.pointSize];
    }
    [fullNameAttributedString addAttribute:NSFontAttributeName value:firstNameFont range:NSMakeRange(0, contact.firstName.length)];
    [fullNameAttributedString addAttribute:NSFontAttributeName value:lastNameFont range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];
    
    [fullNameAttributedString addAttribute:NSForegroundColorAttributeName value:[UIColor blackColor] range:NSMakeRange(0, contact.fullName.length)];
    return fullNameAttributedString;
}

@end
