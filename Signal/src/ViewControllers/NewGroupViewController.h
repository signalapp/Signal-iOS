//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationSettingsViewDelegate.h"
#import "OWSViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface NewGroupViewController : OWSViewController

@property (nonatomic, weak) id<OWSConversationSettingsViewDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
