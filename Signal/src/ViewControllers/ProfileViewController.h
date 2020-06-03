//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class ConversationListViewController;
@class SDSKeyValueStore;

typedef NS_ENUM(NSInteger, ProfileViewMode) {
    ProfileViewMode_AppSettings = 0,
    ProfileViewMode_Registration,
    ProfileViewMode_ExperienceUpgrade,
};

@interface ProfileViewController : OWSViewController

+ (SDSKeyValueStore *)keyValueStore;

- (instancetype)initWithMode:(ProfileViewMode)profileViewMode
           completionHandler:(void (^)(ProfileViewController *))completionHandler;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (BOOL)shouldDisplayProfileViewOnLaunch;

@end

NS_ASSUME_NONNULL_END
