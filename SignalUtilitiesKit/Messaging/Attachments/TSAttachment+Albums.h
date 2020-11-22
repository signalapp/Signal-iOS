#import <SessionMessagingKit/TSAttachment.h>
#import "TSMessage.h"

#ifndef TSAttachment_Albums_h
#define TSAttachment_Albums_h

@interface TSAttachment (Albums)

- (nullable TSMessage *)fetchAlbumMessageWithTransaction:(YapDatabaseReadTransaction *)transaction;

// `migrateAlbumMessageId` is only used in the migration to the new multi-attachment message scheme,
// and shouldn't be used as a general purpose setter. Instead, `albumMessageId` should be passed as
// an initializer param.
- (void)migrateAlbumMessageId:(NSString *)albumMesssageId;

@end

#endif
