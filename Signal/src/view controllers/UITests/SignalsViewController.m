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

#define CELL_NIB_NAME @"TableViewCell"
#define CELL_HEIGHT 76.0f

#define SEGUE_IDENTIFIER @"showSegue"

@interface SignalsViewController () {
    NSArray * _dataArray;
}
@property (strong, nonatomic) DemoDataModel *demoData;

@end

@implementation SignalsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    _dataArray = [DemoDataFactory data];
    [self tableViewSetUp];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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
    return 5;
}


 - (TableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
     TableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CELL_NIB_NAME];
     if (cell == nil) {
         NSArray *topLevelObjects = [[NSBundle mainBundle] loadNibNamed:CELL_NIB_NAME owner:self options:nil];
         cell = [topLevelObjects objectAtIndex:0];
     }
     
     
     cell._senderLabel.text = ((DemoDataModel*)_dataArray[(NSUInteger)indexPath.row])._sender;
     cell._snippetLabel.text = ((DemoDataModel*)_dataArray[(NSUInteger)indexPath.row])._snippet;
     cell._timeLabel.text = @"21:58";
     
 return cell;
 }

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return CELL_HEIGHT;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self performSegueWithIdentifier:SEGUE_IDENTIFIER sender:self];
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

}



#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
    
    if ([segue.identifier isEqualToString:SEGUE_IDENTIFIER])
    {
        MessagesViewController * vc = [segue destinationViewController];
        NSIndexPath *selectedIndexPath = [self._tableView indexPathForSelectedRow];
        vc._senderTitleString =  ((DemoDataModel*)_dataArray[(NSUInteger)selectedIndexPath.row])._sender;
    }
}


@end
