//
//  SignalsViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "UIUtil.h"
#import "InboxTableViewCell.h"

#import "ContactsManager.h"
#import "Environment.h"
#import "MessagesViewController.h"
#import "SignalsViewController.h"
#import "InCallViewController.h"
#import "TSStorageManager.h"
#import "TSAccountManager.h"
#import "TSDatabaseView.h"
#import "TSSocketManager.h"
#import "TSContactThread.h"
#import "TSMessagesManager+sendMessages.h"
#import "UIImage+normalizeImage.h"

#import "NSDate+millisecondTimeStamp.h"

#import <YapDatabase/YapDatabaseViewChange.h>
#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseViewMappings.h"
#import "YapDatabaseViewConnection.h"
#import "YapDatabaseFullTextSearch.h"
#import "YapDatabase.h"

#define CELL_HEIGHT 72.0f
#define HEADER_HEIGHT 44.0f


static NSString *const inboxTableViewCell      = @"inBoxTableViewCell";
static NSString *const kSegueIndentifier = @"showSegue";
static NSString* const kCallSegue = @"2.0_6.0_Call_Segue";
static NSString* const kShowSignupFlowSegue = @"showSignupFlow";

@interface SignalsViewController ()
@property (nonatomic, strong) YapDatabaseConnection *editingDbConnection;
@property (nonatomic, strong) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic, strong) YapDatabaseViewMappings *threadMappings;
@property (nonatomic) CellState viewingThreadsIn;
@property (nonatomic) long inboxCount;

@end

@implementation SignalsViewController

- (void)awakeFromNib{
    [[Environment getCurrent] setSignalsViewController:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    [self tableViewSetUp];
    
    self.editingDbConnection = TSStorageManager.sharedManager.newDatabaseConnection;
    
    [self.uiDatabaseConnection beginLongLivedReadTransaction];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:TSUIDatabaseConnectionDidUpdateNotification
                                               object:nil];
    [self selectedInbox:self];
    
    [self updateInboxCountLabel];
    
    [[[Environment getCurrent] contactsManager].getObservableContacts watchLatestValue:^(id latestValue) {
        [self.tableView reloadData];
    } onThread:[NSThread mainThread] untilCancelled:nil];
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self  checkIfEmptyView];
}

- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    
    if (![TSAccountManager isRegistered]){
        [self performSegueWithIdentifier:kShowSignupFlowSegue sender:self];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}


-(void)tableViewSetUp
{
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}


#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)[self.threadMappings numberOfSections];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self.threadMappings numberOfItemsInSection:(NSUInteger)section];
}

- (InboxTableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    
    InboxTableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:inboxTableViewCell];
    TSThread *thread         = [self threadForIndexPath:indexPath];
    
    if (!cell) {
        cell = [[InboxTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                         reuseIdentifier:inboxTableViewCell];
        cell.delegate = self;
    }
    
    [cell configureWithThread:thread];
    [cell configureForState:self.viewingThreadsIn == kInboxState ? kInboxState : kArchiveState];
    
    return cell;
}

- (TSThread*)threadForIndexPath:(NSIndexPath*)indexPath {
    
    __block TSThread *thread = nil;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        thread = [[transaction extension:TSThreadDatabaseViewExtensionName] objectAtIndexPath:indexPath withMappings:self.threadMappings];
    }];
    
    return thread;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return CELL_HEIGHT;
}

#pragma mark Table Swipe to Delete

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    return;
}


- (NSArray *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // add the ability to delete the cell
    UITableViewRowAction *deleteAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDefault title:@"           " handler:^(UITableViewRowAction *action, NSIndexPath *swipedIndexPath){
        
        [self tableViewCellTappedDelete:swipedIndexPath];
    }];
    
    
    UIImage* buttonImage = [[UIImage imageNamed:@"cellBtnDelete"] resizedImageToSize:CGSizeMake(82.0f, 72.0f)];
    
    deleteAction.backgroundColor = [[UIColor alloc] initWithPatternImage:buttonImage];

    //deleteAction.backgroundColor = [UIColor ows_redColor];
    
    return @[deleteAction];

    return nil;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

#pragma mark - HomeFeedTableViewCellDelegate

- (void)tableViewCellTappedDelete:(NSIndexPath*)indexPath {
    //NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    TSThread    *thread    = [self threadForIndexPath:indexPath];
    if([thread isKindOfClass:[TSGroupThread class]]) {
        DDLogDebug(@"leaving the group");
        TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:thread messageBody:@"" attachments:[[NSMutableArray alloc] init]];
        message.groupMetaMessage = TSGroupMessageQuit;
        [[TSMessagesManager sharedManager] sendMessage:message inThread:thread];
    }
    [self.editingDbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [thread removeWithTransaction:transaction];
    }];
    _inboxCount -= (self.viewingThreadsIn == kArchiveState) ? 1 : 0;
    [self checkIfEmptyView];
}

- (void)tableViewCellTappedArchive:(InboxTableViewCell*)cell {
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    TSThread    *thread    = [self threadForIndexPath:indexPath];
    thread.archivalDate    = self.viewingThreadsIn == kInboxState ? [NSDate date] : nil ;
    
    [self.editingDbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [thread saveWithTransaction:transaction];
    }];
    [self checkIfEmptyView];
}


-(void) updateInboxCountLabel {
    _inboxCount = (self.viewingThreadsIn == kInboxState) ? (long)[self tableView:self.tableView numberOfRowsInSection:0] : _inboxCount;

    self.inboxCountLabel.text = [NSString stringWithFormat:@"%ld",_inboxCount];
    self.inboxCountLabel.hidden = (_inboxCount == 0);

}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath{
    [self performSegueWithIdentifier:kSegueIndentifier sender:self];
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    
    if ([segue.identifier isEqualToString:kSegueIndentifier]){
        MessagesViewController * vc    = [segue destinationViewController];
        NSIndexPath *selectedIndexPath = [self.tableView indexPathForSelectedRow];
        TSThread *thread               = [self threadForIndexPath:selectedIndexPath];
        
        if (self.contactIdentifierFromCompose){
            [vc setupWithTSIdentifier:self.contactIdentifierFromCompose];
            self.contactIdentifierFromCompose = nil;
        }
        else if (self.groupFromCompose) {
            [vc setupWithTSGroup:self.groupFromCompose];
            self.groupFromCompose = nil;
        }
        else if (thread) {
            [vc setupWithThread:thread];
        }
    }
    else if ([segue.identifier isEqualToString:kCallSegue]) {
        InCallViewController* vc = [segue destinationViewController];
        [vc configureWithLatestCall:_latestCall];
        _latestCall = nil;
    }
}

#pragma mark - IBAction

-(IBAction)selectedInbox:(id)sender {
    self.viewingThreadsIn = kInboxState;
    [self.inboxButton setSelected:YES];
    [self.archiveButton setSelected:NO];
    [self changeToGrouping:TSInboxGroup];
}

-(IBAction)selectedArchive:(id)sender {
    self.viewingThreadsIn = kArchiveState;
    [self.inboxButton setSelected:NO];
    [self.archiveButton setSelected:YES];
    [self changeToGrouping:TSArchiveGroup];
}

-(void) changeToGrouping:(NSString*)grouping {
    self.threadMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[grouping]
                                                                     view:TSThreadDatabaseViewExtensionName];
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
        [self.threadMappings updateWithTransaction:transaction];
    }];
    [self.tableView reloadData];
    [self checkIfEmptyView];

}

#pragma mark Database delegates

- (YapDatabaseConnection *)uiDatabaseConnection {
    NSAssert([NSThread isMainThread], @"Must access uiDatabaseConnection on main thread!");
    if (!_uiDatabaseConnection) {
        YapDatabase *database = TSStorageManager.sharedManager.database;
        _uiDatabaseConnection = [database newConnection];
        [_uiDatabaseConnection beginLongLivedReadTransaction];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yapDatabaseModified:)
                                                     name:YapDatabaseModifiedNotification
                                                   object:database];
    }
    return _uiDatabaseConnection;
}

- (void)yapDatabaseModified:(NSNotification *)notification {
    NSArray *notifications  = [self.uiDatabaseConnection beginLongLivedReadTransaction];
    NSArray *sectionChanges = nil;
    NSArray *rowChanges     = nil;

    [[self.uiDatabaseConnection ext:TSThreadDatabaseViewExtensionName] getSectionChanges:&sectionChanges
                                                                              rowChanges:&rowChanges
                                                                        forNotifications:notifications
                                                                            withMappings:self.threadMappings];
    
    if ([sectionChanges count] == 0 && [rowChanges count] == 0){
        return;
    }
    
    [self.tableView beginUpdates];
    
    for (YapDatabaseViewSectionChange *sectionChange in sectionChanges)
    {
        switch (sectionChange.type)
        {
            case YapDatabaseViewChangeDelete :
            {
                [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionChange.index]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeInsert :
            {
                [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionChange.index]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeUpdate:
            case YapDatabaseViewChangeMove:
                break;
        }
    }
    
    for (YapDatabaseViewRowChange *rowChange in rowChanges)
    {
        switch (rowChange.type)
        {
            case YapDatabaseViewChangeDelete :
            {
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                _inboxCount += (self.viewingThreadsIn == kArchiveState) ? 1 : 0;
                break;
            }
            case YapDatabaseViewChangeInsert :
            {
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                _inboxCount -= (self.viewingThreadsIn == kArchiveState) ? 1 : 0;
                break;
            }
            case YapDatabaseViewChangeMove :
            {
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeUpdate :
            {
                [self.tableView reloadRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationNone];
                break;
            }
        }
    }
    
    [self.tableView endUpdates];
    [self updateInboxCountLabel];
    [self checkIfEmptyView];
}


- (IBAction)unwindSettingsDone:(UIStoryboardSegue *)segue {
    
}

- (IBAction)unwindMessagesView:(UIStoryboardSegue *)segue {
    
}

- (void)checkIfEmptyView{
    [_tableView setHidden:NO];
    if (self.viewingThreadsIn == kInboxState && [self.threadMappings numberOfItemsInGroup:TSInboxGroup]==0) {
        _emptyBoxImage.image = [UIImage imageNamed:@"uiEmptyContact"];
        [self setEmptyBoxText];
        [_tableView setHidden:YES];
    }
    else if (self.viewingThreadsIn == kArchiveState && [self.threadMappings numberOfItemsInGroup:TSArchiveGroup]==0) {        
        _emptyBoxImage.image = [UIImage imageNamed:@"uiEmptyArchive"];
        [self setEmptyBoxText];
        [_tableView setHidden:YES];
    }
    
    
    
  
}

-(void) setEmptyBoxText {
    _emptyBoxLabel.textColor = [UIColor grayColor];
    _emptyBoxLabel.font = [UIFont ows_regularFontWithSize:18.f];
    _emptyBoxLabel.textAlignment = NSTextAlignmentCenter;
    _emptyBoxLabel.numberOfLines = 4;

    NSString* firstLine = @"";
    NSString* secondLine = @"";
    
    if(self.viewingThreadsIn == kInboxState) {
        // Check if this is the first launch
        firstLine =  @"No Messages :(";
        secondLine = @"Tap compose to send a message or invite a friend to Signal.";
    }
    else {
        firstLine = @"No archived messages.";
        secondLine = @"Swipe right on any message in your inbox and archive it here.";
    }
    NSMutableAttributedString *fullLabelString = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n%@",firstLine,secondLine]];
    
    [fullLabelString addAttribute:NSFontAttributeName value:[UIFont ows_boldFontWithSize:15.f] range:NSMakeRange(0,firstLine.length)];
    [fullLabelString addAttribute:NSFontAttributeName value:[UIFont ows_regularFontWithSize:14.f] range:NSMakeRange(firstLine.length + 1, secondLine.length)];
    [fullLabelString addAttribute:NSForegroundColorAttributeName value:[UIColor blackColor] range:NSMakeRange(0,firstLine.length)];
    [fullLabelString addAttribute:NSForegroundColorAttributeName value:[UIColor ows_darkGrayColor] range:NSMakeRange(firstLine.length + 1, secondLine.length)];
    _emptyBoxLabel.attributedText = fullLabelString;

    
}

@end
