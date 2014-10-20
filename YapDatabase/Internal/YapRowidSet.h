/**
 * Wrapper for C++ code (std::unordered_set<int64_t>)
**/

#import <Foundation/Foundation.h>

#ifndef YapDatabase_YapRowidSet_h
#define YapDatabase_YapRowidSet_h

#if defined(__cplusplus)
extern "C" {
#endif

typedef struct _YapRowidSet YapRowidSet;

YapRowidSet* YapRowidSetCreate(NSUInteger capacity);

YapRowidSet* YapRowidSetCopy(YapRowidSet *set);

void YapRowidSetRelease(YapRowidSet *set);

void YapRowidSetAdd(YapRowidSet *set, int64_t rowid);
void YapRowidSetRemove(YapRowidSet *set, int64_t rowid);
void YapRowidSetRemoveAll(YapRowidSet *set);

NSUInteger YapRowidSetCount(YapRowidSet *set);

BOOL YapRowidSetContains(YapRowidSet *set, int64_t rowid);

void YapRowidSetEnumerate(YapRowidSet *set, void (^block)(int64_t rowid, BOOL *stop));

#if defined(__cplusplus)
}
#endif

#endif
