//
//  TSMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"

NSString *const TSAttachementsRelationshipEdgeName = @"TSAttachmentEdge";

@implementation TSMessage

- (void)addattachments:(NSArray *)attachments {
    for (NSString *identifier in attachments) {
        [self addattachment:identifier];
    }
}

- (void)addattachment:(NSString *)attachment {
    if (!_attachments) {
        _attachments = [NSMutableArray array];
    }

    [self.attachments addObject:attachment];
}

- (NSArray *)yapDatabaseRelationshipEdges {
    NSMutableArray *edges = [[super yapDatabaseRelationshipEdges] mutableCopy];

    if ([self hasAttachments]) {
        for (NSString *attachmentId in self.attachments) {
            YapDatabaseRelationshipEdge *fileEdge =
                [[YapDatabaseRelationshipEdge alloc] initWithName:TSAttachementsRelationshipEdgeName
                                                   destinationKey:attachmentId
                                                       collection:[TSAttachment collection]
                                                  nodeDeleteRules:YDB_DeleteDestinationIfAllSourcesDeleted];
            [edges addObject:fileEdge];
        }
    }
    return edges;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageBody:(NSString *)body
                      attachments:(NSArray *)attachments {
    self = [super initWithTimestamp:timestamp inThread:thread];

    if (self) {
        _body        = body;
        _attachments = [attachments mutableCopy];
    }
    return self;
}

- (BOOL)hasAttachments {
    return self.attachments ? (self.attachments.count > 0) : false;
}

- (NSString *)description {
    if ([self hasAttachments]) {
        NSString *attachmentId   = self.attachments[0];
        TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentId];
        if (attachment) {
            return attachment.description;
        } else {
            return NSLocalizedString(@"UNKNOWN_ATTACHMENT_LABEL", @"In Inbox view, last message label for thread with corrupted attachment.");
        }
    } else {
        return self.body;
    }
}

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    for (NSString *attachmentId in _attachments) {
        TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
        [attachment removeWithTransaction:transaction];
    }

    [super removeWithTransaction:transaction];
}

@end
