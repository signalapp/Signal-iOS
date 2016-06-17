#import "YapDatabaseViewPage.h"
#include <vector>


@implementation YapDatabaseViewPage
{
	std::vector<int64_t> *vector;
}

- (id)init
{
	return [self initWithCapacity:0];
}

- (id)initWithCapacity:(NSUInteger)capacity
{
	if ((self = [super init]))
	{
		vector = new std::vector<int64_t>();
		
		if (capacity > 0)
			vector->reserve(capacity);
	}
	return self;
}

- (id)copyWithZone:(NSZone __unused *)zone
{
	YapDatabaseViewPage *copy = [[YapDatabaseViewPage alloc] initWithCapacity:[self count]];
	
	copy->vector->insert(copy->vector->begin(), vector->begin(), vector->end());
	
	return copy;
}

- (void)dealloc
{
	if (vector)
		delete vector;
}

- (NSData *)serialize
{
	NSUInteger count = vector->size();
	NSUInteger numBytes = count * sizeof(int64_t);
	
	int64_t *buffer = (int64_t *)malloc(numBytes);
	memcpy(buffer, vector->data(), numBytes);
	
	if (CFByteOrderGetCurrent() == CFByteOrderBigEndian)
	{
		for (NSUInteger i = 0; i < count; i++)
		{
			buffer[i] = CFSwapInt64HostToLittle(buffer[i]);
		}
	}
	
	return [NSData dataWithBytesNoCopy:buffer length:numBytes freeWhenDone:YES];
}

- (void)deserialize:(NSData *)data
{
	vector->clear();
	
	NSUInteger count = [data length] / sizeof(int64_t);
	int64_t *bytes = (int64_t *)[data bytes];
	
	if (vector->capacity() < count)
		vector->reserve(count);
	
	for (NSUInteger i = 0; i < count; i++)
	{
		int64_t rowid = bytes[i];
		
		if (CFByteOrderGetCurrent() == CFByteOrderBigEndian)
			vector->push_back(CFSwapInt64LittleToHost(rowid));
		else
			vector->push_back(rowid);
	}
}

- (NSUInteger)count
{
	return (NSUInteger)(vector->size());
}

- (int64_t)rowidAtIndex:(NSUInteger)index
{
	return vector->at(index);
}

- (void)addRowid:(int64_t)rowid
{
	vector->push_back(rowid);
}

- (void)insertRowid:(int64_t)rowid atIndex:(NSUInteger)index
{
	vector->insert(vector->begin() + index, rowid);
}

- (void)removeRowidAtIndex:(NSUInteger)index
{
	vector->erase(vector->begin() + index);
}

- (void)removeRange:(NSRange)range
{
	std::vector<int64_t>::iterator it = vector->begin();
	
	vector->erase(it+range.location, it+range.location+range.length);
}

- (void)removeAllRowids
{
	vector->clear();
}

- (void)appendPage:(YapDatabaseViewPage *)page
{
	vector->insert(vector->end(), page->vector->begin(), page->vector->end());
}

- (void)prependPage:(YapDatabaseViewPage *)page
{
	vector->insert(vector->begin(), page->vector->begin(), page->vector->end());
}

- (void)appendRange:(NSRange)range ofPage:(YapDatabaseViewPage *)page
{
	std::vector<int64_t>::iterator rangeBegin = page->vector->begin();
	std::vector<int64_t>::iterator rangeEnd;
	
	rangeBegin += range.location;
	rangeEnd = rangeBegin + range.length;
	
	vector->insert(vector->end(), rangeBegin, rangeEnd);
}

- (void)prependRange:(NSRange)range ofPage:(YapDatabaseViewPage *)page
{
	std::vector<int64_t>::iterator rangeBegin = page->vector->begin();
	std::vector<int64_t>::iterator rangeEnd;
	
	rangeBegin += range.location;
	rangeEnd = rangeBegin + range.length;
	
	vector->insert(vector->begin(), rangeBegin, rangeEnd);
}

- (BOOL)getIndex:(NSUInteger *)indexPtr ofRowid:(int64_t)rowid
{
	std::vector<int64_t>::iterator iterator = vector->begin();
	std::vector<int64_t>::iterator end = vector->end();
	
	NSUInteger index = 0;
	
	while (iterator != end)
	{
		if (*iterator == rowid)
		{
			if (indexPtr) *indexPtr = index;
			return YES;
		}
		
		iterator++;
		index++;
	}
	
	if (indexPtr) *indexPtr = 0;
	return NO;
}

- (void)enumerateRowidsUsingBlock:(void (^)(int64_t rowid, NSUInteger idx, BOOL *stop))block
{
	[self enumerateRowidsWithOptions:0 usingBlock:block];
}

- (void)enumerateRowidsWithOptions:(NSEnumerationOptions)options
                        usingBlock:(void (^)(int64_t rowid, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	if ((options & NSEnumerationReverse) == 0)
	{
		// Forward enumeration
		
		std::vector<int64_t>::iterator iterator = vector->begin();
		std::vector<int64_t>::iterator end = vector->end();
		
		NSUInteger index = 0;
		BOOL stop = NO;
		
		while (iterator != end)
		{
			int64_t rowid = *iterator;
			
			block(rowid, index, &stop);
			
			if (stop) break;
			
			iterator++;
			index++;
		}
	}
	else
	{
		// Reverse enumeration
		
		std::vector<int64_t>::reverse_iterator iterator = vector->rbegin();
		std::vector<int64_t>::reverse_iterator end = vector->rend();
		
		NSUInteger index = vector->size() - 1;
		BOOL stop = NO;
		
		while (iterator != end)
		{
			int64_t rowid = *iterator;
			
			block(rowid, index, &stop);
			
			if (stop) break;
			
			iterator++;
			index--;
		}
	}
}

- (void)enumerateRowidsWithOptions:(NSEnumerationOptions)options
                             range:(NSRange)range
                        usingBlock:(void (^)(int64_t rowid, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	if ((options & NSEnumerationReverse) == 0)
	{
		// Forward enumeration
		
		std::vector<int64_t>::iterator iterator = vector->begin();
		std::vector<int64_t>::iterator end;
		
		iterator += range.location;
		end = iterator + range.length;
		
		NSUInteger index = range.location;
		BOOL stop = NO;
		
		while (iterator != end)
		{
			int64_t rowid = *iterator;
			
			block(rowid, index, &stop);
			
			if (stop) break;
			
			iterator++;
			index++;
		}
	}
	else
	{
		// Reverse enumeration
		
		std::vector<int64_t>::reverse_iterator iterator = vector->rbegin();
		std::vector<int64_t>::reverse_iterator end;
		
		iterator += (vector->size() - (range.location + range.length));
		end = iterator + range.length;
		
		NSUInteger index = range.location + range.length - 1;
		BOOL stop = NO;
		
		while (iterator != end)
		{
			int64_t rowid = *iterator;
			
			block(rowid, index, &stop);
			
			if (stop) break;
			
			iterator++;
			index--;
		}
	}
}

- (NSString *)debugDescription
{
	NSMutableString *string = [NSMutableString stringWithCapacity:100];
	[string appendFormat:@"<YapDatabaseViewPage[%p] count=%lu {\n", self, (unsigned long)[self count]];
	
	std::vector<int64_t>::iterator iterator = vector->begin();
	std::vector<int64_t>::iterator end = vector->end();
	
	NSUInteger index = 0;
	
	while (iterator != end)
	{
		[string appendFormat:@"  %lu: %lld\n", (unsigned long)index, *iterator];
		
		iterator++;
		index++;
	}
	
	[string appendFormat:@"}>"];
	
	return string;
}

@end
