//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "InboxTableViewCell.h"
#import "Contact.h"
#import "TSGroupModel.h"

@interface SignalsViewController
    : UIViewController <UITableViewDelegate, UITableViewDataSource, UIViewControllerPreviewingDelegate>

@property (nonatomic, retain) IBOutlet UITableView *tableView;
@property (nonatomic, strong) IBOutlet UILabel *emptyBoxLabel;
@property (nonatomic) BOOL newlyRegisteredUser;

- (void)presentThread:(TSThread *)thread keyboardOnViewAppearing:(BOOL)keyboardOnViewAppearing;
- (NSNumber *)updateInboxCountLabel;
- (void)composeNew;

@end
