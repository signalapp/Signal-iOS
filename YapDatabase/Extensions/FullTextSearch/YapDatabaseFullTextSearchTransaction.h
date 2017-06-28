#import <Foundation/Foundation.h>

#import "YapDatabaseExtensionTransaction.h"
#import "YapDatabaseFullTextSearchSnippetOptions.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase
 *
 * If you're new to the project you may want to check out the wiki
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * YapDatabaseFullTextSearch is an extension for performing text based search.
 * Internally it uses sqlite's FTS module which was contributed by Google.
 *
 * After registering the extension, you can access this class within a regular transaction.
 * For example:
 *
 * [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
 *
 *     [[transaction ext:@"mySearch"] enumerateKeysMatching:@"birthday party"
 *                                               usingBlock:^(NSString *collection, NSString *key, BOOL *stop){
 *         // matching row...
 *     }]
 * }];
**/
@interface YapDatabaseFullTextSearchTransaction : YapDatabaseExtensionTransaction

// Regular query matching

- (void)enumerateKeysMatching:(NSString *)query
                   usingBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block;

- (void)enumerateKeysAndMetadataMatching:(NSString *)query
                              usingBlock:(void (^)(NSString *collection, NSString *key, id metadata, BOOL *stop))block;

- (void)enumerateKeysAndObjectsMatching:(NSString *)query
                             usingBlock:(void (^)(NSString *collection, NSString *key, id object, BOOL *stop))block;

- (void)enumerateRowsMatching:(NSString *)query
                   usingBlock:(void (^)(NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block;

// FTS5 bm25 ordering

- (void)enumerateBm25OrderedKeysMatching:(NSString *)query
                             withWeights:(nullable NSArray<NSNumber *> *)weights
                              usingBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block;

- (void)enumerateBm25OrderedKeysAndMetadataMatching:(NSString *)query
                                        withWeights:(nullable NSArray<NSNumber *> *)weights
                                         usingBlock:(void (^)(NSString *collection, NSString *key, id metadata, BOOL *stop))block;

- (void)enumerateBm25OrderedKeysAndObjectsMatching:(NSString *)query
                                       withWeights:(nullable NSArray<NSNumber *> *)weights
                                        usingBlock:(void (^)(NSString *collection, NSString *key, id object, BOOL *stop))block;

- (void)enumerateBm25OrderedRowsMatching:(NSString *)query
                             withWeights:(nullable NSArray<NSNumber *> *)weights
                              usingBlock:(void (^)(NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block;

// Query matching + Snippets

- (void)enumerateKeysMatching:(NSString *)query
           withSnippetOptions:(nullable YapDatabaseFullTextSearchSnippetOptions *)options
                   usingBlock:
            (void (^)(NSString *snippet, NSString *collection, NSString *key, BOOL *stop))block;

- (void)enumerateKeysAndMetadataMatching:(NSString *)query
                      withSnippetOptions:(nullable YapDatabaseFullTextSearchSnippetOptions *)options
                              usingBlock:
            (void (^)(NSString *snippet, NSString *collection, NSString *key, id metadata, BOOL *stop))block;

- (void)enumerateKeysAndObjectsMatching:(NSString *)query
                     withSnippetOptions:(nullable YapDatabaseFullTextSearchSnippetOptions *)options
                             usingBlock:
            (void (^)(NSString *snippet, NSString *collection, NSString *key, id object, BOOL *stop))block;

- (void)enumerateRowsMatching:(NSString *)query
           withSnippetOptions:(nullable YapDatabaseFullTextSearchSnippetOptions *)options
                   usingBlock:
            (void (^)(NSString *snippet, NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block;

@end

NS_ASSUME_NONNULL_END
