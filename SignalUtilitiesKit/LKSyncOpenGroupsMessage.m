#import "LKSyncOpenGroupsMessage.h"
#import "OWSPrimaryStorage.h"
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation LKSyncOpenGroupsMessage

- (instancetype)init
{
    return [super init];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    NSError *error;
    NSMutableArray<SSKProtoSyncMessageOpenGroupDetails *> *openGroupSyncMessages = @[].mutableCopy;
    __block NSDictionary<NSString *, SNOpenGroup *> *openGroups;
    [OWSPrimaryStorage.sharedManager.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        openGroups = [LKDatabaseUtilities getAllPublicChats:transaction];
    }];
    for (SNOpenGroup *openGroup in openGroups.allValues) {
        SSKProtoSyncMessageOpenGroupDetailsBuilder *openGroupSyncMessageBuilder = [SSKProtoSyncMessageOpenGroupDetails builderWithUrl:openGroup.server channelID:openGroup.channel];
        SSKProtoSyncMessageOpenGroupDetails *_Nullable openGroupSyncMessage = [openGroupSyncMessageBuilder buildAndReturnError:&error];
        if (error || !openGroupSyncMessage) {
            OWSFailDebug(@"Couldn't build protobuf due to error: %@.", error);
            return nil;
        }
        [openGroupSyncMessages addObject:openGroupSyncMessage];
    }
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    [syncMessageBuilder setOpenGroups:openGroupSyncMessages];
    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
