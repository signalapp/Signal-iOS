//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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
    static Environment *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Order matters here.
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        TSNetworkManager *networkManager = [TSNetworkManager sharedManager];
        OWSContactsManager *contactsManager = [OWSContactsManager new];
        ContactsUpdater *contactsUpdater = [ContactsUpdater sharedUpdater];
        OWSMessageSender *messageSender = [[OWSMessageSender alloc] initWithNetworkManager:networkManager
                                                                            storageManager:storageManager
                                                                           contactsManager:contactsManager
                                                                           contactsUpdater:contactsUpdater];

        instance = [[Environment alloc] initWithContactsManager:contactsManager
                                                contactsUpdater:contactsUpdater
                                                 networkManager:networkManager
                                                  messageSender:messageSender];
    });
    return instance;
}

@end
