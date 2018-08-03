//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseMigration.h"

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^DBRecordFilterBlock)(id record);

@class YapDatabaseConnection;

// Base class for migrations that resave all or a subset of
// records in a database collection.
@interface OWSResaveCollectionDBMigration : OWSDatabaseMigration

- (void)resaveDBCollection:(NSString *)collection
                    filter:(nullable DBRecordFilterBlock)filter
              dbConnection:(YapDatabaseConnection *)dbConnection
                completion:(OWSDatabaseMigrationCompletion)completion;

@end

NS_ASSUME_NONNULL_END
