#import <Foundation/Foundation.h>

#import "YapDatabaseExtensionTransaction.h"
#import "YapDatabaseRelationshipEdge.h"
#import "YapDatabaseRelationshipNode.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * The YapDatabaseRelationship extension allow you to create relationships between objects,
 * and configure automatic deletion rules.
 *
 * For tons of information about this extension, see the wiki article:
 * https://github.com/yapstudios/YapDatabase/wiki/Relationships
**/

@interface YapDatabaseRelationshipTransaction : YapDatabaseExtensionTransaction

#pragma mark Node Fetch

/**
 * Shortcut for fetching the source object for the given edge.
 * Equivalent to:
 * 
 * [transaction objectForKey:edge.sourceKey inCollection:edge.sourceCollection];
**/
- (nullable id)sourceNodeForEdge:(YapDatabaseRelationshipEdge *)edge;

/**
 * Shortcut for fetching the destination object for the given edge.
 * Equivalent to:
 * 
 * [transaction objectForKey:edge.destinationKey inCollection:edge.destinationCollection];
**/
- (nullable id)destinationNodeForEdge:(YapDatabaseRelationshipEdge *)edge;

#pragma mark Enumerate

/**
 * Enumerates every edge in the graph with the given name.
 * 
 * @param name
 *   The name of the edge (case sensitive).
**/
- (void)enumerateEdgesWithName:(NSString *)name
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block;

/**
 * Enumerates every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - sourceKey & sourceCollection only
 * - name + sourceKey & sourceCollection
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param sourceKey (optional)
 *   The edge.sourceKey to match.
 * 
 * @param sourceCollection (optional)
 *   The edge.sourceCollection to match.
 * 
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (void)enumerateEdgesWithName:(nullable NSString *)name
                     sourceKey:(nullable NSString *)sourceKey
                    collection:(nullable NSString *)sourceCollection
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block;

/**
 * Enumerates every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - destinationKey & destinationCollection only
 * - name + destinationKey & destinationCollection
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param destinationKey (optional)
 *   The edge.destinationKey to match.
 * 
 * @param destinationCollection (optional)
 *   The edge.destinationCollection to match.
 * 
 * If you pass a non-nil destinationKey, and destinationCollection is nil,
 * then the destinationCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (void)enumerateEdgesWithName:(nullable NSString *)name
                destinationKey:(nullable NSString *)destinationKey
                    collection:(nullable NSString *)destinationCollection
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block;

/**
 * Enumerates every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - destinationFileURL
 * - name + destinationFileURL
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param destinationFileURL (optional)
 *   The edge.destinationFileURL to match.
**/
- (void)enumerateEdgesWithName:(nullable NSString *)name
            destinationFileURL:(nullable NSURL *)destinationFileURL
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block;

/**
 * Enumerates every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - sourceKey & sourceCollection only
 * - destinationKey & destinationCollection only
 * - name + sourceKey & sourceCollection
 * - name + destinationKey & destinationCollection
 * - name + sourceKey & sourceCollection + destinationKey & destinationCollection
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param sourceKey (optional)
 *   The edge.sourceKey to match.
 *
 * @param sourceCollection (optional)
 *   The edge.sourceCollection to match.
 * 
 * @param destinationKey (optional)
 *   The edge.destinationKey to match.
 *
 * @param destinationCollection (optional)
 *   The edge.destinationCollection to match.
 *
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
 * 
 * If you pass a non-nil destinationKey, and destinationCollection is nil,
 * then the destinationCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (void)enumerateEdgesWithName:(nullable NSString *)name
                     sourceKey:(nullable NSString *)sourceKey
                    collection:(nullable NSString *)sourceCollection
                destinationKey:(nullable NSString *)destinationKey
                    collection:(nullable NSString *)destinationCollection
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block;

/**
 * Enumerates every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - sourceKey & sourceCollection only
 * - destinationKey & destinationCollection only
 * - name + sourceKey & sourceCollection
 * - name + destinationKey & destinationCollection
 * - name + sourceKey & sourceCollection + destinationKey & destinationCollection
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param sourceKey (optional)
 *   The edge.sourceKey to match.
 *
 * @param sourceCollection (optional)
 *   The edge.sourceCollection to match.
 * 
 * @param destinationFileURL (optional)
 *   The edge.destinationFileURL to match.
 *
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (void)enumerateEdgesWithName:(nullable NSString *)name
                     sourceKey:(nullable NSString *)sourceKey
                    collection:(nullable NSString *)sourceCollection
            destinationFileURL:(nullable NSURL *)destinationFileURL
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block;

#pragma mark Count

/**
 * Returns a count of every edge in the graph with the given name.
 * 
 * @param name
 *   The name of the edge (case sensitive).
**/
- (NSUInteger)edgeCountWithName:(NSString *)name;

/**
 * Returns a count of every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - sourceKey & sourceCollection only
 * - name + sourceKey & sourceCollection
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param sourceKey (optional)
 *   The edge.sourceKey to match.
 * 
 * @param sourceCollection (optional)
 *   The edge.sourceCollection to match.
 * 
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (NSUInteger)edgeCountWithName:(nullable NSString *)name
                      sourceKey:(nullable NSString *)sourceKey
                     collection:(nullable NSString *)sourceCollection;

/**
 * Returns a count of every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - destinationKey & destinationCollection only
 * - name + destinationKey & destinationCollection
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param destinationKey (optional)
 *   The edge.destinationKey to match.
 * 
 * @param destinationCollection (optional)
 *   The edge.destinationCollection to match.
 * 
 * If you pass a non-nil destinationKey, and destinationCollection is nil,
 * then the destinationCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (NSUInteger)edgeCountWithName:(nullable NSString *)name
                 destinationKey:(nullable NSString *)destinationKey
                     collection:(nullable NSString *)destinationCollection;

/**
 * Returns a count of every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - destinationFileURL
 * - name + destinationFileURL
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param destinationFileURL (optional)
 *   The edge.destinationFileURL to match.
**/
- (NSUInteger)edgeCountWithName:(nullable NSString *)name
             destinationFileURL:(nullable NSURL *)destinationFileURL;

/**
 * Returns a count of every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - sourceKey & sourceCollection only
 * - destinationKey & destinationCollection only
 * - name + sourceKey & sourceCollection
 * - name + destinationKey & destinationCollection
 * - name + sourceKey & sourceCollection + destinationKey & destinationCollection
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param sourceKey (optional)
 *   The edge.sourceKey to match.
 *
 * @param sourceCollection (optional)
 *   The edge.sourceCollection to match.
 * 
 * @param destinationKey (optional)
 *   The edge.destinationKey to match.
 *
 * @param destinationCollection (optional)
 *   The edge.destinationCollection to match.
 *
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
 * 
 * If you pass a non-nil destinationKey, and destinationCollection is nil,
 * then the destinationCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (NSUInteger)edgeCountWithName:(nullable NSString *)name
                      sourceKey:(nullable NSString *)sourceKey
                     collection:(nullable NSString *)sourceCollection
                 destinationKey:(nullable NSString *)destinationKey
                     collection:(nullable NSString *)destinationCollection;

/**
 * Returns a count of every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - sourceKey & sourceCollection only
 * - destinationFileURL
 * - name + sourceKey & sourceCollection
 * - name + destinationFileURL
 * - name + sourceKey & sourceCollection + destinationFileURL
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param sourceKey (optional)
 *   The edge.sourceKey to match.
 *
 * @param sourceCollection (optional)
 *   The edge.sourceCollection to match.
 * 
 * @param destinationFileURL (optional)
 *   The edge.destinationFileURL to match.
 *
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (NSUInteger)edgeCountWithName:(nullable NSString *)name
                      sourceKey:(nullable NSString *)sourceKey
                     collection:(nullable NSString *)sourceCollection
             destinationFileURL:(nullable NSURL *)destinationFileURL;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRelationshipTransaction (ReadWrite)

#pragma mark Manual Edge Management

/**
 * There are 2 ways to manage edges (add/remove) using the YapDatabaseRelationship extension:
 * 
 * - Manual edge management (via the methods below)
 * - Implement the YapDatabaseRelationshipNode protocol for some of your objects
 * 
 * For more information, see the wiki section "Edge Creation":
 * 
 * https://github.com/yapstudios/YapDatabase/wiki/Relationships#wiki-edge_creation
**/

/**
 * This method will add the manual edge (if it doesn't already exist).
 * Otherwise it will replace the the existing manual edge with the same name & srcKey/collection & dstKey/collection.
**/
- (void)addEdge:(YapDatabaseRelationshipEdge *)edge;

/**
 * This method will remove the given manual edge (if it exists).
 *
 * The following properties are compared, for the purpose of checking edges to see if they match:
 * - name
 * - sourceKey & sourceCollection
 * - destinationKey & destinationCollection
 * - isManualEdge
 * 
 * In other words, to manually remove an existing manual edge, you simply need to pass an edge instance which
 * has the same name & source & destination.
 * 
 * When you manually remove an edge, you can decide how the relationship extension should process it.
 * That is, you can tell the relationship edge to act as if the source or destination node was deleted:
 * 
 * - YDB_EdgeDeleted            : Do nothing. Simply remove the edge from the database.
 * - YDB_SourceNodeDeleted      : Act as if the source node was deleted.
 * - YDB_DestinationNodeDeleted : Act as if the destination node was deleted.
 * 
 * This allows you to tell the relationship extension whether or not to process the nodeDeleteRules of the edge.
 * And, if so, in what manner.
 * 
 * In other words, you can remove an edge, and tell the relationship extension
 * to pretend the source node was deleted (for example), even if you didn't actually delete the source node.
 * This allows you to execute the nodeDeleteRules that exist on an edge, without actually deleting the node.
 * 
 * Please note that manual edges and protocol edges are in different domains.
 * A manual edge is one you create and add to the system via the addEdge: method.
 * A protocol edge is one created via the YapDatabaseRelationshipNode protocol.
 * So you cannot, for example, create an edge via the YapDatabaseRelationshipNode protocol,
 * and then manually delete it via the removeEdge:: method. This is what is meant by "different domains".
**/
- (void)removeEdgeWithName:(NSString *)edgeName
                 sourceKey:(NSString *)sourceKey
                collection:(nullable NSString *)sourceCollection
            destinationKey:(NSString *)destinationKey
                collection:(nullable NSString *)destinationCollection
            withProcessing:(YDB_NotifyReason)reason;

/**
 * This method is the same as removeEdgeWithName::::::, but allows you to pass an existing edge instance.
 *
 * The following properties of the given edge are inspected, for the purpose of checking edges to see if they match:
 * - name
 * - sourceKey & sourceCollection
 * - destinationKey & destinationCollection
 *
 * The given edge's nodeDeleteRules are ignored.
 * The nodeDeleteRules of the pre-existing edge are processed according to the given reason.
 * 
 * @see removeEdgeWithName:sourceKey:collection:destinationKey:collection:withProcessing:
**/
- (void)removeEdge:(YapDatabaseRelationshipEdge *)edge withProcessing:(YDB_NotifyReason)reason;

#pragma mark Force Processing

/**
 * The extension automatically processes all changes to the graph at the end of a readwrite transaction.
 * This allows it to consolidate multiple changes into a single batch,
 * and also minimizes the impact of cascading delete rules, especially in the case where you'll be deleting
 * many of the objects manually at some later point within the transaction block.
 * 
 * However, there may be certain use cases where it is preferable to have the extension execute its rules in advance.
 * For example, if you need a cascading delete to complete before continuing your transaction logic,
 * then you can force the extension processing to occur prior to the end of the readwrite transaction
 * by invoking this flush method
**/
- (void)flush;

@end

NS_ASSUME_NONNULL_END
