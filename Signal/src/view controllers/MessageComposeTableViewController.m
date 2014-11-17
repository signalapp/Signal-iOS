//
//  MessageComposeTableViewController.m
//  
//
//  Created by Dylan Bourgeois on 02/11/14.
//
//

#import "MessageComposeTableViewController.h"
#import "MessagesViewController.h"
#import "SignalsViewController.h"

#import "ContactTableViewCell.h"

@interface MessageComposeTableViewController () <UISearchBarDelegate, UISearchResultsUpdating>
{
    NSArray* contacts;
    NSArray* searchResults;
}

@property (nonatomic, strong) UISearchController *searchController;

@end

@implementation MessageComposeTableViewController



- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    
    self.searchController.searchResultsUpdater = self;
    
    self.searchController.searchBar.frame = CGRectMake(self.searchController.searchBar.frame.origin.x, self.searchController.searchBar.frame.origin.y, self.searchController.searchBar.frame.size.width, 44.0);
    
    self.tableView.tableHeaderView = self.searchController.searchBar;
    self.definesPresentationContext = YES;
    
    contacts = [DemoDataFactory makeFakeContacts];
    searchResults = contacts;


    self.tableView.tableFooterView = [[UIView alloc]initWithFrame:CGRectZero];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
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
    searchResults = [contacts filteredArrayUsingPredicate:resultPredicate];
    if (!searchResults.count && _searchController.searchBar.text.length == 0) searchResults = contacts;
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    
    if (self.searchController.active) {
        return (NSInteger)[searchResults count];
    } else {
        return (NSInteger)[contacts count];
    }
    
}


- (ContactTableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ContactTableViewCell *cell = (ContactTableViewCell*)[tableView dequeueReusableCellWithIdentifier:@"ContactTableViewCell"];
    
    if (cell == nil) {
        cell = [[ContactTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ContactTableViewCell"];
    }

    [cell configureWithContact:[self contactForIndexPath:indexPath]];
    
    tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    return cell;
}

#pragma mark - Table View delegate

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    //HACK: This is horrible due to the view hierarchy, but gets the job done. Gets a reference to the SignalsVC so we can present the conversation from it.
    
    UITabBarController * tb = (UITabBarController*)self.parentViewController.presentingViewController;
    UINavigationController* nav = (UINavigationController*)[tb.childViewControllers objectAtIndex:1];
    SignalsViewController* s = (SignalsViewController*)nav.topViewController;
    s.contactFromCompose = [self contactForIndexPath:[tableView indexPathForSelectedRow]];
    
    [self dismissViewControllerAnimated:YES completion:^(){
        [s performSegueWithIdentifier:@"showSegue" sender:nil];
    }];
}
    

-(void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    ContactTableViewCell * cell = (ContactTableViewCell*)[tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryNone;
}

-(Contact*)contactForIndexPath:(NSIndexPath*)indexPath
{
    Contact *contact = nil;
    
    if (self.searchController.active) {
        contact = [searchResults objectAtIndex:(NSUInteger)indexPath.row];
    } else {
        contact = [contacts objectAtIndex:(NSUInteger)indexPath.row];
    }

    return contact;
}


#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
  
}

-(IBAction)closeAction:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}


@end
