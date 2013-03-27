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

@end
