//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingConfigurationUpdateInfoMessage.h"
#import "NSString+SSK.h"
#import "OWSDisappearingMessagesConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSDisappearingConfigurationUpdateInfoMessage ()

@property (nonatomic, readonly, nullable) NSString *createdByRemoteName;
@property (nonatomic, readonly) BOOL createdInExistingGroup;
@property (nonatomic, readonly) uint32_t configurationDurationSeconds;

@end

@implementation OWSDisappearingConfigurationUpdateInfoMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                    configuration:(OWSDisappearingMessagesConfiguration *)configuration
              createdByRemoteName:(nullable NSString *)remoteName
           createdInExistingGroup:(BOOL)createdInExistingGroup
{
    self = [super initWithTimestamp:timestamp inThread:thread messageType:TSInfoMessageTypeDisappearingMessagesUpdate];
    if (!self) {
        return self;
    }

    _configurationIsEnabled = configuration.isEnabled;
    _configurationDurationSeconds = configuration.durationSeconds;

    // At most one should be set
    OWSAssertDebug(!remoteName || !createdInExistingGroup);

    _createdByRemoteName = remoteName;
    _createdInExistingGroup = createdInExistingGroup;

    return self;
}

- (BOOL)shouldUseReceiptDateForSorting
{
    // Use the timestamp, not the "received at" timestamp to sort,
    // since we're creating these interactions after the fact and back-dating them.
    return NO;
}

-(NSString *)previewTextWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    if (self.createdInExistingGroup) {
        OWSAssertDebug(self.configurationIsEnabled && self.configurationDurationSeconds > 0);
        NSString *infoFormat = NSLocalizedString(@"DISAPPEARING_MESSAGES_CONFIGURATION_GROUP_EXISTING_FORMAT",
            @"Info Message when added to a group which has enabled disappearing messages. Embeds {{time amount}} "
            @"before messages disappear, see the *_TIME_AMOUNT strings for context.");

        NSString *durationString = [NSString formatDurationSeconds:self.configurationDurationSeconds useShortFormat:NO];
        return [NSString stringWithFormat:infoFormat, durationString];
    } else if (self.createdByRemoteName) {
        if (self.configurationIsEnabled && self.configurationDurationSeconds > 0) {
            NSString *infoFormat = NSLocalizedString(@"OTHER_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                @"Info Message when {{other user}} updates message expiration to {{time amount}}, see the "
                @"*_TIME_AMOUNT "
                @"strings for context.");

            NSString *durationString =
                [NSString formatDurationSeconds:self.configurationDurationSeconds useShortFormat:NO];
            return [NSString stringWithFormat:infoFormat, self.createdByRemoteName, durationString];
        } else {
            NSString *infoFormat = NSLocalizedString(@"OTHER_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                @"Info Message when {{other user}} disables or doesn't support disappearing messages");
            return [NSString stringWithFormat:infoFormat, self.createdByRemoteName];
        }
    } else {
        // Changed by local request
        if (self.configurationIsEnabled && self.configurationDurationSeconds > 0) {
            NSString *infoFormat = NSLocalizedString(@"YOU_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                @"Info message embedding a {{time amount}}, see the *_TIME_AMOUNT strings for context.");

            NSString *durationString =
                [NSString formatDurationSeconds:self.configurationDurationSeconds useShortFormat:NO];
            return [NSString stringWithFormat:infoFormat, durationString];
        } else {
            return NSLocalizedString(@"YOU_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                @"Info Message when you disable disappearing messages");
        }
    }
}

@end

NS_ASSUME_NONNULL_END
