//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "Release.h"
#import "Environment.h"
#import "NotificationsManager.h"
#import "OWSContactsManager.h"
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/TSNetworkManager.h>

@implementation Release

+ (Environment *)releaseEnvironment
{
    // Order matters here.
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    TSNetworkManager *networkManager = [TSNetworkManager sharedManager];
    OWSContactsManager *contactsManager = [OWSContactsManager new];
    ContactsUpdater *contactsUpdater = [ContactsUpdater sharedUpdater];
    OWSMessageSender *messageSender = [[OWSMessageSender alloc] initWithNetworkManager:networkManager
                                                                        storageManager:storageManager
                                                                       contactsManager:contactsManager
                                                                       contactsUpdater:contactsUpdater];

    return [[Environment alloc] initWithContactsManager:contactsManager
                                        contactsUpdater:contactsUpdater
                                         networkManager:networkManager
                                          messageSender:messageSender];
}

// TODELETE
+ (Environment *)stagingEnvironment
{
    // Order matters here.
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    TSNetworkManager *networkManager = [TSNetworkManager sharedManager];
    OWSContactsManager *contactsManager = [OWSContactsManager new];
    ContactsUpdater *contactsUpdater = [ContactsUpdater sharedUpdater];
    OWSMessageSender *messageSender = [[OWSMessageSender alloc] initWithNetworkManager:networkManager
                                                                        storageManager:storageManager
                                                                       contactsManager:contactsManager
                                                                       contactsUpdater:contactsUpdater];

    return [[Environment alloc] initWithContactsManager:contactsManager
                                        contactsUpdater:contactsUpdater
                                         networkManager:networkManager
                                          messageSender:messageSender];
}

// TODELETE
+ (Environment *)unitTestEnvironment:(NSArray *)testingAndLegacyOptions
{
    TSNetworkManager *networkManager = [TSNetworkManager sharedManager];
    OWSContactsManager *contactsManager = [OWSContactsManager new];
    ContactsUpdater *contactsUpdater = [ContactsUpdater sharedUpdater];
    OWSMessageSender *messageSender = [[OWSMessageSender alloc] initWithNetworkManager:networkManager
                                                                        storageManager:[TSStorageManager sharedManager]
                                                                       contactsManager:contactsManager
                                                                       contactsUpdater:contactsUpdater];

    return [[Environment alloc] initWithContactsManager:nil
                                        contactsUpdater:contactsUpdater
                                         networkManager:networkManager
                                          messageSender:messageSender];
}

@end
