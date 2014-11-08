//
//  MessageComposeTableViewController.m
//  
//
//  Created by Dylan Bourgeois on 02/11/14.
//
//

#import "MessageComposeTableViewController.h"
#import "MessagesViewController.h"

@interface MessageComposeTableViewController () {
    NSArray* contacts;
    NSArray* searchResults;
}

@end

@implementation MessageComposeTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    contacts = [DemoDataFactory makeFakeContacts];
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    
    if (tableView == self.searchDisplayController.searchResultsTableView) {
        return (NSInteger)[searchResults count];
        
    } else {
        return (NSInteger)[contacts count];
    }
    
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SearchCell"];
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SearchCell"];
    }
    
    NSUInteger row = (NSUInteger)indexPath.row;
    Contact* contact = nil;
    
    if (tableView == self.searchDisplayController.searchResultsTableView) {
        contact = searchResults[row];
    } else {
        contact = contacts[row];
    }
    
    cell.textLabel.text = contact.fullName;
    
    
    tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    return cell;
}

#pragma mark - Table View delegate
-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryCheckmark;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    if ([tableView indexPathsForSelectedRows].count == 1)
    {
        //Present compose text view
        //Set destination to selected person or group
        
    }
    else if ([tableView indexPathsForSelectedRows].count > 1)
    {
        /*
         *  //Create a group with these people in it & send destination to group
         */
    }
}

-(void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryNone;
}


#pragma mark - Search 

- (void)filterContentForSearchText:(NSString*)searchText scope:(NSString*)scope
{
    NSPredicate *resultPredicate = [NSPredicate predicateWithFormat:@"fullName contains[c] %@", searchText];
    searchResults = [contacts filteredArrayUsingPredicate:resultPredicate];
}

-(BOOL)searchDisplayController:(UISearchController *)controller shouldReloadTableForSearchString:(NSString *)searchString
{
    [self filterContentForSearchText:searchString
                               scope:[[self.searchDisplayController.searchBar scopeButtonTitles]
                                      objectAtIndex:(NSUInteger)[self.searchDisplayController.searchBar
                                                     selectedScopeButtonIndex]]];
    
    return YES;
}


#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    
    NSIndexPath *indexPath = nil;
    Contact *contact = nil;
    
    if ([segue.identifier isEqualToString:@"ConversationSegue"]) {
        if (self.searchDisplayController.active) {
            indexPath = [self.searchDisplayController.searchResultsTableView indexPathForSelectedRow];
            contact = [searchResults objectAtIndex:(NSUInteger)indexPath.row];
        } else {
            indexPath = [self.tableView indexPathForSelectedRow];
            contact = [contacts objectAtIndex:(NSUInteger)indexPath.row];
        }
    }
    
    MessagesViewController * dest = [segue destinationViewController];
    dest._senderTitleString = contact.fullName;
    
    [self.navigationController presentViewController:dest animated:YES completion:^(){searchResults = nil;}];
    
}

-(IBAction)closeAction:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
