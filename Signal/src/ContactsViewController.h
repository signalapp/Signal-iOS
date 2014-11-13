//
//  ContactsViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 29/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ContactsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property(nonatomic,strong) IBOutlet UISearchBar* searchBar;
@property(nonatomic,strong) IBOutlet UITableView* tableView;
@property(nonatomic,strong) IBOutlet UILabel* phoneNumberLabel;
@end
