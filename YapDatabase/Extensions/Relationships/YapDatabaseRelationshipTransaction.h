#import <Foundation/Foundation.h>

#import "YapDatabaseExtensionTransaction.h"
#import "YapDatabaseRelationshipEdge.h"


@interface YapDatabaseRelationshipTransaction : YapDatabaseExtensionTransaction

- (void)enumerateEdgesWithName:(NSString *)name
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block;

- (void)enumerateEdgesWithName:(NSString *)name
                destinationKey:(NSString *)dstKey
                    collection:(NSString *)dstCollection
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block;

- (void)enumerateEdgesWithName:(NSString *)name
                destinationKey:(NSString *)dstKey
                    collection:(NSString *)dstCollection
                     sourceKey:(NSString *)srcKey
                    collection:(NSString *)srcCollection
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block;

@end

// NOTE: We need a method to force the relationship to run its preCommitReadWriteTransaction code.
// - flush
// - processPendingChanges
// - flushPendingChanges
//
// something like that