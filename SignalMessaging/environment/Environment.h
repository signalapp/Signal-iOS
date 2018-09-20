//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/SSKEnvironment.h>

@class OWSContactsManager;
@class OWSPreferences;

/**
 *
 * Environment is a data and data accessor class.
 * It handles application-level component wiring in order to support mocks for testing.
 * It also handles network configuration for testing/deployment server configurations.
 *
 **/
// TODO: Rename to AppEnvironment?
@interface Environment : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithPreferences:(OWSPreferences *)preferences;

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSPreferences *preferences;

@property (class, nonatomic) Environment *shared;

#ifdef DEBUG
// Should only be called by tests.
+ (void)clearSharedForTests;
#endif

@end
