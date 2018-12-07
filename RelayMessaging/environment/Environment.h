//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSPreferences.h"
#import <RelayServiceKit/TSStorageHeaders.h>

/**
 *
 * Environment is a data and data accessor class.
 * It handles application-level component wiring in order to support mocks for testing.
 * It also handles network configuration for testing/deployment server configurations.
 *
 **/

extern NSString *const FLRelayWipeAndReturnToRegistrationNotification;

@class ContactsUpdater;
@class FLContactsManager;
@class OWSMessageSender;
@class OWSNavigationController;
@class TSNetworkManager;
@class TSThread;
@class ThreadManager;

@interface Environment : NSObject

- (instancetype)initWithContactsManager:(FLContactsManager *)contactsManager
                        contactsUpdater:(ContactsUpdater *)contactsUpdater
                         networkManager:(TSNetworkManager *)networkManager
                          messageSender:(OWSMessageSender *)messageSender;

@property (nonatomic, readonly) FLContactsManager *contactsManager;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) ThreadManager *threadManager;
@property (nonatomic, readonly) OWSPreferences *preferences;

+ (Environment *)current;
+ (void)setCurrent:(Environment *)environment;
// Should only be called by tests.
+ (void)clearCurrentForTests;

+ (OWSPreferences *)preferences;

@end
