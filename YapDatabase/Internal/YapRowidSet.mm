#include "YapRowidSet.h"
#include <unordered_set>

struct _YapRowidSet {
    std::unordered_set<int64_t> *rowids;
};

YapRowidSet* YapRowidSetCreate(NSUInteger capacity)
{
	YapRowidSet *set = (YapRowidSet *)malloc(sizeof(YapRowidSet));
	
	set->rowids = new std::unordered_set<int64_t>();
	if (capacity > 0) {
		set->rowids->reserve(capacity);
	}
	
	return set;
}

YapRowidSet* YapRowidSetCopy(YapRowidSet *set)
{
	if (set == NULL) return NULL;
	
	YapRowidSet *copy = (YapRowidSet *)malloc(sizeof(YapRowidSet));
	
	if (set->rowids) {
		copy->rowids = new std::unordered_set<int64_t>(*(set->rowids));
	}
	else {
		copy->rowids = new std::unordered_set<int64_t>();
	}
	
	return copy;
}

void YapRowidSetRelease(YapRowidSet *set)
{
	if (set == NULL) return;
	
	if (set->rowids) {
		free(set->rowids);
		set->rowids = NULL;
	}
	
	free(set);
}

void YapRowidSetAdd(YapRowidSet *set, int64_t rowid)
{
	set->rowids->insert(rowid);
}

void YapRowidSetRemove(YapRowidSet *set, int64_t rowid)
{
	set->rowids->erase(rowid);
}

void YapRowidSetRemoveAll(YapRowidSet *set)
{
	set->rowids->clear();
}

NSUInteger YapRowidSetCount(YapRowidSet *set)
{
	return (NSUInteger)(set->rowids->size());
}

BOOL YapRowidSetContains(YapRowidSet *set, int64_t rowid)
{
	return (set->rowids->find(rowid) != set->rowids->end());
}

void YapRowidSetEnumerate(YapRowidSet *set, void (^block)(int64_t rowid, BOOL *stop))
{
	__block BOOL stop = NO;
	
	std::unordered_set<int64_t>::iterator iterator = set->rowids->begin();
	std::unordered_set<int64_t>::iterator end = set->rowids->end();
	
	while (iterator != end)
	{
		int64_t rowid = *iterator;
		
		block(rowid, &stop);
		
		if (stop) break;
		iterator++;
	}
}
