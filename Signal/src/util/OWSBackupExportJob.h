//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupJob.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSBackupExportJob : OWSBackupJob

- (void)startAsync;

@end

NS_ASSUME_NONNULL_END
