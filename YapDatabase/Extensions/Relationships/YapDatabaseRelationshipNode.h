#import <Foundation/Foundation.h>

@class YapDatabaseRelationshipEdge;

typedef enum  {
	YDB_SourceNodeDeleted,
	YDB_DestinationNodeDeleted,
} YDB_NotifyReason;


/**
 * Any object that is stored in the database may optionally implement this protocol in order to
 * store object relationship information. You can create a relationship between any two objects in the database.
 * In common graph parlance, each item is called a node, and the line between the two nodes is called an edge.
 * This protocol allows you to specify the edges, along with a rule to specify what should happen if
 * one of the 2 nodes gets deleted from the database.
 * 
 * @see YapDatabaseRelationshipEdge
**/
@protocol YapDatabaseRelationshipNode <NSObject>
@required

/**
 * Implement this method in order to return the edges that start from this node.
 * Note that although edges are directional, the associated rules are bidirectional.
 * 
 * In terms of edge direction, this object is the "source" of the edge.
 * And the object at the other end of the edge is called the "destination".
 * 
 * Every edge also has a name (which can be any string you specify), and a bidirectional rule.
 * For example, you could specify either of the following:
 * - delete the destination if I am deleted
 * - delete me if the destination is deleted
 * 
 * In fact, you could specify both of those rules simultaneously for a single edge.
 * And there are similar rules if your graph is one-to-many for this node.
 *
 * Thus it is unnecessary to duplicate the edge on the destination node.
 * So you can pick which node you'd like to create the edge(s) from.
 * Either side is fine, just pick whichever is easier, or whichever makes more sense for your data model.
 *
 * YapDatabaseRelationship supports one-to-one, one-to-many, and even many-to-many relationships.
 * 
 * Important: This method will not be invoked unless the object implements the protocol.
 * That is, the object's class declaration must have YapDatabaseRelationshipNode in its listed protocols.
 *
 * @interface MyObject : NSObject <YapDatabaseRelationshipNode> // <-- Must be in protocol list
 *
 * @see YapDatabaseRelationshipEdge
**/
- (NSArray *)yapDatabaseRelationshipEdges;

@optional

/**
 * If an edge is deleted due to one of two associated nodes being deleted,
 * and the edge has a notify rule associated with it (YDB_NotifyIfSourceDeleted or YDB_NotifyIfDestinationDeleted),
 * then this method may be invoked on the remaining node.
 * 
 * It doesn't matter which side created the edge (the source or destination side).
 * If the rule exists, and the remaining side implements this particular
**/
- (id)yapDatabaseRelationshipEdgeDeleted:(YapDatabaseRelationshipEdge *)edge withReason:(YDB_NotifyReason)reason;

@end


