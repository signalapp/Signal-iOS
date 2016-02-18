#import <Foundation/Foundation.h>

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

typedef NS_OPTIONS(uint16_t, YDB_NodeDeleteRules) {
    // notify only
    YDB_NotifyIfSourceDeleted      = 1 << 0,
    YDB_NotifyIfDestinationDeleted = 1 << 1,
    
    // one-to-one
    YDB_DeleteSourceIfDestinationDeleted = 1 << 2,
    YDB_DeleteDestinationIfSourceDeleted = 1 << 3,
    
    // one-to-many & many-to-many
    YDB_DeleteSourceIfAllDestinationsDeleted = 1 << 4,
    YDB_DeleteDestinationIfAllSourcesDeleted = 1 << 5,
};

@interface YapDatabaseRelationshipEdge : NSObject <NSCopying>

/**
 * Returns an edge with the given name, destination & nodeDeleteRules.
 * 
 * This method is suitable for use with the YapDatabaseRelationshipNode protocol.
 * When using this protocol, the source object is directly queried by the YapDatabaseRelationship extension.
 * Thus the extension already knows what the source node is,
 * and so the source node information (sourceKey & sourceCollection) doesn't need to be explicitly set on the edge.
 * 
 * This method is not suitable for use with manual edge management.
 * When manually adding an edge, you must fully specify the source node.
**/
+ (instancetype)edgeWithName:(NSString *)name
              destinationKey:(NSString *)destinationKey
                  collection:(nullable NSString *)destinationCollection
             nodeDeleteRules:(YDB_NodeDeleteRules)rules;

/**
 * Returns an edge with the given name, destinationFilePath & nodeDeleteRules.
 * 
 * When using a destinationFilePath, only a subset of the nodeDeleteRules apply.
 * Specifically only the following work:
 * - YDB_DeleteDestinationIfSourceDeleted
 * - YDB_DeleteDestinationIfAllSourcesDeleted
 *
 * This method is suitable for use with the YapDatabaseRelationshipNode protocol.
 * When using this protocol, the source object is directly queried by the YapDatabaseRelationship extension.
 * Thus the extension already knows what the source node is,
 * and so the source node information (sourceKey & sourceCollection) doesn't need to be explicitly set on the edge.
 * 
 * This method is not suitable for use with manual edge management.
 * When directly adding an edge, you must fully specify the source node.
**/
+ (instancetype)edgeWithName:(NSString *)name
          destinationFileURL:(NSURL *)destinationFileURL
             nodeDeleteRules:(YDB_NodeDeleteRules)rules;

/**
 * Returns a fully specified edge.
 * 
 * This method is suitable for use with manual edge management.
 * 
 * If you're using the YapDatabaseRelationshipNode protocol, then you can use the shorter version of this method
 * which doesn't specify the source node. This is because the source node is implied with the
 * YapDatabaseRelationshipNode protocol, and thus doesn't need to be explicitly specified in the edge.
**/
+ (instancetype)edgeWithName:(NSString *)name
                   sourceKey:(NSString *)sourceKey
                  collection:(nullable NSString *)sourceCollection
              destinationKey:(NSString *)destinationKey
                  collection:(nullable NSString *)destinationCollection
             nodeDeleteRules:(YDB_NodeDeleteRules)rules;

/**
 * Returns a fully specified edge.
 * 
 * When using a destinationFilePath, only a subset of the nodeDeleteRules apply.
 * Specifically only the following work:
 * - YDB_DeleteDestinationIfSourceDeleted
 * - YDB_DeleteDestinationIfAllSourcesDeleted
 *
 * This method is suitable for use with manual edge management.
 *
 * If you're using the YapDatabaseRelationshipNode protocol, then you can use the shorter version of this method
 * which doesn't specify the source node. This is because the source node is implied with the
 * YapDatabaseRelationshipNode protocol, and thus doesn't need to be explicitly specified in the edge.
**/
+ (instancetype)edgeWithName:(NSString *)name
                   sourceKey:(NSString *)sourceKey
                  collection:(nullable NSString *)sourceCollection
          destinationFileURL:(NSURL *)destinationFileURL
             nodeDeleteRules:(YDB_NodeDeleteRules)rules;

#pragma mark Init

/**
 * For documentation @see edgeWithName:destinationKey:collection:nodeDeleteRules:
**/
- (id)initWithName:(NSString *)name
    destinationKey:(NSString *)key
        collection:(nullable NSString *)collection
   nodeDeleteRules:(YDB_NodeDeleteRules)rules;

/**
 * For documentation @see edgeWithName:destinationFilePath:nodeDeleteRules:
**/
- (id)initWithName:(NSString *)name destinationFileURL:(NSURL *)destinationFileURL
                                       nodeDeleteRules:(YDB_NodeDeleteRules)rules;

/**
 * For documentation @see edgeWithName:sourceKey:collection:destinationKey:collection:nodeDeleteRules:
**/
- (id)initWithName:(NSString *)name
         sourceKey:(NSString *)sourceKey
        collection:(nullable NSString *)sourceCollection
    destinationKey:(NSString *)destinationKey
        collection:(nullable NSString *)destinationCollection
   nodeDeleteRules:(YDB_NodeDeleteRules)rules;

/**
 * For documentation @see edgeWithName:sourceKey:collection:destinationFilePath:nodeDeleteRules:
**/
- (id)initWithName:(NSString *)name sourceKey:(NSString *)sourceKey
                                   collection:(nullable NSString *)sourceCollection
                           destinationFileURL:(NSURL *)destinationFileURL
                              nodeDeleteRules:(YDB_NodeDeleteRules)rules;

#pragma mark Properties

@property (nonatomic, copy, readonly) NSString *name;

@property (nonatomic, copy, readonly) NSString *sourceKey;
@property (nonatomic, copy, readonly) NSString *sourceCollection;

@property (nonatomic, copy, readonly) NSString *destinationKey;
@property (nonatomic, copy, readonly) NSString *destinationCollection;

@property (nonatomic, copy, readonly) NSURL *destinationFileURL;

@property (nonatomic, assign, readonly) YDB_NodeDeleteRules nodeDeleteRules;

/**
 * NO if the edge was created via the YapDatabaseRelationshipNode protocol.
 * YES if the edge was created via "manual edge management" methods.
**/
@property (nonatomic, assign, readonly) BOOL isManualEdge;

@end

NS_ASSUME_NONNULL_END
