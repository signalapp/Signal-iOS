#import <Foundation/Foundation.h>

#import "YapAbstractDatabaseView.h"
#import "YapAbstractDatabaseViewConnection.h"
#import "YapAbstractDatabaseViewTransaction.h"

#import "YapAbstractDatabaseConnection.h"
#import "YapAbstractDatabaseTransaction.h"


@interface YapAbstractDatabaseView () {
@protected
	NSString *name;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapAbstractDatabaseConnection () {
@protected
	
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapAbstractDatabaseViewTransaction () {
@protected
	__strong YapAbstractDatabaseConnection *connection;
	
	__unsafe_unretained YapAbstractDatabaseTransaction *readTransaction;
	__unsafe_unretained YapAbstractDatabaseTransaction *readWriteTransaction;
}

- (id)initWithConnection:(YapAbstractDatabaseConnection *)connection
         readTransaction:(YapAbstractDatabaseTransaction *)transaction;

- (id)initWithConnection:(YapAbstractDatabaseConnection *)connection
    readWriteTransaction:(YapAbstractDatabaseTransaction *)transaction;

- (void)handleInsertKey:(NSString *)key withObject:(id)object metadata:(id)metadata;
- (void)handleUpdateKey:(NSString *)key withObject:(id)object metadata:(id)metadata;
- (void)handleUpdateKey:(NSString *)key withMetadata:(id)metadata;
- (void)handleRemoveKey:(NSString *)key;
- (void)handleRemoveAllKeys;

- (void)commitTransaction;

@end
