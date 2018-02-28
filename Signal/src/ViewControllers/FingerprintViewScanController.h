//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@interface FingerprintViewScanController : OWSViewController

- (void)configureWithRecipientId:(NSString *)recipientId NS_SWIFT_NAME(configure(recipientId:));

+ (void)showVerificationSucceeded:(UIViewController *)viewController
                      identityKey:(NSData *)identityKey
                      recipientId:(NSString *)recipientId
                      contactName:(NSString *)contactName
                              tag:(NSString *)tag;

+ (void)showVerificationFailedWithError:(NSError *)error
                         viewController:(UIViewController *)viewController
                             retryBlock:(void (^_Nullable)(void))retryBlock
                            cancelBlock:(void (^_Nonnull)(void))cancelBlock
                                    tag:(NSString *)tag;

@end

NS_ASSUME_NONNULL_END
