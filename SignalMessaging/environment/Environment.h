//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSStorageHeaders.h>

/**
 *
 * Environment is a data and data accessor class.
 * It handles application-level component wiring in order to support mocks for testing.
 * It also handles network configuration for testing/deployment server configurations.
 *
 **/

@class ContactsUpdater;
@class OWSContactsManager;
@class OWSMessageSender;
@class OWSNavigationController;
@class OWSPreferences;
@class TSGroupThread;
@class TSNetworkManager;
@class TSThread;

@interface Environment : NSObject

- (instancetype)initWithContactsManager:(OWSContactsManager *)contactsManager
                        contactsUpdater:(ContactsUpdater *)contactsUpdater
                         networkManager:(TSNetworkManager *)networkManager
                          messageSender:(OWSMessageSender *)messageSender;

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) OWSPreferences *preferences;

@property (class, nonatomic) Environment *shared;

// Should only be called by tests.
+ (void)clearSharedForTests;

@end
