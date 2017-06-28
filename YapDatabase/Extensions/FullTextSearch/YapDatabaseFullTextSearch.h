#import <Foundation/Foundation.h>

#import "YapDatabaseExtension.h"
#import "YapDatabaseFullTextSearchHandler.h"
#import "YapDatabaseFullTextSearchConnection.h"
#import "YapDatabaseFullTextSearchTransaction.h"

NS_ASSUME_NONNULL_BEGIN

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


extern NSString *const YapDatabaseFullTextSearchFTS5Version;
extern NSString *const YapDatabaseFullTextSearchFTS4Version;
extern NSString *const YapDatabaseFullTextSearchFTS3Version;


@interface YapDatabaseFullTextSearch : YapDatabaseExtension

- (id)initWithColumnNames:(NSArray<NSString *> *)columnNames
                  handler:(YapDatabaseFullTextSearchHandler *)handler;

- (id)initWithColumnNames:(NSArray<NSString *> *)columnNames
                    handler:(YapDatabaseFullTextSearchHandler *)handler
               versionTag:(nullable NSString *)versionTag;

- (id)initWithColumnNames:(NSArray<NSString *> *)columnNames
                  options:(nullable NSDictionary *)options
                  handler:(YapDatabaseFullTextSearchHandler *)handler
               versionTag:(nullable NSString *)versionTag;

- (id)initWithColumnNames:(NSArray<NSString *> *)columnNames
                  options:(nullable NSDictionary *)options
                  handler:(YapDatabaseFullTextSearchHandler *)handler
               ftsVersion:(nullable NSString *)ftsVersion
               versionTag:(nullable NSString *)versionTag;


/* Inherited from YapDatabaseExtension
 
@property (nonatomic, strong, readonly) NSString *registeredName;
 
*/

@property (nonatomic, strong, readonly) YapDatabaseFullTextSearchHandler *handler;

/**
 * The versionTag assists in making changes to the extension.
 *
 * If you need to change the columnNames and/or block,
 * then simply pass a different versionTag during the init method,
 * and the FTS extension will automatically update itself.
**/
@property (nonatomic, copy, readonly, nullable) NSString *versionTag;
@property (nonatomic, copy, readonly, nullable) NSString *ftsVersion;

@end

NS_ASSUME_NONNULL_END
