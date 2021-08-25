//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class VNBarcodeObservation;
@class VNDetectBarcodesRequest;

@interface ScanQRCode : NSObject

+ (void)configureVNDetectBarcodesRequest:(VNDetectBarcodesRequest *)request;

+ (BOOL)isVNBarcodeObservationQR:(VNBarcodeObservation *)barcode;

@end

NS_ASSUME_NONNULL_END
