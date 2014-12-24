//
//  ShowGroupMembersViewController.h
//  Signal
//
//  Created by Christine Corbett on 12/19/14
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "TSGroupThread.h"
#import "GroupModel.h"

@interface ShowGroupMembersViewController : UIViewController <UITableViewDelegate, UITabBarDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate>

- (void)configWithThread:(TSGroupThread*)thread;
@property(nonatomic, strong) IBOutlet UITableView* tableView;

@end
