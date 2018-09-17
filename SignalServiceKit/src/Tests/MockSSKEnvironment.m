//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "MockSSKEnvironment.h"
#import "OWSFakeCallMessageHandler.h"
#import "OWSFakeContactsManager.h"
#import "OWSFakeContactsUpdater.h"
#import "OWSFakeMessageSender.h"
#import "OWSFakeNetworkManager.h"
#import "OWSFakeNotificationsManager.h"
#import "OWSFakeProfileManager.h"
#import "OWSPrimaryStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSPrimaryStorage (Tests)

@property (atomic) BOOL areAsyncRegistrationsComplete;
@property (atomic) BOOL areSyncRegistrationsComplete;

@end

#pragma mark -

@implementation MockSSKEnvironment

+ (void)activate
{
    [self setShared:[self new]];
}

- (instancetype)init
{
    OWSPrimaryStorage *primaryStorage = [MockSSKEnvironment createPrimaryStorageForTests];
    id<ContactsManagerProtocol> contactsManager = [OWSFakeContactsManager new];
    TSNetworkManager *networkManager = [OWSFakeNetworkManager new];
    OWSMessageSender *messageSender = [OWSFakeMessageSender new];

    self = [super initWithContactsManager:contactsManager
                            messageSender:messageSender
                           profileManager:[OWSFakeProfileManager new]
                           primaryStorage:primaryStorage
                          contactsUpdater:[OWSFakeContactsUpdater new]
                           networkManager:networkManager];
    if (!self) {
        return nil;
    }
    self.callMessageHandler = [OWSFakeCallMessageHandler new];
    self.notificationsManager = [OWSFakeNotificationsManager new];
    return self;
}


+ (OWSPrimaryStorage *)createPrimaryStorageForTests
{
    OWSPrimaryStorage *primaryStorage = [[OWSPrimaryStorage alloc] initStorage];
    [OWSPrimaryStorage protectFiles];

    // TODO: Should we inject a block to do view registrations?
    primaryStorage.areAsyncRegistrationsComplete = YES;
    primaryStorage.areSyncRegistrationsComplete = YES;

    return primaryStorage;
}

@end

NS_ASSUME_NONNULL_END
