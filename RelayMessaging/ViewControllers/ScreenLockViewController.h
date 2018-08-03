//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

typedef NS_ENUM(NSUInteger, ScreenLockUIState) {
    ScreenLockUIStateNone,
    // Shown while app is inactive or background, if enabled.
    ScreenLockUIStateScreenProtection,
    // Shown while app is active, if enabled.
    ScreenLockUIStateScreenLock,
};

NSString *NSStringForScreenLockUIState(ScreenLockUIState value);

@protocol ScreenLockViewDelegate <NSObject>

- (void)unlockButtonWasTapped;

@end

#pragma mark -

@interface ScreenLockViewController : UIViewController

@property (nonatomic, weak) id<ScreenLockViewDelegate> delegate;

- (void)updateUIWithState:(ScreenLockUIState)uiState isLogoAtTop:(BOOL)isLogoAtTop animated:(BOOL)animated;

@end
