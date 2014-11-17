//
//  ContactsTableViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 29/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "ContactsTableViewController.h"
#import "ContactDetailTableViewController.h"
#import "DialerViewController.h"

#import "ContactTableViewCell.h"

#import "Environment.h"
#import "Contact.h"
#import "ContactsManager.h"
#import "PhoneNumberDirectoryFilterManager.h"

#import "DemoDataFactory.h"

#import <AddressBook/AddressBook.h>

static NSString *const CONTACT_BROWSE_TABLE_CELL_IDENTIFIER = @"ContactTableViewCell";


@interface ContactsTableViewController () {
    NSMutableDictionary *_latestAlphabeticalContacts;
    NSArray *_latestSortedAlphabeticalContactKeys;
    NSArray *_latestContacts;
}
@end

@implementation ContactsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    //Hide search bar
    self.tableView.contentOffset = CGPointMake(0, 44);
    
    [self setupContacts];
    [self.tableView reloadData];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Contact functions

- (void)setupContacts {
    //    ObservableValue *observableContacts = Environment.getCurrent.contactsManager.getObservableWhisperUsers;
    //
    //    [observableContacts watchLatestValue:^(NSArray *latestContacts) {
    //        _latestContacts = latestContacts;
    //    } onThread:NSThread.mainThread untilCancelled:nil];
    _latestContacts = [DemoDataFactory makeFakeContacts];
    
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"firstName" ascending:YES];
    NSArray *sortDescriptors = [NSArray arrayWithObject:sortDescriptor];
    _latestSortedAlphabeticalContactKeys = [_latestContacts sortedArrayUsingDescriptors:sortDescriptors];
    
    _latestAlphabeticalContacts = [self alphabetDictionaryInit];
    
    for (Contact*contact in _latestContacts)
    {
        NSString * firstLetter = [contact.firstName substringToIndex:1];
        
        NSMutableArray * mutArray = [[_latestAlphabeticalContacts objectForKey:firstLetter] mutableCopy];
        if (![mutArray containsObject:contact])
            [mutArray addObject:contact];
        [_latestAlphabeticalContacts setObject:mutArray forKey:firstLetter];
        
    }
    
    _latestSortedAlphabeticalContactKeys = [[_latestAlphabeticalContacts allKeys]sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    
}

- (NSArray *)contactsForSectionIndex:(NSUInteger)index {
    return [_latestAlphabeticalContacts valueForKey:_latestSortedAlphabeticalContactKeys[index]];
}


-(NSMutableDictionary*)alphabetDictionaryInit
{
    NSDictionary * dic;
    
    dic = @{
            @"A": @[],
            @"B": @[],
            @"C": @[],
            @"D": @[],
            @"E": @[],
            @"F": @[],
            @"G": @[],
            @"H": @[],
            @"I": @[],
            @"J": @[],
            @"K": @[],
            @"L": @[],
            @"M": @[],
            @"N": @[],
            @"O": @[],
            @"P": @[],
            @"Q": @[],
            @"R": @[],
            @"S": @[],
            @"T": @[],
            @"U": @[],
            @"V": @[],
            @"W": @[],
            @"X": @[],
            @"Y": @[],
            @"Z": @[],
            
            };
    
    return [dic mutableCopy];
}


#pragma mark - Table view data source
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[[self contactsForSectionIndex:(NSUInteger)section] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([[self contactsForSectionIndex:(NSUInteger)section] count])
        return _latestSortedAlphabeticalContactKeys[(NSUInteger)section];
    else return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)[[_latestAlphabeticalContacts allKeys] count];
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    tableView.sectionIndexBackgroundColor = [UIColor clearColor];
    return _latestSortedAlphabeticalContactKeys;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ContactTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CONTACT_BROWSE_TABLE_CELL_IDENTIFIER];
    
    if (!cell) {
        cell = [[ContactTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:CONTACT_BROWSE_TABLE_CELL_IDENTIFIER];
    }
    
    NSArray *contactSection = [self contactsForSectionIndex:(NSUInteger)indexPath.section];
    Contact *contact = contactSection[(NSUInteger)indexPath.row];
    
    [cell configureWithContact:contact];
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self performSegueWithIdentifier:@"DetailSegue" sender:self];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Segue

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"DetailSegue"])
    {
        ContactDetailTableViewController * detailvc = [segue destinationViewController];
        NSIndexPath * indexPath = [self.tableView indexPathForSelectedRow];
        NSArray *contactSection = [self contactsForSectionIndex:(NSUInteger)indexPath.section];
        Contact *contact = contactSection[(NSUInteger)indexPath.row];
        detailvc.contact = contact;
    }
}

#pragma mark - IBAction

-(IBAction)presentDialer:(id)sender
{
    
    DialerViewController * dialer = [DialerViewController new];
    
    UINavigationController *navigationController = [[UINavigationController alloc]
                                                   initWithRootViewController:dialer];
    navigationController.tabBarController.hidesBottomBarWhenPushed = NO;
    
    dialer.phoneNumber = nil;
    
    self.tabBarController.providesPresentationContextTransitionStyle = YES;
    self.tabBarController.definesPresentationContext = YES;
    [navigationController setModalPresentationStyle:UIModalPresentationOverCurrentContext];
    navigationController.hidesBottomBarWhenPushed = YES;
    navigationController.navigationBarHidden=YES;
    
    [self.tabBarController presentViewController:navigationController animated:YES completion:^(){
        
    }];
}

@end

