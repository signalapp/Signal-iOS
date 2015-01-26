//
//  MessageComposeTableViewController.m
//  
//
//  Created by Dylan Bourgeois on 02/11/14.
//
//

#import "Environment.h"
#import "Contact.h"
#import "PhoneNumberUtil.h"
#import "MessageComposeTableViewController.h"
#import "MessagesViewController.h"
#import "SignalsViewController.h"
#import "NotificationManifest.h"
#import "PhoneNumberDirectoryFilterManager.h"

#import <MessageUI/MessageUI.h>
#import <MessageUI/MFMessageComposeViewController.h>

#import "ContactTableViewCell.h"
#import "UIColor+OWS.h"

@interface MessageComposeTableViewController () <UISearchBarDelegate, UISearchResultsUpdating, MFMessageComposeViewControllerDelegate>
{
    UIButton* sendTextButton;
    NSString* currentSearchTerm;
    
    NSArray* contacts;
    NSArray* searchResults;
}

@property (nonatomic, strong) UISearchController *searchController;

@end

@implementation MessageComposeTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];    
    [self initializeSearch];
    
    contacts = [[Environment getCurrent] contactsManager].textSecureContacts;
    searchResults = contacts;

    self.tableView.tableFooterView = [[UIView alloc]initWithFrame:CGRectZero];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Initializers

-(void)initializeSearch
{
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    
    self.searchController.searchResultsUpdater = self;
    
    self.searchController.dimsBackgroundDuringPresentation = NO;
    
    self.searchController.hidesNavigationBarDuringPresentation = NO;
    
    self.searchController.searchBar.frame = CGRectMake(self.searchController.searchBar.frame.origin.x, self.searchController.searchBar.frame.origin.y, self.searchController.searchBar.frame.size.width, 44.0);
    
    self.tableView.tableHeaderView = self.searchController.searchBar;
    
    
    self.searchController.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchController.searchBar.delegate = self;
    self.searchController.searchBar.placeholder = @"Search by name or number";

    sendTextButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [sendTextButton setBackgroundColor:[UIColor ows_materialBlueColor]];
    [sendTextButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    sendTextButton.frame = CGRectMake(self.searchController.searchBar.frame.origin.x, self.searchController.searchBar.frame.origin.y + 44.0, self.searchController.searchBar.frame.size.width, 44.0);
    [self.view addSubview:sendTextButton];
    sendTextButton.hidden = YES;
    
    [sendTextButton addTarget:self action:@selector(sendText) forControlEvents:UIControlEventTouchUpInside];
    [self initializeObservers];
    [self initializeRefreshControl];
    
}

-(void)initializeObservers
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contactsDidRefresh) name:NOTIFICATION_DIRECTORY_WAS_UPDATED object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contactRefreshFailed) name:NOTIFICATION_DIRECTORY_FAILED object:nil];
}

-(void)initializeRefreshControl {
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc]init];
    [refreshControl addTarget:self action:@selector(refreshContacts) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refreshControl;
    [self.tableView addSubview:self.refreshControl];
    
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

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    sendTextButton.hidden = YES;
}


#pragma mark - Filter

- (void)filterContentForSearchText:(NSString*)searchText scope:(NSString*)scope
{
    // search by contact name or number
    NSString *normalizedNumber = [PhoneNumberUtil normalizePhoneNumber:searchText];
    NSPredicate *resultPredicate = [NSPredicate predicateWithFormat:@"(fullName contains[c] %@) OR (allPhoneNumbers contains[c] %@)", searchText, normalizedNumber];
    searchResults = [contacts filteredArrayUsingPredicate:resultPredicate];
    if (!searchResults.count && _searchController.searchBar.text.length == 0) searchResults = contacts;
    
    // formats the user input into a pretty number to display
    NSString *formattedNumber = [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:normalizedNumber];
    
    // text to a non-signal number if we have no results and a valid phone #
    if (searchResults.count == 0 && normalizedNumber.length > 8) {
        NSString *sendTextTo = @"Send SMS to: ";
        sendTextTo = [sendTextTo stringByAppendingString:formattedNumber];
        [sendTextButton setTitle:sendTextTo forState:UIControlStateNormal];
        sendTextButton.hidden = NO;
        currentSearchTerm = formattedNumber;
    } else {
        sendTextButton.hidden = YES;
    }

}


#pragma mark - Send Normal Text to Unknown Contact

- (void)sendText {
    NSString *confirmMessage = @"Would you like to invite the following number to Signal: ";
    confirmMessage = [confirmMessage stringByAppendingString:currentSearchTerm];
    confirmMessage = [confirmMessage stringByAppendingString:@"?"];
    UIAlertController *alertController = [UIAlertController
                                          alertControllerWithTitle:@"Confirm"
                                                           message:confirmMessage
                                                    preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *cancelAction = [UIAlertAction
                                   actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel action")
                                   style:UIAlertActionStyleCancel
                                   handler:^(UIAlertAction *action)
                                   {
                                       NSLog(@"Cancel action");
                                   }];
    
    UIAlertAction *okAction = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", @"OK action")
                                         style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *action) {
                                           [self.searchController setActive:NO];
                                           
                                           UIDevice *device = [UIDevice currentDevice];
                                           if ([[device model] isEqualToString:@"iPhone"]) {
                                               MFMessageComposeViewController *picker = [[MFMessageComposeViewController alloc] init];
                                               picker.messageComposeDelegate = self;
                                               
                                               picker.recipients = [NSArray arrayWithObject:currentSearchTerm];
                                               picker.body = @"I'm inviting you to install Signal! Here is the link: https://itunes.apple.com/us/app/signal-private-messenger/id874139669?mt=8";
                                               [self presentViewController:picker animated:YES completion:^{
                                                   [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
                                               }];
                                           } else {
                                               // TODO: better backup for iPods (just don't support on)
                                               UIAlertView *notPermitted=[[UIAlertView alloc] initWithTitle:@"Alert" message:@"Your device doesn't support this feature." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
                                               
                                               [notPermitted show];
                                           }
                                       }];
    
    [alertController addAction:cancelAction];
    [alertController addAction:okAction];
    sendTextButton.hidden = YES;
    self.searchController.searchBar.text = @"";
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    [self presentViewController:alertController animated:YES completion:nil];
}

#pragma mark - SMS Composer Delegate

// called on completion of message screen
- (void)messageComposeViewController:(MFMessageComposeViewController *)controller didFinishWithResult:(MessageComposeResult) result
{
    switch (result) {
        case MessageComposeResultCancelled:
            break;
        case MessageComposeResultFailed: {
            UIAlertView *warningAlert = [[UIAlertView alloc] initWithTitle:@"Error" message:@"Failed to send SMS!" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [warningAlert show];
            break;
        }
        case MessageComposeResultSent: {
            [self dismissViewControllerAnimated:NO completion:^{
                NSLog(@"view controller dismissed");
            }];
            UIAlertView *successAlert = [[UIAlertView alloc] initWithTitle:@"Success" message:@"You've invited your friend to use Signal!" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [successAlert show];
            break;
        }
        default:
            break;
    }
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View Data Source

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

    cell.shouldShowContactButtons = NO;

    [cell configureWithContact:[self contactForIndexPath:indexPath]];
    
    tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    return cell;
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 52.0f;
}

#pragma mark - Table View delegate
- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    Contact *person = [self contactForIndexPath:indexPath];
    return person.isTextSecureContact ? indexPath : nil;
}


-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *identifier = [[[self contactForIndexPath:indexPath] textSecureIdentifiers] firstObject];
    
    [self dismissViewControllerAnimated:YES completion:^(){
        [Environment messageIdentifier:identifier];
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

#pragma mark Refresh controls

- (void)contactRefreshFailed {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:TIMEOUT message:TIMEOUT_CONTACTS_DETAIL delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"") otherButtonTitles:nil];
    [alert show];
    [self.refreshControl endRefreshing];
}

- (void)contactsDidRefresh {
    [self updateSearchResultsForSearchController:self.searchController];
    [self.refreshControl endRefreshing];
}

- (void)refreshContacts {
    Environment *env = [Environment getCurrent];
    PhoneNumberDirectoryFilterManager *manager = [env phoneDirectoryManager];
    [manager forceUpdate];
}

#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    self.searchController.active = NO;
}

-(IBAction)closeAction:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}



@end
