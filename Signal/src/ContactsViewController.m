//
//  ContactsViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 29/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"
#import "Contact.h"
#import "ContactsManager.h"
#import "PhoneNumberDirectoryFilterManager.h"

#import "DemoDataFactory.h"

#import <AddressBook/AddressBook.h>
#import "ContactsViewController.h"

static NSString *const CONTACT_BROWSE_TABLE_CELL_IDENTIFIER = @"ContactTableViewCell";


@interface ContactsViewController () {
    NSMutableDictionary *_latestAlphabeticalContacts;
    NSArray *_latestSortedAlphabeticalContactKeys;
    NSArray *_latestContacts;
}

@end

@implementation ContactsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    [self.tableView setContentOffset:CGPointMake(0, self.searchBar.frame.size.height)];
    
    [self setupContacts];
    [self.tableView reloadData];
    
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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
    return _latestSortedAlphabeticalContactKeys;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CONTACT_BROWSE_TABLE_CELL_IDENTIFIER];
    
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:CONTACT_BROWSE_TABLE_CELL_IDENTIFIER];
    }
    
    NSArray *contactSection = [self contactsForSectionIndex:(NSUInteger)indexPath.section];
    Contact *contact = contactSection[(NSUInteger)indexPath.row];
    
    //TODO: real setup of custom cell
    cell.textLabel.text = contact.firstName;
    
    return cell;
}

@end
