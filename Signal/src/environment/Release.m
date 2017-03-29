//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "Release.h"
#import "DiscardingLog.h"
#import "NotificationsManager.h"
#import "OWSContactsManager.h"
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/TSNetworkManager.h>

@implementation Release

+ (Environment *)releaseEnvironmentWithLogging:(id<Logging>)logging {
    TSNetworkManager *networkManager = [TSNetworkManager sharedManager];
    OWSContactsManager *contactsManager = [OWSContactsManager new];
    ContactsUpdater *contactsUpdater = [ContactsUpdater sharedUpdater];
    OWSMessageSender *messageSender = [[OWSMessageSender alloc] initWithNetworkManager:networkManager
                                                                        storageManager:[TSStorageManager sharedManager]
                                                                       contactsManager:contactsManager
                                                                       contactsUpdater:contactsUpdater];

    return [[Environment alloc] initWithLogging:logging
                                contactsManager:contactsManager
                                contactsUpdater:contactsUpdater
                                 networkManager:networkManager
                                  messageSender:messageSender];
}

+ (Environment *)stagingEnvironmentWithLogging:(id<Logging>)logging {
    TSNetworkManager *networkManager = [TSNetworkManager sharedManager];
    OWSContactsManager *contactsManager = [OWSContactsManager new];
    ContactsUpdater *contactsUpdater = [ContactsUpdater sharedUpdater];
    OWSMessageSender *messageSender = [[OWSMessageSender alloc] initWithNetworkManager:networkManager
                                                                        storageManager:[TSStorageManager sharedManager]
                                                                       contactsManager:contactsManager
                                                                       contactsUpdater:contactsUpdater];

    return [[Environment alloc] initWithLogging:logging
                                contactsManager:contactsManager
                                contactsUpdater:contactsUpdater
                                 networkManager:networkManager
                                  messageSender:messageSender];
}

+ (Environment *)unitTestEnvironment:(NSArray *)testingAndLegacyOptions {
    TSNetworkManager *networkManager = [TSNetworkManager sharedManager];
    OWSContactsManager *contactsManager = [OWSContactsManager new];
    ContactsUpdater *contactsUpdater = [ContactsUpdater sharedUpdater];
    OWSMessageSender *messageSender = [[OWSMessageSender alloc] initWithNetworkManager:networkManager
                                                                        storageManager:[TSStorageManager sharedManager]
                                                                       contactsManager:contactsManager
                                                                       contactsUpdater:contactsUpdater];

    return [[Environment alloc] initWithLogging:[DiscardingLog discardingLog]
                                contactsManager:nil
                                contactsUpdater:contactsUpdater
                                 networkManager:networkManager
                                  messageSender:messageSender];
}

@end
