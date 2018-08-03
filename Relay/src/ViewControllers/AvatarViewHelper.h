//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AvatarViewHelper;
@class OWSContactsManager;
@class SignalAccount;
@class TSThread;

@protocol AvatarViewHelperDelegate <NSObject>

- (NSString *)avatarActionSheetTitle;

- (void)avatarDidChange:(UIImage *)image;

- (UIViewController *)fromViewController;

- (BOOL)hasClearAvatarAction;

@optional

- (NSString *)clearAvatarActionLabel;

- (void)clearAvatar;

@end

#pragma mark -

typedef void (^AvatarViewSuccessBlock)(void);

@interface AvatarViewHelper : NSObject

@property (nonatomic, weak) id<AvatarViewHelperDelegate> delegate;

- (void)showChangeAvatarUI;

@end

NS_ASSUME_NONNULL_END
