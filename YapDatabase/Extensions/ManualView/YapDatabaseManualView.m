#import "YapDatabaseManualView.h"
#import "YapDatabaseManualViewPrivate.h"


@implementation YapDatabaseManualView

- (instancetype)init
{
	return [self initWithVersionTag:nil options:nil];
}

- (instancetype)initWithVersionTag:(NSString *)inVersionTag
                           options:(YapDatabaseViewOptions *)inOptions
{
	if ((self = [super initWithVersionTag:inVersionTag options:inOptions]))
	{
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseExtension Protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
	return [[YapDatabaseManualViewConnection alloc] initWithParent:self databaseConnection:databaseConnection];
}

@end
