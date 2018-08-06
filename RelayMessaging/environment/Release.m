//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Release.h"
#import "Environment.h"
#import "NotificationsManager.h"
#import "OWSContactsManager.h"
#import <RelayServiceKit/ContactsUpdater.h>
#import <RelayServiceKit/OWSMessageSender.h>
#import <RelayServiceKit/TSNetworkManager.h>

@implementation Release

+ (Environment *)releaseEnvironment
{
    static Environment *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Order matters here.
        OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
        TSNetworkManager *networkManager = [TSNetworkManager sharedManager];
        OWSContactsManager *contactsManager = [OWSContactsManager new];
        ContactsUpdater *contactsUpdater = [ContactsUpdater sharedUpdater];
        OWSMessageSender *messageSender = [[OWSMessageSender alloc] initWithNetworkManager:networkManager
                                                                            primaryStorage:primaryStorage
                                                                           contactsManager:contactsManager];

        instance = [[Environment alloc] initWithContactsManager:contactsManager
                                                contactsUpdater:contactsUpdater
                                                 networkManager:networkManager
                                                  messageSender:messageSender];
    });
    return instance;
}

@end
