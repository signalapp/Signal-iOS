//
//  SignalsViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SignalsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

@property(nonatomic,strong) IBOutlet UITableView* _tableView;

@end
