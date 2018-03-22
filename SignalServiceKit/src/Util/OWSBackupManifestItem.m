//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupManifestItem.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSBackupManifestItem

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(self.recordName.length > 0);

    if (!self.uniqueId) {
        self.uniqueId = self.recordName;
    }
    [super saveWithTransaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
