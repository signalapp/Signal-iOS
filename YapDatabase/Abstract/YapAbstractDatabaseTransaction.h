#import <Foundation/Foundation.h>


/**
 * This base class is shared by YapDatabaseTransaction and YapCollectionsDatabaseTransaction.
 *
 * It provides the generic implementation of a transaction.
**/
@interface YapAbstractDatabaseTransaction : NSObject

/**
 * Under normal circumstances, when a read-write transaction block completes,
 * the changes are automatically committed. If, however, something goes wrong and
 * you'd like to abort and discard all changes made within the transaction,
 * then invoke this method.
 * 
 * You should generally return (exit the transaction block) after invoking this method.
 * Any changes made within the the transaction before and after invoking this method will be discarded.
 *
 * Invoking this method from within a read-only transaction does nothing.
**/
- (void)rollback;

/**
 * Attempts to open the view with the given name.
 *
 * Views are automatically opened using the view: method, if they're not yet open.
 * However there is a small overhead involved with opening a view.
 * Thus this method may be used to incur the cost ahead of time before the application requires use of the view.
 *
 * @return
 *    YES if the view was successfully opened or was already open.
 *    NO otherwise.
 * 
 * One must register a view with the database before it can be accessed from within connections or transactions.
 * After registration everything works automatically using just the view name.
 * 
 * @see [YapAbstractDatabase registerView:withName:]
**/
- (BOOL)openView:(NSString *)viewName;

/**
 * Returns a view transaction corresponding to the view type registered under the given name.
 * If the view has not yet been opened, it is done so automatically.
 *
 * @return
 *     A subclass of YapAbstractDatabaseViewTransaction,
 *     according to the type of view registered under the given name.
 * 
 * One must register a view with the database before it can be accessed from within connections or transactions.
 * After registration everything works automatically using just the view name.
 *
 * @see [YapAbstractDatabase registerView:withName:]
**/
- (id)view:(NSString *)viewName;

@end
