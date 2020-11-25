#import "TSAttachmentPointer+Backups.h"

@implementation TSAttachmentPointer (Backups)

- (nullable OWSBackupFragment *)lazyRestoreFragment
{
    if (!self.lazyRestoreFragmentId) {
        return nil;
    }
    OWSBackupFragment *_Nullable backupFragment =
        [OWSBackupFragment fetchObjectWithUniqueID:self.lazyRestoreFragmentId];
    OWSAssertDebug(backupFragment);
    return backupFragment;
}

- (void)markForLazyRestoreWithFragment:(OWSBackupFragment *)lazyRestoreFragment
                           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(lazyRestoreFragment);
    OWSAssertDebug(transaction);

    if (!lazyRestoreFragment.uniqueId) {
        // If metadata hasn't been saved yet, save now.
        [lazyRestoreFragment saveWithTransaction:transaction];

        OWSAssertDebug(lazyRestoreFragment.uniqueId);
    }
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSAttachmentPointer *attachment) {
                                 [attachment setLazyRestoreFragmentId:lazyRestoreFragment.uniqueId];
                             }];
}

@end
