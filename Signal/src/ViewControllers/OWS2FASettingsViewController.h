//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, Enable2FAMode) {
    OWS2FASettingsMode_Status = 0,
    OWS2FASettingsMode_SelectPIN,
    OWS2FASettingsMode_ConfirmPIN,
};

@interface OWS2FASettingsViewController : OWSViewController

@property (nonatomic) Enable2FAMode mode;

// When confirming the PIN, this is the PIN that was
// initially entered by the user.
@property (nonatomic, nullable) NSString *candidatePin;

@end

NS_ASSUME_NONNULL_END
