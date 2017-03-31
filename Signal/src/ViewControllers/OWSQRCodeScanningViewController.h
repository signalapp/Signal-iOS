//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <ZXingObjC/ZXingObjC.h>

@class OWSQRCodeScanningViewController;

@protocol OWSQRScannerDelegate

@optional

- (void)controller:(OWSQRCodeScanningViewController *)controller didDetectQRCodeWithString:(NSString *)string;
- (void)controller:(OWSQRCodeScanningViewController *)controller didDetectQRCodeWithData:(NSData *)data;

@end

@interface OWSQRCodeScanningViewController
    : UIViewController <AVCaptureMetadataOutputObjectsDelegate, ZXCaptureDelegate>

@property (nonatomic, weak) UIViewController<OWSQRScannerDelegate> *scanDelegate;
- (void)startCapture;

@end
