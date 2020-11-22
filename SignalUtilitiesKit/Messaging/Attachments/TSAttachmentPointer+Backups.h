#import <YapDatabase/YapDatabase.h>
#import <SessionMessagingKit/TSAttachmentPointer.h>
#import "OWSBackupFragment.h"

#ifndef TSAttachmentPointer_Backups_h
#define TSAttachmentPointer_Backups_h

@interface TSAttachmentPointer (Backups)

// Non-nil for attachments which need "lazy backup restore."
- (nullable OWSBackupFragment *)lazyRestoreFragment;

// Marks attachment as needing "lazy backup restore."
- (void)markForLazyRestoreWithFragment:(OWSBackupFragment *)lazyRestoreFragment
                           transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

#endif
