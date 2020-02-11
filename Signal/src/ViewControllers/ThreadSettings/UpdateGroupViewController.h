//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationSettingsViewDelegate.h"
#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class TSGroupThread;

typedef NS_ENUM(NSUInteger, UpdateGroupMode) {
    UpdateGroupMode_Default = 0,
    UpdateGroupMode_EditGroupName,
    UpdateGroupMode_EditGroupAvatar,
};

@interface UpdateGroupViewController : OWSViewController

@property (nonatomic, weak) id<OWSConversationSettingsViewDelegate> conversationSettingsViewDelegate;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
- (nullable instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

- (instancetype)initWithGroupThread:(TSGroupThread *)groupThread mode:(UpdateGroupMode)mode NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
