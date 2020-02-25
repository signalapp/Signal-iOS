#import "OWSSyncOpenGroupsMessage.h"
#import "OWSPrimaryStorage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSSyncOpenGroupsMessage

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
    NSMutableArray<SSKProtoSyncMessageOpenGroups *> *sessionOpenGroups = @[].mutableCopy;
    __block NSDictionary<NSString *, LKPublicChat *> *publicChats;
    [OWSPrimaryStorage.sharedManager.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        publicChats = [LKDatabaseUtilities getAllPublicChats:transaction];
    }];
    for (LKPublicChat *openGroup in publicChats.allValues) {
        SSKProtoSyncMessageOpenGroupsBuilder *openGroupBuilder = [SSKProtoSyncMessageOpenGroups builder];
        [openGroupBuilder setUrl:openGroup.server];
        [openGroupBuilder setChannel:openGroup.channel];
        SSKProtoSyncMessageOpenGroups *_Nullable openGroupProto = [openGroupBuilder buildAndReturnError:&error];
        if (error || !openGroupProto) {
            OWSFailDebug(@"could not build protobuf: %@", error);
            return nil;
        }
        [sessionOpenGroups addObject:openGroupProto];
    }

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    [syncMessageBuilder setOpenGroups:sessionOpenGroups];

    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
