//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSQRCodeScanningViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSFingerprint;
@class OWSConversationSettingsTableViewController;

@interface FingerprintViewController : UIViewController <OWSQRScannerDelegate>

@property (nullable) OWSConversationSettingsTableViewController *dismissDelegate;

- (void)configureWithFingerprint:(OWSFingerprint *)fingerprint
                     contactName:(NSString *)contactName NS_SWIFT_NAME(configure(fingerprint:contactName:));

- (void)controller:(OWSQRCodeScanningViewController *)controller didDetectQRCodeWithData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
