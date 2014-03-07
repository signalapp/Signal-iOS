#import <Foundation/Foundation.h>

#import "YapDatabaseExtensionTransaction.h"
#import "YapDatabaseRelationshipEdge.h"

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yaptv/YapDatabase/wiki
 *
 * The YapDatabaseRelationship extension allow you to create relationships between objects,
 * and configure automatic deletion rules.
 *
 * For tons of information about this extension, see the wiki article:
 * https://github.com/yaptv/YapDatabase/wiki/Relationships
**/

@interface YapDatabaseRelationshipTransaction : YapDatabaseExtensionTransaction

#pragma mark Node Fetch

/**
 * Shortcut for fetching the source object for the given edge.
 * Equivalent to:
 * 
 * [transaction objectForKey:edge.sourceKey inCollection:edge.sourceCollection];
**/
- (id)sourceNodeForEdge:(YapDatabaseRelationshipEdge *)edge;

/**
 * Shortcut for fetching the destination object for the given edge.
 * Equivalent to:
 * 
 * [transaction objectForKey:edge.destinationKey inCollection:edge.destinationCollection];
**/
- (id)destinationNodeForEdge:(YapDatabaseRelationshipEdge *)edge;

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
- (void)enumerateEdgesWithName:(NSString *)name
                     sourceKey:(NSString *)sourceKey
                    collection:(NSString *)sourceCollection
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
- (void)enumerateEdgesWithName:(NSString *)name
                destinationKey:(NSString *)destinationKey
                    collection:(NSString *)destinationCollection
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block;

/**
 * Enumerates every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - destinationFilePath
 * - name + destinationFilePath
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param destinationFilePath (optional)
 *   The edge.destinationFilePath to match.
**/
- (void)enumerateEdgesWithName:(NSString *)name
           destinationFilePath:(NSString *)destinationFilePath
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
- (void)enumerateEdgesWithName:(NSString *)name
                     sourceKey:(NSString *)sourceKey
                    collection:(NSString *)sourceCollection
                destinationKey:(NSString *)destinationKey
                    collection:(NSString *)destinationCollection
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
 * @param destinationFilePath (optional)
 *   The edge.destinationFilePath to match.
 *
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (void)enumerateEdgesWithName:(NSString *)name
                     sourceKey:(NSString *)sourceKey
                    collection:(NSString *)sourceCollection
           destinationFilePath:(NSString *)destinationFilePath
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
- (NSUInteger)edgeCountWithName:(NSString *)name
                      sourceKey:(NSString *)sourceKey
                     collection:(NSString *)sourceCollection;

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
- (NSUInteger)edgeCountWithName:(NSString *)name
                 destinationKey:(NSString *)destinationKey
                     collection:(NSString *)destinationCollection;

/**
 * Returns a count of every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - destinationFilePath
 * - name + destinationFilePath
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param destinationFilePath (optional)
 *   The edge.destinationFilePath to match.
**/
- (NSUInteger)edgeCountWithName:(NSString *)name
            destinationFilePath:(NSString *)destinationFilePath;

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
- (NSUInteger)edgeCountWithName:(NSString *)name
                      sourceKey:(NSString *)sourceKey
                     collection:(NSString *)sourceCollection
                 destinationKey:(NSString *)destinationKey
                     collection:(NSString *)destinationCollection;

/**
 * Returns a count of every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - sourceKey & sourceCollection only
 * - destinationFilePath
 * - name + sourceKey & sourceCollection
 * - name + destinationFilePath
 * - name + sourceKey & sourceCollection + destinationFilePath
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
 * @param destinationFilePath (optional)
 *   The edge.destinationFilePath to match.
 *
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (NSUInteger)edgeCountWithName:(NSString *)name
                      sourceKey:(NSString *)sourceKey
                     collection:(NSString *)sourceCollection
            destinationFilePath:(NSString *)destinationFilePath;

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
 * https://github.com/yaptv/YapDatabase/wiki/Relationships#wiki-edge_creation
**/

/**
 * The addEdge: method will add the manual edge (if it doesn't already exist).
 * Otherwise it will replace the the existing manual edge with the same name & srcKey/collection & dstKey/collection.
**/
- (void)addEdge:(YapDatabaseRelationshipEdge *)edge;

- (void)removeEdge:(YapDatabaseRelationshipEdge *)edge;

#pragma mark Force Processing

/**
 * The extension automatically processes all changes to the graph at the end of a readwrite transaction.
 * This allows it to consolidate multiple changes into a single batch,
 * and also minimizes the impact of cascading delete rules, especially in the case where you'll be deleting
 * many of the objects manually at some later point within the transaction block.
 * 
 * However, there may be certain use cases where it is preferable to have the extension execute its rules in advance.
 * I'm struggling to come up with a really good example, so this semi-convoluted one will have to do:
 * 
 * You have a parent object, with a bunch of child objects that have edges to the parent.
 * You need to replace the parent, and for whatever reason the new parent has the same collection/key.
 * So instead of doing a setObject:forKey:inCollection:, you first delete the original parent.
 * At that point you can invoke this flush method, and it will properly delete any child objects.
 * Then you can safely set the new parent, knowing it won't accidentally inherit any children from the old parent.
**/
- (void)flush;

@end
