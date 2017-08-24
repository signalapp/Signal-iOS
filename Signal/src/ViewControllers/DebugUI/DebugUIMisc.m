//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUIMisc.h"
#import "Environment.h"
#import "OWSCountryMetadata.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <AFNetworking/AFNetworking.h>
#import <AxolotlKit/PreKeyBundle.h>
#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SecurityUtils.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSStorageManager+SessionStore.h>
#import <SignalServiceKit/OWSProfileKeyMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIMisc

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Misc.";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];
    [items addObject:[OWSTableItem itemWithTitle:@"Enable Manual Censorship Circumvention"
                                     actionBlock:^{
                                         [DebugUIMisc setManualCensorshipCircumventionEnabled:YES];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Disable Manual Censorship Circumvention"
                                     actionBlock:^{
                                         [DebugUIMisc setManualCensorshipCircumventionEnabled:NO];
                                     }]];
#ifdef DEBUG
    [items addObject:[OWSTableItem itemWithTitle:@"Clear Profile Whitelist"
                                     actionBlock:^{
                                         [OWSProfileManager.sharedManager clearProfileWhitelist];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Log Profile Whitelist"
                                     actionBlock:^{
                                         [OWSProfileManager.sharedManager logProfileWhitelist];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Regenerate Profile/ProfileKey"
                                     actionBlock:^{
                                         [[OWSProfileManager sharedManager] regenerateLocalProfile];
                                     }]];
#endif
    [items addObject:[OWSTableItem itemWithTitle:@"Send profile key message."
                                     actionBlock:^{
                                         OWSProfileKeyMessage *message = [[OWSProfileKeyMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:thread];
                                         
                                         [[Environment getCurrent].messageSender sendMessage:message
                                                                                     success:^{
                                                                                         DDLogInfo(@"Successfully sent profile key message to thread: %@", thread);
                                                                                     }
                                                                                     failure:^(NSError * _Nonnull error) {
                                                                                         OWSFail(@"Failed to send prifle key message to thread: %@", thread);
                                                                                     }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Clear hasDismissedOffers"
                                     actionBlock:^{
                                         [DebugUIMisc clearHasDismissedOffers];
                                     }]];
    return [OWSTableSection sectionWithTitle:self.name items:items];
}

+ (void)setManualCensorshipCircumventionEnabled:(BOOL)isEnabled
{
    OWSCountryMetadata *countryMetadata = nil;
    NSString *countryCode = OWSSignalService.sharedInstance.manualCensorshipCircumventionCountryCode;
    if (countryCode) {
        countryMetadata = [OWSCountryMetadata countryMetadataForCountryCode:countryCode];
    }

    if (!countryMetadata) {
        countryCode = [NSLocale.currentLocale objectForKey:NSLocaleCountryCode];
        if (countryCode) {
            countryMetadata = [OWSCountryMetadata countryMetadataForCountryCode:countryCode];
        }
    }

    if (!countryMetadata) {
        countryCode = @"US";
        countryMetadata = [OWSCountryMetadata countryMetadataForCountryCode:countryCode];
    }

    OWSAssert(countryMetadata);
    OWSSignalService.sharedInstance.manualCensorshipCircumventionCountryCode = countryCode;
    OWSSignalService.sharedInstance.manualCensorshipCircumventionDomain = countryMetadata.googleDomain;

    OWSSignalService.sharedInstance.isCensorshipCircumventionManuallyActivated = isEnabled;
}

+ (void)clearHasDismissedOffers
{
    [TSStorageManager.sharedManager.dbReadWriteConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            NSMutableArray<TSContactThread *> *contactThreads = [NSMutableArray new];
            [transaction
                enumerateKeysAndObjectsInCollection:[TSThread collection]
                                         usingBlock:^(NSString *_Nonnull key, id _Nonnull object, BOOL *_Nonnull stop) {
                                             TSThread *thread = object;
                                             if (thread.isGroupThread) {
                                                 return;
                                             }
                                             TSContactThread *contactThread = object;
                                             [contactThreads addObject:contactThread];
                                         }];
            for (TSContactThread *contactThread in contactThreads) {
                if (contactThread.hasDismissedOffers) {
                    contactThread.hasDismissedOffers = NO;
                    [contactThread saveWithTransaction:transaction];
                }
            }
        }];
}

@end

NS_ASSUME_NONNULL_END
