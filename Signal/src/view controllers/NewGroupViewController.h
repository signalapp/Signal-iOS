//
//  NewGroupViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface NewGroupViewController : UIViewController <UITableViewDelegate, UITabBarDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@property(nonatomic, strong) IBOutlet UITableView* tableView;

@property(nonatomic, strong) IBOutlet UITextField* nameGroupTextField;
@property(nonatomic, strong) IBOutlet UIButton* groupImageButton;
@property(nonatomic, strong) IBOutlet UIView* tapToDismissView;

@end
