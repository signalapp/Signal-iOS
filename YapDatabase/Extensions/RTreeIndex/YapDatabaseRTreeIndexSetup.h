#import <Foundation/Foundation.h>

@class YapDatabaseRTreeIndexColumn;

@interface YapDatabaseRTreeIndexSetup : NSObject <NSCopying, NSFastEnumeration>

- (id)init;
- (id)initWithCapacity:(NSUInteger)capacity;

- (void)setColumns:(NSArray *)columnNames;

- (NSUInteger)count;
- (NSArray *)columnNames;

@end
