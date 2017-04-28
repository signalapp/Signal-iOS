//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationSettingsViewDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@class TSGroupThread;

@interface UpdateGroupViewController : UIViewController

@property (nonatomic, weak) id<OWSConversationSettingsViewDelegate> delegate;

// This property _must_ be set before the view is presented.
@property (nonatomic) TSGroupThread *thread;

@property (nonatomic) BOOL shouldEditGroupNameOnAppear;
@property (nonatomic) BOOL shouldEditAvatarOnAppear;

@end

NS_ASSUME_NONNULL_END
