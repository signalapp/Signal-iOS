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
#import "LocalizableText.h"
#import "PhoneNumberDirectoryFilterManager.h"
#import "NotificationManifest.h"

#import <AddressBook/AddressBook.h>

#define REFRESH_TIMEOUT 20

static NSString *const CONTACT_BROWSE_TABLE_CELL_IDENTIFIER = @"ContactTableViewCell";


@interface ContactsTableViewController () <UISearchBarDelegate, UISearchResultsUpdating>
{
    NSDictionary *latestAlphabeticalContacts;
    NSArray *searchResults;
}


@property NSArray *latestSortedAlphabeticalContactKeys;
@property NSArray *latestContacts;
@property (nonatomic, strong) UISearchController *searchController;

@end

@implementation ContactsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contactsDidRefresh) name:NOTIFICATION_DIRECTORY_WAS_UPDATED object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contactRefreshFailed) name:NOTIFICATION_DIRECTORY_FAILED object:nil];
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc]
                                        init];
    [refreshControl addTarget:self action:@selector(refreshContacts) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refreshControl;
    [self.contactTableView addSubview:self.refreshControl];
    
    self.tableView.contentOffset = CGPointMake(0, 44);
    
    [self initializeSearch];
    
    [self setupContacts];
    
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
    
    self.searchController.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    
    
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
    searchResults = [self.latestContacts filteredArrayUsingPredicate:resultPredicate];
    if (!searchResults.count && _searchController.searchBar.text.length == 0) searchResults = self.latestContacts;
}


#pragma mark - Contact functions

- (void)setupContacts {
    ObservableValue *observableContacts = Environment.getCurrent.contactsManager.getObservableRedPhoneUsers;
    [observableContacts watchLatestValue:^(NSArray *latestContacts) {
        _latestContacts = latestContacts;
        [self onSearchOrContactChange:nil];
    } onThread:NSThread.mainThread untilCancelled:nil];
}

- (NSArray *)contactsForSectionIndex:(NSUInteger)index {
    return [latestAlphabeticalContacts valueForKey:self.latestSortedAlphabeticalContactKeys[index]];
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
            @"Z": @[]
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
        return self.latestSortedAlphabeticalContactKeys[(NSUInteger)section];
    } else {
        return nil;
    }
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    [header.textLabel setTextColor:[UIColor blackColor]];
    [header.textLabel setFont:[UIFont fontWithName:@"HelveticaNeue-Thin" size:14.0f]];
    
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
    return _latestSortedAlphabeticalContactKeys;
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

-(IBAction)presentDialer:(id)sender {
    DialerViewController * dialer = [DialerViewController new];
    
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:dialer];
    navigationController.tabBarController.hidesBottomBarWhenPushed = NO;
    
    dialer.phoneNumber = nil;
    
    self.tabBarController.providesPresentationContextTransitionStyle = YES;
    self.tabBarController.definesPresentationContext = YES;
    [navigationController setModalPresentationStyle:UIModalPresentationOverCurrentContext];
    navigationController.hidesBottomBarWhenPushed = YES;
    navigationController.navigationBarHidden=YES;
    
    [self.tabBarController presentViewController:navigationController animated:YES completion:nil];
}

#pragma mark - Refresh controls

- (void)onSearchOrContactChange:(NSString *)searchTerm {
    if (_latestContacts) {
        latestAlphabeticalContacts = [ContactsManager groupContactsByFirstLetter:_latestContacts
                                                             matchingSearchString:searchTerm];
        
        NSArray *contactKeys = [latestAlphabeticalContacts allKeys];
        _latestSortedAlphabeticalContactKeys = [contactKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
        [_contactTableView reloadData];
    }
}

- (void)refreshContacts{
    Environment *env = [Environment getCurrent];
    PhoneNumberDirectoryFilterManager *manager = [env phoneDirectoryManager];
    [manager forceUpdate];
}

- (void)contactRefreshFailed{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:TIMEOUT message:TIMEOUT_CONTACTS_DETAIL delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"") otherButtonTitles:nil];
    [alert show];
    [self.refreshControl endRefreshing];
}

- (void)contactsDidRefresh{
    [self.refreshControl endRefreshing];
}

@end

