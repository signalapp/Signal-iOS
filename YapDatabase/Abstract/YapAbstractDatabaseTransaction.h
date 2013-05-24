#import <Foundation/Foundation.h>


/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yaptv/YapDatabase/wiki
 *
 * This is the base database class which is shared by YapDatabaseTransaction and YapCollectionsDatabaseTransaction.
 *
 * - YapDatabase = Key/Value
 * - YapCollectionsDatabase = Collection/Key/Value
 *
 * YapAbstractDatabaseTransaction provides the generic implementation of a transaction.
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
 * Returns an extension transaction corresponding to the extension type registered under the given name.
 * If the extension has not yet been opened, it is done so automatically.
 *
 * @return
 *     A subclass of YapAbstractDatabaseExtensionTransaction,
 *     according to the type of extension registered under the given name.
 * 
 * One must register an extension with the database before it can be accessed from within connections or transactions.
 * After registration everything works automatically using just the registered extension name.
 *
 * @see [YapAbstractDatabase registerExtension:withName:]
**/
- (id)extension:(NSString *)extensionName;
- (id)ext:(NSString *)extensionName; // <-- Save yourself some typing

@end
