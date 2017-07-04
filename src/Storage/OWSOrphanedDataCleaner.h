//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface OWSOrphanedDataCleaner : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (void)auditAsync;

+ (void)auditAndCleanupAsync;

@end
