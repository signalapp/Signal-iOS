//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalUI/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

@interface FingerprintViewScanController : OWSViewController

- (void)configureWithRecipientAddress:(SignalServiceAddress *)address NS_SWIFT_NAME(configure(recipientAddress:));

+ (void)showVerificationSucceeded:(UIViewController *)viewController
                      identityKey:(NSData *)identityKey
                 recipientAddress:(SignalServiceAddress *)address
                      contactName:(NSString *)contactName
                              tag:(NSString *)tag;

+ (void)showVerificationFailedWithError:(NSError *)error
                         viewController:(UIViewController *)viewController
                             retryBlock:(void (^_Nullable)(void))retryBlock
                            cancelBlock:(void (^_Nonnull)(void))cancelBlock
                                    tag:(NSString *)tag;

@end

NS_ASSUME_NONNULL_END
