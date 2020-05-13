//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationSettingsViewDelegate.h"
#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class TSGroupThread;

typedef NS_ENUM(NSUInteger, UpdateGroupMode) {
    UpdateGroupModeDefault = 0,
    UpdateGroupModeEditGroupName,
    UpdateGroupModeEditGroupAvatar,
};

// GroupsV2 TODO: Remove this VC.
@interface UpdateGroupViewController : OWSViewController

@property (nonatomic, weak) id<OWSConversationSettingsViewDelegate> conversationSettingsViewDelegate;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithGroupThread:(TSGroupThread *)groupThread mode:(UpdateGroupMode)mode NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
