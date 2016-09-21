//
//  FingerprintViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 02/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "OWSQRCodeScanningViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class TSThread;
@class OWSFingerprint;

@interface FingerprintViewController : UIViewController <OWSQRScannerDelegate>

- (void)configureWithThread:(TSThread *)thread
                fingerprint:(OWSFingerprint *)fingerprint
                contactName:(NSString *)contactName;
- (void)controller:(OWSQRCodeScanningViewController *)controller didDetectQRCodeWithData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
