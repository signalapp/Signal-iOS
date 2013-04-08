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
@public
	YapAbstractDatabaseView *abstractView;
	
@protected
	
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapAbstractDatabaseViewTransaction () {
@protected
	__unsafe_unretained YapAbstractDatabaseViewConnection *viewConnection;
	__unsafe_unretained YapAbstractDatabaseConnection *databaseConnection;
	
	__unsafe_unretained YapAbstractDatabaseTransaction *readTransaction;
	__unsafe_unretained YapAbstractDatabaseTransaction *readWriteTransaction;
}

- (id)initWithViewConnection:(YapAbstractDatabaseViewConnection *)viewConnection
		  databaseConnection:(YapAbstractDatabaseConnection *)databaseConnection
             readTransaction:(YapAbstractDatabaseTransaction *)transaction;

- (id)initWithViewConnection:(YapAbstractDatabaseViewConnection *)viewConnection
		  databaseConnection:(YapAbstractDatabaseConnection *)databaseConnection
        readWriteTransaction:(YapAbstractDatabaseTransaction *)transaction;

- (void)handleInsertKey:(NSString *)key withObject:(id)object metadata:(id)metadata;
- (void)handleUpdateKey:(NSString *)key withObject:(id)object metadata:(id)metadata;
- (void)handleUpdateKey:(NSString *)key withMetadata:(id)metadata;
- (void)handleRemoveKey:(NSString *)key;
- (void)handleRemoveAllKeys;

- (void)commitTransaction;

@end
