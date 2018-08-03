//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface RegistrationUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (void)showReregistrationUIFromViewController:(UIViewController *)fromViewController;

@end

NS_ASSUME_NONNULL_END
