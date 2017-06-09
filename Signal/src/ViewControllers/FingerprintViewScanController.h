//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface FingerprintViewScanController : UIViewController

- (void)configureWithRecipientId:(NSString *)recipientId NS_SWIFT_NAME(configure(recipientId:));

+ (void)showVerificationSucceeded:(UIViewController *)viewController
                      identityKey:(NSData *)identityKey
                      recipientId:(NSString *)recipientId
                      contactName:(NSString *)contactName
                              tag:(NSString *)tag;

+ (void)showVerificationFailedWithError:(NSError *)error
                         viewController:(UIViewController *)viewController
                             retryBlock:(void (^_Nullable)())retryBlock
                            cancelBlock:(void (^_Nonnull)())cancelBlock
                                    tag:(NSString *)tag;

@end

NS_ASSUME_NONNULL_END
