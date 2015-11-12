#import <Foundation/Foundation.h>


@interface NSDate (YapDatabase)

- (BOOL)isBefore:(NSDate *)date;
- (BOOL)isAfter:(NSDate *)date;

- (BOOL)isBeforeOrEqual:(NSDate *)date;
- (BOOL)isAfterOrEqual:(NSDate *)date;

@end
