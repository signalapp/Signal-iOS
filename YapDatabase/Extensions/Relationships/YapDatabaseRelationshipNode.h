#import <Foundation/Foundation.h>
#import "YapDatabaseRelationshipEdge.h"

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

typedef NS_ENUM(NSInteger, YDB_NotifyReason) {
	YDB_EdgeDeleted,
	YDB_SourceNodeDeleted,
	YDB_DestinationNodeDeleted,
};


/**
 * There are 2 techniques you may use to add edges to the relationship graph:
 *
 * - Use the YapDatabaseRelationshipNode protocol
 * - Manually manage the edges by adding / removing them yourself
 *
 * You are welcome to use either technique. In fact you can use them both simultaneously.
 * Which you choose may simply be whichever works best depending on the situation.
 * 
 * The YapDatabaseRelationshipNode protocol works quite simply:
 *
 * Any object that is stored in the database may optionally implement this protocol in order to
 * specify a list of relationships that apply to it. The object just needs to:
 * 1.) Add the YapDatabaseRelationshipNode protocol to its declared list of protocols (in header file)
 * 2.) Implement the yapDatabaseRelationshipEdges method
 * 
 * When the object is inserted or updated in the database, the YapDatabaseRelationshipExtension will automatically
 * invoke the yapDatabaseRelationshipEdges method to get the list of edges. It then inserts the list of edges
 * into the database (if object was inserted), or updates the previously inserted list (if object was updated).
 *
 * Typically this protocol is convenient to use if:
 * - Your objects already contain identifiers that can be used to create the edges you desire
 * - You'd like to be able to delete objects in the database by simply setting identifier properties to nil
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
 * ... MyObject : NSObject <YapDatabaseRelationshipNode> // <-- Must be in protocol list
 *
 * @see YapDatabaseRelationshipEdge
**/
- (nullable NSArray<YapDatabaseRelationshipEdge *> *)yapDatabaseRelationshipEdges;

@optional

/**
 * If an edge is deleted due to one of two associated nodes being deleted,
 * and the edge has a notify rule associated with it (YDB_NotifyIfSourceDeleted or YDB_NotifyIfDestinationDeleted),
 * then this method may be invoked on the remaining node.
 * 
 * For example, if YDB_NotifyIfDestinationDeleted is specified, and the destination node is deleted,
 * and the source node implements this method, then this method will be invoked on the remaining source node.
 * 
 * This method is designed to support "weak" references.
 * For example:
 * 
 *   A source node might contain a property named "cachedServerResponse", which points to a cached response object
 *   that's stored in the database. However, this cached object may be deleted at any time for various reasones
 *   (e.g. becomes stale, access token expiration, user logout). The desire is for the sourceNode.cachedServerResponse
 *   property to be automatically set to nil if/when the "cachedServerResponse" object is deleted from the database.
 *   This method helps automate that.
 * 
 *   Simply create a relationship between the source node and the "cachedServerResponse" object, and set the
 *   YDB_NotifyIfDestinationDeleted flag on the edge. Then, when the "cachedServerResponse" object is deleted,
 *   this method is automatically invoked on the source node. At that point, the source node simply sets its
 *   "cachedServerResponse" property to nil, and return self.
 * 
 * @return
 *   If you return an object, that object automatically replaces the previous object in the database.
 *   Specifically, the code invokes 'replaceObject:forKey:inCollection:'.
 *   I.E. the object is replaced, but any existing metadata remains as is.
 *   
 *   If you return nil, then nothing happens.
 * 
 * The recommended way of implementing this method is typically something like this:
 * 
 * - (id)yapDatabaseRelationshipEdgeDeleted:(YapDatabaseRelationshipEdge *)edge withReason:(YDB_NotifyReason)reason
 * {
 *     if ([edge.name isEqualToString:@"cachedServerResponse"])
 *     {
 *         id copy = [self copy];
 *         copy.cachedServerResponse = nil;
 *         return copy;
 *     }
 *
 *     return nil;
 * }
**/
- (nullable id)yapDatabaseRelationshipEdgeDeleted:(YapDatabaseRelationshipEdge *)edge
                                       withReason:(YDB_NotifyReason)reason;

@end

NS_ASSUME_NONNULL_END
