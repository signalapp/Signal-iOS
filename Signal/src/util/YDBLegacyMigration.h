//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface YDBLegacyMigration : NSObject

+ (BOOL)ensureIsYDBReadyForAppExtensions:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
