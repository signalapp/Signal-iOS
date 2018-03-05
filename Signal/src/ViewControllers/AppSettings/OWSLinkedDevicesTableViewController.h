//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface OWSLinkedDevicesTableViewController : UITableViewController <UITableViewDataSource, UITableViewDelegate>

/**
 * This is used to show the user there is a device provisioning in-progress.
 */
- (void)expectMoreDevices;

@end
