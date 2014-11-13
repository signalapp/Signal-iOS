//
//  SignalsViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#include "TableViewCell.h"
#import <UIKit/UIKit.h>

@interface SignalsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, TableViewCellDelegate>

@property (nonatomic) Contact* contactFromCompose;
@property (nonatomic,strong) IBOutlet UITableView* _tableView;

@property (strong, nonatomic) IBOutlet UISegmentedControl * segmentedControl;

@end
