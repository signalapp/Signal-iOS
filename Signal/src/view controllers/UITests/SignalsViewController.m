//
//  SignalsViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "UIUtil.h"
#import "DemoDataFactory.h"
#import "InboxTableViewCell.h"

#import "MessagesViewController.h"
#import "SignalsViewController.h"
#import "TSStorageManager.h"
#import "TSDatabaseView.h"
#import "TSSocketManager.h"
#import "TSContactThread.h"

#import <YapDatabase/YapDatabaseViewChange.h>
#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseViewMappings.h"
#import "YapDatabaseViewConnection.h"
#import "YapDatabaseFullTextSearch.h"
#import "YapDatabase.h"

#define CELL_HEIGHT   71.0f
#define HEADER_HEIGHT 44.0f


static NSString *const inboxTableViewCell = @"inBoxTableViewCell";
static NSString *const kSegueIndentifier  = @"showSegue";


@interface SignalsViewController () {
    NSArray * _dataArray;
    NSUInteger numberOfCells;
    
}
@property (strong, nonatomic) UILabel * emptyViewLabel;
@property (strong, nonatomic) DemoDataModel *demoData;
@property (nonatomic, strong) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic, strong) YapDatabaseViewMappings *threadMappings;

@end

@implementation SignalsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self tableViewSetUp];
    
    [self.uiDatabaseConnection beginLongLivedReadTransaction];
    
    self.threadMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[TSThreadGroup]
                                                                     view:TSThreadDatabaseViewExtensionName];
    
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
        [self.threadMappings updateWithTransaction:transaction];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:TSUIDatabaseConnectionDidUpdateNotification
                                               object:nil];
    
    [TSSocketManager becomeActive];
    
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if ([self.threadMappings numberOfItemsInAllGroups]==0)
    {
        CGRect r = CGRectMake(0, 60, 300, 70);
        _emptyViewLabel = [[UILabel alloc]initWithFrame:r];
        _emptyViewLabel.text = @"You have no messages yet.";
        _emptyViewLabel.textColor = [UIColor grayColor];
        _emptyViewLabel.font = [UIFont ows_thinFontWithSize:14.0f];
        _emptyViewLabel.textAlignment = NSTextAlignmentCenter;
        self.tableView.tableHeaderView = _emptyViewLabel;
    } else {
        _emptyViewLabel = nil;
        self.tableView.tableHeaderView = nil;
    }
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}


-(void)tableViewSetUp
{
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)[self.threadMappings numberOfSections];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self.threadMappings numberOfItemsInSection:(NSUInteger)section];
}

- (InboxTableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    
    InboxTableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:inboxTableViewCell];
    TSThread *thread = [self threadForIndexPath:indexPath];
    
    if (!cell) {
        cell = [[InboxTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                         reuseIdentifier:inboxTableViewCell];
        cell.delegate = self;
    }
    
    [cell configureWithThread:thread];
    [cell configureForState:_segmentedControl.selectedSegmentIndex == 0 ? kInboxState : kArchiveState];
    
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

#pragma mark - HomeFeedTableViewCellDelegate

- (void)tableViewCellTappedDelete:(InboxTableViewCell*)cell {
    NSLog(@"Delete");
}

- (void)tableViewCellTappedArchive:(InboxTableViewCell*)cell {
    NSLog(@"Archive");
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self performSegueWithIdentifier:kSegueIndentifier sender:self];
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
}



#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    
    if ([segue.identifier isEqualToString:kSegueIndentifier])
    {
        MessagesViewController * vc    = [segue destinationViewController];
        NSIndexPath *selectedIndexPath = [self.tableView indexPathForSelectedRow];
        vc.thread                      = [self threadForIndexPath:selectedIndexPath];
        
        if (!vc.thread) {
            [TSStorageManager.sharedManager.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                vc.thread = [TSContactThread threadWithContactId:[self.contactFromCompose.userTextPhoneNumbers firstObject] transaction:transaction];
                NSLog(@"Thread:%@", vc.thread);
            }];
        }
        
    }
}

#pragma mark - IBAction

-(IBAction)segmentDidChange:(id)sender
{
    switch (_segmentedControl.selectedSegmentIndex) {
        case 0:
            numberOfCells=5;
            [self.tableView reloadData];
            break;
            
        case 1:
            numberOfCells=3;
            [self.tableView reloadData];
            break;
            
    }
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
    NSArray *notifications = notification.userInfo[@"notifications"];
    
    NSArray *sectionChanges = nil;
    NSArray *rowChanges = nil;
    
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
                break;
            }
            case YapDatabaseViewChangeInsert :
            {
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
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
}
@end
