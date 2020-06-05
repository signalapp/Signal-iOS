//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncGroupsMessage.h"
#import "OWSGroupsOutputStream.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import <SessionCoreKit/NSDate+OWS.h>
#import <SessionServiceKit/SessionServiceKit-Swift.h>
#import "OWSPrimaryStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncGroupsMessage ()

@property (nonatomic, readonly) TSGroupThread *groupThread;

@end

@implementation OWSSyncGroupsMessage

- (instancetype)initWithGroupThread:(TSGroupThread *)thread
{
    self = [super init];
    if (!self) {
        return self;
    }
    
    _groupThread = thread;
    
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    NSError *error;
    if (self.attachmentIds.count > 1) {
        OWSLogError(@"Expected sync group message to have one or zero attachments, but found %lu.", (unsigned long)self.attachmentIds.count);
    }
    
    SSKProtoSyncMessageGroupsBuilder *groupsBuilder;
    if (self.attachmentIds.count == 0) {
        SSKProtoAttachmentPointerBuilder *attachmentProtoBuilder = [SSKProtoAttachmentPointer builderWithId:0];
        SSKProtoAttachmentPointer *attachmentProto = [attachmentProtoBuilder buildAndReturnError:&error];
        groupsBuilder = [SSKProtoSyncMessageGroups builder];
        [groupsBuilder setBlob:attachmentProto];
        __block NSData *data;
        [OWSPrimaryStorage.sharedManager.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            data = [self buildPlainTextAttachmentDataWithTransaction:transaction];
        }];
        [groupsBuilder setData:data];
    } else {
        SSKProtoAttachmentPointer *attachmentProto = [TSAttachmentStream buildProtoForAttachmentId:self.attachmentIds.firstObject];
        if (attachmentProto == nil) {
            OWSFailDebug(@"Couldn't build protobuf.");
            return nil;
        }
        groupsBuilder = [SSKProtoSyncMessageGroups builder];
        [groupsBuilder setBlob:attachmentProto];
    }

    SSKProtoSyncMessageGroups *_Nullable groupsProto = [groupsBuilder buildAndReturnError:&error];
    if (error || !groupsProto) {
        OWSFailDebug(@"Couldn't build protobuf due to error: %@.", error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    [syncMessageBuilder setGroups:groupsProto];

    return syncMessageBuilder;
}

- (nullable NSData *)buildPlainTextAttachmentDataWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    // TODO use temp file stream to avoid loading everything into memory at once
    // First though, we need to re-engineer our attachment process to accept streams (encrypting with stream,
    // and uploading with streams).
    NSOutputStream *dataOutputStream = [NSOutputStream outputStreamToMemory];
    [dataOutputStream open];
    OWSGroupsOutputStream *groupsOutputStream = [[OWSGroupsOutputStream alloc] initWithOutputStream:dataOutputStream];
    [groupsOutputStream writeGroup:self.groupThread transaction:transaction];
    [dataOutputStream close];

    if (groupsOutputStream.hasError) {
        OWSFailDebug(@"Could not write groups sync stream.");
        return nil;
    }

    return [dataOutputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
}

@end

NS_ASSUME_NONNULL_END
