//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "ScanQRCodeViewController.h"
#import <Vision/Vision.h>

NS_ASSUME_NONNULL_BEGIN

@implementation ScanQRCode

+ (void)configureVNDetectBarcodesRequest:(VNDetectBarcodesRequest *)request
{
    // These two methods work around a crash when scanning.  I'm not sure
    // if this issue represents some kind of bug in Xcode 13 or in how
    // the Vision deprecated their constants.
    //
    // The Vision framework has deprecated their old symbology constants
    // and replaced them with new similar constants. 
    //
    // The old symbol:
    //
    // * Is/was .QR in Swift
    // * Was VNBarcodeSymbologyQR in Obj-C in Xcode 12/iOS SDK 14.
    // * Is now VNBarcodeSymbologyQR_SwiftDeprecated in Obj-C.
    //
    // The new symbol:
    //
    // * Is .qr in Swift in Xcode 13/iOS SDK 15.
    // * Was not available in Obj-C in Xcode 12/iOS SDK 14.
    // * Is now VNBarcodeSymbologyQR in Obj-C in Xcode 13/iOS SDK 15.
    //
    // If we use the old symbol in Swift, the app will crash when scanning
    // if built using Xcode 13/iOS SDK 15.
    //
    // We cannot use the new symbol in Swift, because we still use
    // both Xcode 12 and 13 to cut builds.
    //
    // It's not convenient to work around this problem in Swift.
    //
    // * The new symbol .qr is not available in iOS SDK 14 and will
    //   fail to compile under Xcode 12.
    // * #available(iOS 15, *) tests the iOS version of the device,
    //   not the iOS SDK version.
    // * There's no way to explicitly do conditional compilation
    //   around SDK version in SWK.  You _can_ conditionally compile
    //   by consulting Swift or compiler version, but this seems
    //   brittle.
    //
    // Therefore we solve this problem by using this symbol in Obj-C.
    // In Obj-c the _symbol names_ changed.  So:
    //
    // * Using Xcode 12, VNBarcodeSymbologyQR refers to the old symbol.
    //   This works at runtime on devices running iOS 15 and earlier.
    // * Using Xcode 13, VNBarcodeSymbologyQR refers to the new symbol.
    //   This works at runtime on devices running iOS 15 and earlier.
    request.symbologies = @[ VNBarcodeSymbologyQR ];
}

+ (BOOL)isVNBarcodeObservationQR:(VNBarcodeObservation *)barcode
{
    return barcode.symbology == VNBarcodeSymbologyQR;
}
    
@end

NS_ASSUME_NONNULL_END
