#import <Foundation/Foundation.h>

typedef enum {
	YapDatabaseViewOperationMove,
	YapDatabaseViewOperationInsert,
	YapDatabaseViewOperationDelete,
	
} YapDatabaseViewOperationType;


@interface YapDatabaseViewOperation : NSObject <NSCopying>

+ (YapDatabaseViewOperation *)insertKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index;
+ (YapDatabaseViewOperation *)deleteKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index;

+ (void)processAndConsolidateOperations:(NSMutableArray *)operations;
+ (void)processAndConsolidateOperations:(NSMutableArray *)operations
             withGroupToSectionMappings:(NSDictionary *)mappings;

@property (nonatomic, readonly) id key;

@property (nonatomic, readonly) YapDatabaseViewOperationType type;

@property (nonatomic, readonly) NSString *originalGroup;
@property (nonatomic, readonly) NSString *finalGroup;

@property (nonatomic, readonly) NSUInteger originalIndex;
@property (nonatomic, readonly) NSUInteger finalIndex;

@property (nonatomic, readonly) NSIndexPath *indexPath;
@property (nonatomic, readonly) NSIndexPath *newIndexPath;

@end
