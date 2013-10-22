#import <Foundation/Foundation.h>

#import "YapAbstractDatabaseExtensionTransaction.h"
#import "YapDatabaseQuery.h"


@interface YapDatabaseSecondaryIndexTransaction : YapAbstractDatabaseExtensionTransaction

/**
 * 
 *
 * @return NO if there was a problem with the given query. YES otherwise.
**/
- (BOOL)enumerateKeysMatchingQuery:(YapDatabaseQuery *)query
                        usingBlock:(void (^)(NSString *key, BOOL *stop))block;

/**
 *
**/
- (BOOL)enumerateKeysAndMetadataMatchingQuery:(YapDatabaseQuery *)query
                                   usingBlock:(void (^)(NSString *key, id metadata, BOOL *stop))block;

/**
 *
**/
- (BOOL)enumerateKeysAndObjectsMatchingQuery:(YapDatabaseQuery *)query
                                  usingBlock:(void (^)(NSString *key, id object, BOOL *stop))block;

/**
 *
**/
- (BOOL)enumerateRowsMatchingQuery:(YapDatabaseQuery *)query
                        usingBlock:(void (^)(NSString *key, id object, id metadata, BOOL *stop))block;

@end
