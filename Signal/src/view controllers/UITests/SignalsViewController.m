//
//  SignalsViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "SignalsViewController.h"
#import "DemoDataFactory.h"
#import "TableViewCell.h"
#import "MessagesViewController.h"


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
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

-(void)tableViewSetUp
{
    self._tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
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

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
    
    if ([segue.identifier isEqualToString:kSegueIndentifier])
    {
        MessagesViewController * vc = [segue destinationViewController];
        NSIndexPath *selectedIndexPath = [self._tableView indexPathForSelectedRow];
        vc._senderTitleString =  ((DemoDataModel*)_dataArray[(NSUInteger)selectedIndexPath.row])._sender;
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
