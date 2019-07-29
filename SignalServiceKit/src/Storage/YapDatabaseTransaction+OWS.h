//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <YapDatabase/YapDatabase.h>

@class YapDatabaseAutoViewTransaction;
@class YapDatabaseFullTextSearchTransaction;
@class YapDatabaseSecondaryIndexTransaction;
@class YapDatabaseViewTransaction;

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseReadTransaction (OWS)

#pragma mark - Extensions

- (nullable YapDatabaseViewTransaction *)safeViewTransaction:(NSString *)extensionName
    NS_SWIFT_NAME(safeViewTransaction(_:));
- (nullable YapDatabaseAutoViewTransaction *)safeAutoViewTransaction:(NSString *)extensionName
    NS_SWIFT_NAME(safeAutoViewTransaction(_:));
- (nullable YapDatabaseSecondaryIndexTransaction *)safeSecondaryIndexTransaction:(NSString *)extensionName
    NS_SWIFT_NAME(safeSecondaryIndexTransaction(_:));
- (nullable YapDatabaseFullTextSearchTransaction *)safeFullTextSearchTransaction:(NSString *)extensionName
    NS_SWIFT_NAME(safeFullTextSearchTransaction(_:));

@end

NS_ASSUME_NONNULL_END
