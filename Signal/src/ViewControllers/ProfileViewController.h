//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ProfileViewMode) {
    ProfileViewMode_AppSettings = 0,
    ProfileViewMode_Registration,
    ProfileViewMode_UpgradeOrNag,
};

@interface ProfileViewController : OWSTableViewController

@property (nonatomic) ProfileViewMode profileViewMode;

@end

NS_ASSUME_NONNULL_END
