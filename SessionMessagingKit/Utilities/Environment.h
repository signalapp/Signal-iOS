#import <Foundation/Foundation.h>

@class OWSAudioSession;
@class OWSPreferences;
@class OWSSounds;
@class OWSWindowManager;

@protocol OWSProximityMonitoringManager;

/**
 *
 * Environment is a data and data accessor class.
 * It handles application-level component wiring in order to support mocks for testing.
 * It also handles network configuration for testing/deployment server configurations.
 *
 **/
@interface Environment : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithAudioSession:(OWSAudioSession *)audioSession
                         preferences:(OWSPreferences *)preferences
          proximityMonitoringManager:(id<OWSProximityMonitoringManager>)proximityMonitoringManager
                              sounds:(OWSSounds *)sounds
                       windowManager:(OWSWindowManager *)windowManager;

@property (nonatomic, readonly) OWSAudioSession *audioSession;
@property (nonatomic, readonly) id<OWSProximityMonitoringManager> proximityMonitoringManager;
@property (nonatomic, readonly) OWSPreferences *preferences;
@property (nonatomic, readonly) OWSSounds *sounds;
@property (nonatomic, readonly) OWSWindowManager *windowManager;
// We don't want to cover the window when we request the photo library permission
@property (nonatomic, readwrite) BOOL isRequestingPermission;

@property (class, nonatomic) Environment *shared;

#ifdef DEBUG
// Should only be called by tests.
+ (void)clearSharedForTests;
#endif

@end
