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


@interface ContactsTableViewController () <UISearchBarDelegate, UISearchResultsUpdating>
{
    NSMutableDictionary *latestAlphabeticalContacts;
    NSArray *latestSortedAlphabeticalContactKeys;
    NSArray * latestContacts;
    
    NSArray * searchResults;
}

@property (nonatomic, strong) UISearchController *searchController;

@end

@implementation ContactsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    //Hide search bar
    self.tableView.contentOffset = CGPointMake(0, 44);
    
    [self initializeSearch];

    [self setupContacts];
    searchResults = latestContacts;
    
    [self.tableView reloadData];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Initializers

-(void)initializeSearch
{
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    
    self.searchController.searchResultsUpdater = self;
    
    self.searchController.searchBar.frame = CGRectMake(self.searchController.searchBar.frame.origin.x, self.searchController.searchBar.frame.origin.y, self.searchController.searchBar.frame.size.width, 44.0);
    
    self.tableView.tableHeaderView = self.searchController.searchBar;
    
    self.searchController.dimsBackgroundDuringPresentation = NO;
    self.searchController.hidesNavigationBarDuringPresentation = NO;
    
    self.definesPresentationContext = YES;
    
    
}

#pragma mark - UISearchResultsUpdating

-(void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    
    NSString *searchString = [self.searchController.searchBar text];
    
    [self filterContentForSearchText:searchString scope:nil];
    
    [self.tableView reloadData];
}


#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope {
    [self updateSearchResultsForSearchController:self.searchController];
}


#pragma mark - Filter

- (void)filterContentForSearchText:(NSString*)searchText scope:(NSString*)scope
{
    NSPredicate *resultPredicate = [NSPredicate predicateWithFormat:@"fullName contains[c] %@", searchText];
    searchResults = [latestContacts filteredArrayUsingPredicate:resultPredicate];
    if (!searchResults.count && _searchController.searchBar.text.length == 0) searchResults = latestContacts;
}


#pragma mark - Contact functions

- (void)setupContacts {
    //    ObservableValue *observableContacts = Environment.getCurrent.contactsManager.getObservableWhisperUsers;
    //
    //    [observableContacts watchLatestValue:^(NSArray *latestContacts) {
    //        _latestContacts = latestContacts;
    //    } onThread:NSThread.mainThread untilCancelled:nil];
    
    latestContacts = [DemoDataFactory makeFakeContacts];
    
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"firstName" ascending:YES];
    NSArray *sortDescriptors = [NSArray arrayWithObject:sortDescriptor];
    latestSortedAlphabeticalContactKeys = [latestContacts sortedArrayUsingDescriptors:sortDescriptors];
    
    latestAlphabeticalContacts = [self alphabetDictionaryInit];
    
    for (Contact*contact in latestContacts)
    {
        NSString * firstLetter = [contact.firstName substringToIndex:1];
        
        NSMutableArray * mutArray = [[latestAlphabeticalContacts objectForKey:firstLetter] mutableCopy];
        if (![mutArray containsObject:contact])
            [mutArray addObject:contact];
        [latestAlphabeticalContacts setObject:mutArray forKey:firstLetter];
        
    }
    
    latestSortedAlphabeticalContactKeys = [[latestAlphabeticalContacts allKeys]sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    
}

- (NSArray *)contactsForSectionIndex:(NSUInteger)index {
    return [latestAlphabeticalContacts valueForKey:latestSortedAlphabeticalContactKeys[index]];
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
    if (self.searchController.active) {
        return (NSInteger)[searchResults count];
    } else {
        return (NSInteger)[[self contactsForSectionIndex:(NSUInteger)section] count];
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    
    if ([[self contactsForSectionIndex:(NSUInteger)section] count]) {
        return latestSortedAlphabeticalContactKeys[(NSUInteger)section];
    } else {
        return nil;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.searchController.active) {
        return 1;
    } else {
        return (NSInteger)[[latestAlphabeticalContacts allKeys] count];
    }
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    tableView.sectionIndexBackgroundColor = [UIColor clearColor];
    return latestSortedAlphabeticalContactKeys;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ContactTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CONTACT_BROWSE_TABLE_CELL_IDENTIFIER];
    
    if (!cell) {
        cell = [[ContactTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:CONTACT_BROWSE_TABLE_CELL_IDENTIFIER];
    }
    
    
    [cell configureWithContact:[self contactForIndexPath:indexPath]];
    
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self performSegueWithIdentifier:@"DetailSegue" sender:self];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

-(Contact*)contactForIndexPath:(NSIndexPath*)indexPath
{
    Contact *contact = nil;
    
    if (self.searchController.active) {
        contact = [searchResults objectAtIndex:(NSUInteger)indexPath.row];
    } else {
        NSArray *contactSection = [self contactsForSectionIndex:(NSUInteger)indexPath.section];
        contact = contactSection[(NSUInteger)indexPath.row];
    }
    
    return contact;
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 44.0f;
}

#pragma mark - Segue

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"DetailSegue"])
    {
        Contact *contact = nil;
        ContactDetailTableViewController * detailvc = [segue destinationViewController];
        NSIndexPath * indexPath = [self.tableView indexPathForSelectedRow];
        
        if (self.searchController.active) {
            contact = [searchResults objectAtIndex:(NSUInteger)indexPath.row];
        } else {
            NSArray *contactSection = [self contactsForSectionIndex:(NSUInteger)indexPath.section];
            contact = contactSection[(NSUInteger)indexPath.row];
        }
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

