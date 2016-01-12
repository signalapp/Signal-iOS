#import <Foundation/Foundation.h>

#import "YapDatabaseRelationshipNode.h"
#import "YapDatabaseRelationshipEdge.h"

/**
 * The following test classes are for use by TestYapDatabaseRelationship.
**/

/**
 * Standard relationship: (parent)->(child)
 * nodeDeleteRule = YDB_DeleteDestinationIfSourceDeleted
 * 
 * So the parent node creates the edge which points to the child node.
 * And the child should get deleted if the parent is deleted.
**/
@interface Node_Standard : NSObject <NSCoding, YapDatabaseRelationshipNode>

@property (nonatomic, strong, readonly) NSString *key;
@property (nonatomic, copy, readwrite) NSArray *childKeys;

@end


/**
 * Standard inverse relationship: (child)->(parent)
 * nodeDeleteRule = YDB_DeleteSourceIfDestinationDeleted
 * 
 * So the child node creates the edge which points to the parent node.
 * And the child should get deleted if the parent is deleted.
**/
@interface Node_Inverse : NSObject <NSCoding, YapDatabaseRelationshipNode>

@property (nonatomic, strong, readonly) NSString *key;
@property (nonatomic, copy, readwrite) NSString *parentKey;

@end

/**
 * Retain count relationship: (retainer)->(retained)
 * nodeDeleteRule = YDB_DeleteDestinationIfAllSourcesDeleted
 * 
 * So the retainer node creates the edge which points the the retained node.
 * And there may be multiple retainers pointing to the same retained node.
 * And the retained node doesn't get deleted unless all the retainers are deleted.
**/
@interface Node_RetainCount : NSObject <NSCoding, YapDatabaseRelationshipNode>

@property (nonatomic, strong, readonly) NSString *key;
@property (nonatomic, copy, readwrite) NSString *retainedKey;

@end

/**
 * Inverse retain count relationship: (retained)->(retainer)
 * nodeDeleteRule = YDB_DeleteSourceIfAllDestinationsDeleted
 * 
 * So the retained node creates the edge which points to the retainer node(s).
 * And there may be multiple retainers.
 * And the retained node should get deleted if all the retainers are deleted.
**/
@interface Node_InverseRetainCount : NSObject <NSCoding, YapDatabaseRelationshipNode>

@property (nonatomic, strong, readonly) NSString *key;
@property (nonatomic, copy, readwrite) NSArray *retainerKeys;

@end

/**
 * Standard file relationship: (parent)->(file)
 * nodeDeleteRule = YDB_DeleteDestinationIfSourceDeleted
 * 
 * So the parent node creates the edge which points to the "child" filePath.
 * And the file should get deleted if the parent is deleted.
**/
@interface Node_Standard_FileURL : NSObject <NSCoding, YapDatabaseRelationshipNode>

@property (nonatomic, strong, readonly) NSString *key;
@property (nonatomic, copy, readwrite) NSURL *fileURL;

@end

/**
 * Retain count file relationship: (parent)->(file)
 * nodeDeleteRule = YDB_DeleteDestinationIfAllSourcesDeleted
 *
 * So the retainer node creates the edge which points the the retained file.
 * And there may be multiple retainers pointing to the same retained file.
 * And the file doesn't get deleted unless all the retainers are deleted.
 **/
@interface Node_RetainCount_FileURL : NSObject <NSCoding, YapDatabaseRelationshipNode>

@property (nonatomic, strong, readonly) NSString *key;
@property (nonatomic, copy, readwrite) NSURL *fileURL;

@end
