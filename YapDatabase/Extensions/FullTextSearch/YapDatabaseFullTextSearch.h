#import <Foundation/Foundation.h>

#import "YapDatabaseExtension.h"
#import "YapDatabaseFullTextSearchHandler.h"
#import "YapDatabaseFullTextSearchConnection.h"
#import "YapDatabaseFullTextSearchTransaction.h"

/**
 * Welcome to YapDatabase!
 *
 * https://github.com/yapstudios/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * YapDatabaseFullTextSearch is an extension for performing text based search.
 * Internally it uses sqlite's FTS module which was contributed by Google.
**/
@interface YapDatabaseFullTextSearch : YapDatabaseExtension

- (id)initWithColumnNames:(NSArray *)columnNames
                  handler:(YapDatabaseFullTextSearchHandler *)handler;

- (id)initWithColumnNames:(NSArray *)columnNames
                    handler:(YapDatabaseFullTextSearchHandler *)handler
               versionTag:(NSString *)versionTag;

- (id)initWithColumnNames:(NSArray *)columnNames
                  options:(NSDictionary *)options
                  handler:(YapDatabaseFullTextSearchHandler *)handler
               versionTag:(NSString *)versionTag;


/* Inherited from YapDatabaseExtension
 
@property (nonatomic, strong, readonly) NSString *registeredName;
 
*/

@property (nonatomic, strong, readonly) YapDatabaseFullTextSearchBlock block;
@property (nonatomic, assign, readonly) YapDatabaseFullTextSearchBlockType blockType;

/**
 * The versionTag assists in making changes to the extension.
 *
 * If you need to change the columnNames and/or block,
 * then simply pass a different versionTag during the init method,
 * and the FTS extension will automatically update itself.
**/
@property (nonatomic, copy, readonly) NSString *versionTag;

@end
