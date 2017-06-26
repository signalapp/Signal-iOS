//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationSettingsViewDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@interface NewGroupViewController : UIViewController

@property (nonatomic, weak) id<OWSConversationSettingsViewDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
