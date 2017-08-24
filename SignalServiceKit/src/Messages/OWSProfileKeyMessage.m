//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSProfileKeyMessage.h"
#import "OWSSignalServiceProtos.pb.h"
#import "ProfileManagerProtocol.h"
#import "ProtoBuf+OWS.h"
#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSProfileKeyMessage

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    // override superclass with no-op.
    //
    // There's no need to save this message, since it's not displayed to the user.
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (OWSSignalServiceProtosDataMessage *)buildDataMessage:(NSString *_Nullable)recipientId
{
    OWSAssert(self.thread);
    
    OWSSignalServiceProtosDataMessageBuilder *builder = [self dataMessageBuilder];
    [builder addLocalProfileKey];
    [builder setFlags:OWSSignalServiceProtosDataMessageFlagsProfileKey];
    
    if (recipientId.length > 0) {
        // Once we've shared our profile key with a user (perhaps due to being
        // a member of a whitelisted group), make sure they're whitelisted.
        id<ProfileManagerProtocol> profileManager = [TextSecureKitEnv sharedEnv].profileManager;
        // FIXME PERF avoid this dispatch. It's going to happen for *each* recipient in a group message.
        dispatch_async(dispatch_get_main_queue(), ^{
            [profileManager addUserToProfileWhitelist:recipientId];
        });
    }

    return [builder build];
}

@end

NS_ASSUME_NONNULL_END
