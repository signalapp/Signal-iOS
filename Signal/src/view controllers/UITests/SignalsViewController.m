//
//  SignalsViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "AppDelegate.h"
#import "DemoDataFactory.h"
#import "TableViewCell.h"

#import "MessagesViewController.h"
#import "SignalsViewController.h"


#define CELL_HEIGHT 71.0f
#define HEADER_HEIGHT 44.0f


static NSString *const kCellNibName = @"TableViewCell";
static NSString *const kSegueIndentifier = @"showSegue";


@interface SignalsViewController () {
    NSArray * _dataArray;
    NSUInteger numberOfCells;
    
}
@property (strong, nonatomic) DemoDataModel *demoData;

@end

@implementation SignalsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _dataArray = [DemoDataFactory data];
    numberOfCells = _dataArray.count;
    [self tableViewSetUp];
    
    _socket = [[Socket alloc]init];
    
    [self initializeObserver];
    
    _socket.status = kSocketStatusOpen;
    
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

-(void)dealloc
{
    [_socket removeObserver:self forKeyPath:@"status"];
}

-(void)tableViewSetUp
{
    self._tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

#pragma mark - Socket Status Notifications

-(void)initializeObserver
{
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(socketDidOpen) name:SocketOpenedNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(socketDidClose) name:SocketClosedNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(socketIsConnecting) name:SocketConnectingNotification object:nil];
}

-(void)socketDidOpen
{
    _socketStatusView.progressTintColor = [UIColor greenColor];
}

-(void)socketDidClose
{
    _socketStatusView.progressTintColor = [UIColor redColor];

}

-(void)socketIsConnecting
{
    _socketStatusView.progressTintColor = [UIColor yellowColor];

}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)numberOfCells;
}

 - (TableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
     return [self inboxFeedCellForIndexPath:indexPath];
 }

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return CELL_HEIGHT;
}

-(TableViewCell*)inboxFeedCellForIndexPath:(NSIndexPath *)indexPath {
    
    TableViewCell *cell = [self._tableView dequeueReusableCellWithIdentifier:kCellNibName];
    
    
    if (!cell) {
        cell = [[TableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                    reuseIdentifier:kCellNibName];
        cell.delegate = self;
    }
    
    DemoDataModel *recent = _dataArray[(NSUInteger)indexPath.row];
    [cell configureWithTestMessage:recent];
    [cell configureForState:_segmentedControl.selectedSegmentIndex == 0 ? kInboxState : kArchiveState];
    return cell;

}


#pragma mark - HomeFeedTableViewCellDelegate

- (void)tableViewCellTappedDelete:(TableViewCell *)cell {
    NSLog(@"Delete");
}

- (void)tableViewCellTappedArchive:(TableViewCell *)cell {
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
        MessagesViewController * vc = [segue destinationViewController];
        NSIndexPath *selectedIndexPath = [self._tableView indexPathForSelectedRow];
        if (selectedIndexPath) {
            vc._senderTitleString =  ((DemoDataModel*)_dataArray[(NSUInteger)selectedIndexPath.row])._sender;
        } else if (_contactFromCompose) {
            vc._senderTitleString = _contactFromCompose.fullName;
        } else if (_groupFromCompose) {
            vc._senderTitleString = _groupFromCompose.groupName;
        }

    }
}

#pragma mark - IBAction

-(IBAction)segmentDidChange:(id)sender
{
    switch (_segmentedControl.selectedSegmentIndex) {
        case 0:
            numberOfCells=5;
            [self._tableView reloadData];
            break;
            
        case 1:
            numberOfCells=3;
            [self._tableView reloadData];
            break;
            
    }
}
@end
