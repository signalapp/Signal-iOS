//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "TSGroupModel.h"
#import "TSGroupThread.h"

@interface NewGroupViewController : UIViewController <UITableViewDelegate,
                                                      UITabBarDelegate,
                                                      UIImagePickerControllerDelegate,
                                                      UINavigationControllerDelegate,
                                                      UITextFieldDelegate>

- (void)configWithThread:(TSGroupThread *)thread;

@property (nonatomic) IBOutlet UITableView *tableView;
@property (nonatomic) IBOutlet UITextField *nameGroupTextField;
@property (nonatomic) IBOutlet UIButton *groupImageButton;
@property (nonatomic) IBOutlet UIView *tapToDismissView;
@property (nonatomic) IBOutlet UILabel *addPeopleLabel;
@property (nonatomic) UIImage *groupImage;
@property (nonatomic) TSGroupModel *groupModel;

@property (nonatomic) BOOL shouldEditGroupNameOnAppear;
@property (nonatomic) BOOL shouldEditAvatarOnAppear;

@end
