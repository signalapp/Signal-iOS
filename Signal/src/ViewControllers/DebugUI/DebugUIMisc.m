//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUIMisc.h"
#import "Environment.h"
#import "OWSCountryMetadata.h"
#import "OWSTableViewController.h"
#import "RegistrationViewController.h"
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
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSAccountManager (Debug)

- (void)resetForRegistration;

@end

@implementation DebugUIMisc

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
    [items addObject:[OWSTableItem itemWithTitle:@"Clear experience upgrades (works once per launch)"
                                     actionBlock:^{
                                         [ExperienceUpgrade removeAllObjectsInCollection];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Clear hasDismissedOffers"
                                     actionBlock:^{
                                         [DebugUIMisc clearHasDismissedOffers];
                                     }]];

    [items addObject:[OWSTableItem
                         itemWithTitle:@"Re-register"
                           actionBlock:^{

                               [OWSAlerts
                                   showConfirmationAlertWithTitle:@"Re-register?"
                                                          message:@"If you proceed, you will not lose any of your "
                                                                  @"current messages, but your account will be "
                                                                  @"deactivated until you complete re-registration."
                                                     proceedTitle:@"Proceed"
                                                    proceedAction:^(UIAlertAction *_Nonnull action) {
                                                        [self reregister];
                                                    }];
                           }]];

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

- (void)reregister
{
    DDLogInfo(@"%@ re-registering.", self.logTag);
    [[TSAccountManager sharedInstance] resetForRegistration];
    [[Environment getCurrent].preferences unsetRecordedAPNSTokens];

    RegistrationViewController *viewController = [RegistrationViewController new];
    OWSNavigationController *navigationController =
        [[OWSNavigationController alloc] initWithRootViewController:viewController];
    navigationController.navigationBarHidden = YES;

    [UIApplication sharedApplication].delegate.window.rootViewController = navigationController;
}

+ (void)setManualCensorshipCircumventionEnabled:(BOOL)isEnabled
{
    OWSCountryMetadata *countryMetadata = nil;
    NSString *countryCode = OWSSignalService.sharedInstance.manualCensorshipCircumventionCountryCode;
    if (countryCode) {
        countryMetadata = [OWSCountryMetadata countryMetadataForCountryCode:countryCode];
    }

    if (!countryMetadata) {
        countryCode = [PhoneNumber defaultCountryCode];
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
