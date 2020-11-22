#import "TSAttachment+Albums.h"

@implementation TSAttachment (Albums)

- (nullable TSMessage *)fetchAlbumMessageWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    if (self.albumMessageId == nil) {
        return nil;
    }
    return [TSMessage fetchObjectWithUniqueID:self.albumMessageId transaction:transaction];
}

- (void)migrateAlbumMessageId:(NSString *)albumMesssageId
{
    self.albumMessageId = albumMesssageId;
}

@end
