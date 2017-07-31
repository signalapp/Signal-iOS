//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalAccount;
@class AvatarViewHelper;
@class OWSContactsManager;
@class TSThread;

@protocol AvatarViewHelperDelegate <NSObject>

- (void)avatarDidChange:(UIImage *)image;

- (UIViewController *)fromViewController;

@end

#pragma mark -

typedef void (^AvatarViewSuccessBlock)();

@interface AvatarViewHelper : NSObject

@property (nonatomic, weak) id<AvatarViewHelperDelegate> delegate;

- (void)showChangeAvatarUI;

@end

NS_ASSUME_NONNULL_END
