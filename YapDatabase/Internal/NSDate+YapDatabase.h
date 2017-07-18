#import <Foundation/Foundation.h>


@interface NSDate (YapDatabase)

- (BOOL)ydb_isBefore:(NSDate *)date;
- (BOOL)ydb_isAfter:(NSDate *)date;

- (BOOL)ydb_isBeforeOrEqual:(NSDate *)date;
- (BOOL)ydb_isAfterOrEqual:(NSDate *)date;

@end
