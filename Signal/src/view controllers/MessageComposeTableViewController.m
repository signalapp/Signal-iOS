//
//  MessageComposeTableViewController.m
//
//
//  Created by Dylan Bourgeois on 02/11/14.
//
//

#import "MessageComposeTableViewController.h"

#import <MessageUI/MessageUI.h>

#import "ContactTableViewCell.h"
#import "ContactsUpdater.h"
#import "Environment.h"
#import "UIColor+OWS.h"
#import "UIUtil.h"

@interface MessageComposeTableViewController () <UISearchBarDelegate,
                                                 UISearchResultsUpdating,
                                                 MFMessageComposeViewControllerDelegate> {
    UIButton *sendTextButton;
    NSString *currentSearchTerm;
    NSArray *contacts;
    NSArray *searchResults;
}

@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UIBarButtonItem *addGroup;
@property (nonatomic, strong) UIView *loadingBackgroundView;
@property (nonatomic, strong) UIView *emptyBackgroundView;

@end

@implementation MessageComposeTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    contacts      = [[Environment getCurrent] contactsManager].signalContacts;
    searchResults = contacts;
    [self initializeSearch];

    self.searchController.searchBar.hidden          = NO;
    self.searchController.searchBar.backgroundColor = [UIColor whiteColor];

    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self createLoadingAndBackgroundViews];
    self.title = NSLocalizedString(@"MESSAGE_COMPOSEVIEW_TITLE", @"");
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}


- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if ([contacts count] == 0) {
        [self showEmptyBackgroundView:YES];
    }
}

- (UILabel *)createLabelWithFirstLine:(NSString *)firstLine andSecondLine:(NSString *)secondLine {
    UILabel *label      = [[UILabel alloc] init];
    label.textColor     = [UIColor grayColor];
    label.font          = [UIFont ows_regularFontWithSize:18.f];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 4;

    NSMutableAttributedString *fullLabelString =
        [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n%@", firstLine, secondLine]];

    [fullLabelString addAttribute:NSFontAttributeName
                            value:[UIFont ows_boldFontWithSize:15.f]
                            range:NSMakeRange(0, firstLine.length)];
    [fullLabelString addAttribute:NSFontAttributeName
                            value:[UIFont ows_regularFontWithSize:14.f]
                            range:NSMakeRange(firstLine.length + 1, secondLine.length)];
    [fullLabelString addAttribute:NSForegroundColorAttributeName
                            value:[UIColor blackColor]
                            range:NSMakeRange(0, firstLine.length)];
    [fullLabelString addAttribute:NSForegroundColorAttributeName
                            value:[UIColor ows_darkGrayColor]
                            range:NSMakeRange(firstLine.length + 1, secondLine.length)];
    label.attributedText = fullLabelString;
    // 250, 66, 140
    [label setFrame:CGRectMake([self marginSize], 100 + 140, [self contentWidth], 66)];
    return label;
}

- (UIButton *)createButtonWithTitle:(NSString *)title {
    NSDictionary *buttonTextAttributes = @{
        NSFontAttributeName : [UIFont ows_regularFontWithSize:15.0f],
        NSForegroundColorAttributeName : [UIColor ows_materialBlueColor]
    };
    UIButton *button                           = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 65, 24)];
    NSMutableAttributedString *attributedTitle = [[NSMutableAttributedString alloc] initWithString:title];
    [attributedTitle setAttributes:buttonTextAttributes range:NSMakeRange(0, [attributedTitle length])];
    [button setAttributedTitle:attributedTitle forState:UIControlStateNormal];
    [button.titleLabel setTextAlignment:NSTextAlignmentCenter];
    return button;
}

- (void)createLoadingAndBackgroundViews {
    // This will be further tweaked per design recs. It must currently be hardcoded (or we can place in separate .xib I
    // suppose) as the controller must be a TableViewController to have access to the native pull to refresh
    // capabilities. That means we can't do a UIView in the storyboard
    _loadingBackgroundView        = [[UIView alloc] initWithFrame:self.tableView.frame];
    UIImageView *loadingImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"uiEmpty"]];
    [loadingImageView setBackgroundColor:[UIColor whiteColor]];
    [loadingImageView setContentMode:UIViewContentModeCenter];
    [loadingImageView setFrame:CGRectMake(self.tableView.frame.size.width / 2.0f - 115.0f / 2.0f, 100, 115, 110)];
    loadingImageView.contentMode = UIViewContentModeCenter;
    loadingImageView.contentMode = UIViewContentModeScaleAspectFit;

    UIActivityIndicatorView *loadingProgressView =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [loadingProgressView
        setFrame:CGRectMake(self.tableView.frame.size.width / 2.0f - loadingProgressView.frame.size.width / 2.0f,
                            100 + 110 / 2.0f - loadingProgressView.frame.size.height / 2.0f,
                            loadingProgressView.frame.size.width,
                            loadingProgressView.frame.size.height)];
    [loadingProgressView setHidesWhenStopped:NO];
    [loadingProgressView startAnimating];
    UILabel *loadingLabel = [self createLabelWithFirstLine:NSLocalizedString(@"LOADING_CONTACTS_LABEL_LINE1", @"")
                                             andSecondLine:NSLocalizedString(@"LOADING_CONTACTS_LABEL_LINE2", @"")];
    [_loadingBackgroundView addSubview:loadingImageView];
    [_loadingBackgroundView addSubview:loadingProgressView];
    [_loadingBackgroundView addSubview:loadingLabel];

    _emptyBackgroundView        = [[UIView alloc] initWithFrame:self.tableView.frame];
    UIImageView *emptyImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"uiEmptyContact"]];
    [emptyImageView setBackgroundColor:[UIColor whiteColor]];
    [emptyImageView setContentMode:UIViewContentModeCenter];
    [emptyImageView setFrame:CGRectMake(self.tableView.frame.size.width / 2.0f - 115.0f / 2.0f, 100, 115, 110)];
    emptyImageView.contentMode = UIViewContentModeCenter;
    emptyImageView.contentMode = UIViewContentModeScaleAspectFit;
    UILabel *emptyLabel        = [self createLabelWithFirstLine:NSLocalizedString(@"EMPTY_CONTACTS_LABEL_LINE1", @"")
                                           andSecondLine:NSLocalizedString(@"EMPTY_CONTACTS_LABEL_LINE2", @"")];

    UIButton *inviteContactButton =
        [self createButtonWithTitle:NSLocalizedString(@"EMPTY_CONTACTS_INVITE_BUTTON", @"")];

    [inviteContactButton addTarget:self action:@selector(sendText) forControlEvents:UIControlEventTouchUpInside];
    [inviteContactButton
        setFrame:CGRectMake([self marginSize], self.tableView.frame.size.height - 200, [self contentWidth], 60)];
    [inviteContactButton.titleLabel setTextAlignment:NSTextAlignmentCenter];

    [_emptyBackgroundView addSubview:emptyImageView];
    [_emptyBackgroundView addSubview:emptyLabel];
    [_emptyBackgroundView addSubview:inviteContactButton];
}


- (void)showLoadingBackgroundView:(BOOL)show {
    if (show) {
        _addGroup = self.navigationItem.rightBarButtonItem != nil ? _addGroup : self.navigationItem.rightBarButtonItem;
        self.navigationItem.rightBarButtonItem = nil;
        self.searchController.searchBar.hidden = YES;
        self.tableView.backgroundView          = _loadingBackgroundView;
        self.refreshControl                    = nil;
        self.tableView.backgroundView.opaque   = YES;
    } else {
        [self initializeRefreshControl];
        self.navigationItem.rightBarButtonItem =
            self.navigationItem.rightBarButtonItem != nil ? self.navigationItem.rightBarButtonItem : _addGroup;
        self.searchController.searchBar.hidden = NO;
        self.tableView.backgroundView          = nil;
    }
}


- (void)showEmptyBackgroundView:(BOOL)show {
    if (show) {
        self.refreshControl = nil;
        _addGroup = self.navigationItem.rightBarButtonItem != nil ? _addGroup : self.navigationItem.rightBarButtonItem;
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithImage:[[UIImage imageNamed:@"btnRefresh--white"]
                                                       imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(refreshContacts)];
        self.navigationItem.rightBarButtonItem.imageInsets = UIEdgeInsetsMake(8, 8, 8, 8);


        self.searchController.searchBar.hidden = YES;
        self.tableView.backgroundView          = _emptyBackgroundView;
        self.tableView.backgroundView.opaque   = YES;
    } else {
        [self initializeRefreshControl];
        self.refreshControl.enabled = YES;
        self.navigationItem.rightBarButtonItem =
            self.navigationItem.rightBarButtonItem != nil ? self.navigationItem.rightBarButtonItem : _addGroup;
        self.searchController.searchBar.hidden = NO;
        self.tableView.backgroundView          = nil;
    }
}

#pragma mark - Initializers

- (void)initializeSearch {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];

    self.searchController.searchResultsUpdater = self;

    self.searchController.dimsBackgroundDuringPresentation = NO;

    self.searchController.hidesNavigationBarDuringPresentation = NO;

    self.searchController.searchBar.frame = CGRectMake(self.searchController.searchBar.frame.origin.x,
                                                       self.searchController.searchBar.frame.origin.y,
                                                       self.searchController.searchBar.frame.size.width,
                                                       44.0);

    self.tableView.tableHeaderView = self.searchController.searchBar;


    self.searchController.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchController.searchBar.delegate       = self;
    self.searchController.searchBar.placeholder    = NSLocalizedString(@"SEARCH_BYNAMEORNUMBER_PLACEHOLDER_TEXT", @"");

    sendTextButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [sendTextButton setBackgroundColor:[UIColor ows_materialBlueColor]];
    [sendTextButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    sendTextButton.frame = CGRectMake(self.searchController.searchBar.frame.origin.x,
                                      self.searchController.searchBar.frame.origin.y + 44.0,
                                      self.searchController.searchBar.frame.size.width,
                                      44.0);
    [self.view addSubview:sendTextButton];
    sendTextButton.hidden = YES;

    [sendTextButton addTarget:self action:@selector(sendText) forControlEvents:UIControlEventTouchUpInside];
    [self initializeRefreshControl];
}

- (void)initializeRefreshControl {
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshContacts) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refreshControl;
    [self.tableView addSubview:self.refreshControl];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
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

- (void)filterContentForSearchText:(NSString *)searchText scope:(NSString *)scope {
    // search by contact name or number
    NSPredicate *resultPredicate = [NSPredicate
        predicateWithFormat:@"(fullName contains[c] %@) OR (allPhoneNumbers contains[c] %@)", searchText, searchText];
    searchResults = [contacts filteredArrayUsingPredicate:resultPredicate];
    if (!searchResults.count && _searchController.searchBar.text.length == 0) {
        searchResults = contacts;
    }
    NSString *formattedNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:searchText].toE164;

    // text to a non-signal number if we have no results and a valid phone #
    if (searchResults.count == 0 && searchText.length > 8 && formattedNumber) {
        NSString *sendTextTo = NSLocalizedString(@"SEND_SMS_BUTTON", @"");
        sendTextTo           = [sendTextTo stringByAppendingString:formattedNumber];
        [sendTextButton setTitle:sendTextTo forState:UIControlStateNormal];
        sendTextButton.hidden = NO;
        currentSearchTerm     = formattedNumber;
    } else {
        sendTextButton.hidden = YES;
    }
}


#pragma mark - Send Normal Text to Unknown Contact

- (void)sendText {
    NSString *confirmMessage = NSLocalizedString(@"SEND_SMS_CONFIRM_TITLE", @"");
    if ([currentSearchTerm length] > 0) {
        confirmMessage = NSLocalizedString(@"SEND_SMS_INVITE_TITLE", @"");
        confirmMessage = [confirmMessage stringByAppendingString:currentSearchTerm];
        confirmMessage = [confirmMessage stringByAppendingString:NSLocalizedString(@"QUESTIONMARK_PUNCTUATION", @"")];
    }

    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"CONFIRMATION_TITLE", @"")
                                            message:confirmMessage
                                     preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"")
                                                           style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction *action) {
                                                           DDLogDebug(@"Cancel action");
                                                         }];

    UIAlertAction *okAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"OK", @"")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                  [self.searchController setActive:NO];

                  UIDevice *device = [UIDevice currentDevice];
                  if ([[device model] isEqualToString:@"iPhone"]) {
                      MFMessageComposeViewController *picker = [[MFMessageComposeViewController alloc] init];
                      picker.messageComposeDelegate          = self;

                      picker.recipients =
                          [currentSearchTerm length] > 0 ? [NSArray arrayWithObject:currentSearchTerm] : nil;
                      picker.body = [NSLocalizedString(@"SMS_INVITE_BODY", @"")
                          stringByAppendingString:
                              @" https://itunes.apple.com/us/app/signal-private-messenger/id874139669?mt=8"];
                      [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
                  } else {
                      // TODO: better backup for iPods (just don't support on)
                      UIAlertView *notPermitted =
                          [[UIAlertView alloc] initWithTitle:@""
                                                     message:NSLocalizedString(@"UNSUPPORTED_FEATURE_ERROR", @"")
                                                    delegate:nil
                                           cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                           otherButtonTitles:nil];
                      [notPermitted show];
                  }
                }];

    [alertController addAction:cancelAction];
    [alertController addAction:okAction];
    sendTextButton.hidden                = YES;
    self.searchController.searchBar.text = @"";

    [self presentViewController:alertController animated:YES completion:[UIUtil modalCompletionBlock]];
}

#pragma mark - SMS Composer Delegate

// called on completion of message screen
- (void)messageComposeViewController:(MFMessageComposeViewController *)controller
                 didFinishWithResult:(MessageComposeResult)result {
    switch (result) {
        case MessageComposeResultCancelled:
            break;
        case MessageComposeResultFailed: {
            UIAlertView *warningAlert =
                [[UIAlertView alloc] initWithTitle:@""
                                           message:NSLocalizedString(@"SEND_SMS_INVITE_FAILURE", @"")
                                          delegate:nil
                                 cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                 otherButtonTitles:nil];
            [warningAlert show];
            break;
        }
        case MessageComposeResultSent: {
            [self dismissViewControllerAnimated:NO
                                     completion:^{
                                       DDLogDebug(@"view controller dismissed");
                                     }];
            UIAlertView *successAlert =
                [[UIAlertView alloc] initWithTitle:@""
                                           message:NSLocalizedString(@"SEND_SMS_INVITE_SUCCESS", @"")
                                          delegate:nil
                                 cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                 otherButtonTitles:nil];
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
    ContactTableViewCell *cell =
        (ContactTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"ContactTableViewCell"];

    if (cell == nil) {
        cell = [[ContactTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:@"ContactTableViewCell"];
    }

    cell.shouldShowContactButtons = NO;

    [cell configureWithContact:[self contactForIndexPath:indexPath]];

    tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 52.0f;
}

#pragma mark - Table View delegate
- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    Contact *person = [self contactForIndexPath:indexPath];
    return person.isTextSecureContact ? indexPath : nil;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *identifier = [[[self contactForIndexPath:indexPath] textSecureIdentifiers] firstObject];

    [self dismissViewControllerAnimated:YES
                             completion:^() {
                               [Environment messageIdentifier:identifier withCompose:YES];
                             }];
}


- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    ContactTableViewCell *cell = (ContactTableViewCell *)[tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType         = UITableViewCellAccessoryNone;
}

- (Contact *)contactForIndexPath:(NSIndexPath *)indexPath {
    Contact *contact = nil;

    if (self.searchController.active) {
        contact = [searchResults objectAtIndex:(NSUInteger)indexPath.row];
    } else {
        contact = [contacts objectAtIndex:(NSUInteger)indexPath.row];
    }

    return contact;
}

#pragma mark Refresh controls

- (void)updateAfterRefreshTry {
    [self.refreshControl endRefreshing];

    [self showLoadingBackgroundView:NO];
    if ([contacts count] == 0) {
        [self showEmptyBackgroundView:YES];
    } else {
        [self showEmptyBackgroundView:NO];
    }
}

- (void)refreshContacts {
    [[ContactsUpdater sharedUpdater]
        updateSignalContactIntersectionWithABContacts:[Environment getCurrent].contactsManager.allContacts
        success:^{
          contacts = [[Environment getCurrent] contactsManager].signalContacts;
          dispatch_async(dispatch_get_main_queue(), ^{
            [self updateSearchResultsForSearchController:self.searchController];
            [self.tableView reloadData];
            [self updateAfterRefreshTry];
          });
        }
        failure:^(NSError *error) {
          UIAlertView *alert = [[UIAlertView alloc] initWithTitle:TIMEOUT
                                                          message:TIMEOUT_CONTACTS_DETAIL
                                                         delegate:nil
                                                cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                                otherButtonTitles:nil];
          [alert show];
          dispatch_async(dispatch_get_main_queue(), ^{
            [self updateAfterRefreshTry];
          });
        }];

    if ([contacts count] == 0) {
        [self showLoadingBackgroundView:YES];
    }
}

#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    self.searchController.active = NO;
}

- (IBAction)closeAction:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (CGFloat)contentWidth {
    return [UIScreen mainScreen].bounds.size.width - 2 * [self marginSize];
}

- (CGFloat)marginSize {
    return 20;
}

@end
