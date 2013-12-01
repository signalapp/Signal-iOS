/**
 * There are a LOT of conversions from NSString to char array.
 * This happens in almost every method, where we bind text to prepared sqlite3 statements.
 * 
 * It is inefficient to use [key UTF8String] for these situations.
 * The Apple documentation is very explicit concerning the UTF8String method:
 * 
 * > The returned C string is automatically freed just as a returned object would be released;
 * > you should copy the C string if [you need] to store it outside of the
 * > autorelease context in which the C string is created.
 * 
 * In other words, the UTF8String method does a malloc for character buffer, copies the characters,
 * and autoreleases the buffer (just like an autoreleased NSData instance).
 * 
 * Thus we suffer a bunch of malloc's if we use UTF8String.
 * 
 * Considering that almost all keys are likely to be relatively small,
 * a much faster technique is to use the stack instead of the heap (with obvious precautions, see below).
 * 
 * Note: This technique ONLY applies to key names and collection names.
 * It does NOT apply to object/primitiveData or metadata. Those are binded to sqlite3 statements using binary blobs.
**/


/**
 * We must be cautious and conservative so as to avoid stack overflow.
 * This is possibe if really huge key names or collection names are used.
 *
 * The number below represents the largest amount of memory (in bytes) that will be allocated on the stack per string.
**/
#define YapDatabaseStringMaxStackLength (1024 * 4)

/**
 * Struct designed to be allocated on the stack.
 * You then use the inline functions below to "setup" and "teardown" the struct.
 * For example:
 * 
 * > YapDatabaseString myKeyChar;
 * > MakeYapDatabaseString(&myKeyChar, myNSStringKey);
 * > ...
 * > sqlite3_bind_text(statement, position, myKeyChar.str, myKeyChar.length, SQLITE_STATIC);
 * > ...
 * > sqlite3_clear_bindings(statement);
 * > sqlite3_reset(statement);
 * > FreeYapDatabaseString(&myKeyChar);
 *
 * There are 2 "public" fields:
 * str    - Pointer to the char[] string.
 * length - Represents the length (in bytes) of the char[] str (excluding the NULL termination byte, as usual).
 * 
 * The other 2 "private" fields are for internal use:
 * strStack - If the string doesn't exceed YapDatabaseStringMaxStackLength,
 *            then the bytes are copied here (onto stack storage), and str actually points to strStack.
 * strHeap  - If the string exceeds YapDatabaseStringMaxStackLength,
 *            the space is allocated on the heap, strHeap holds the pointer, and str has the same pointer.
 * 
 * Thus the "setup" and "teardown" methods below will automatically switch to heap storage (just like UTF8String),
 * if the key/collection name is too long, and performance will be equivalent.
 * But in the common case of short key/collection names, we can skip the more expensive heap allocation/deallocation.
**/
struct YapDatabaseString {
	int length;
	char strStack[YapDatabaseStringMaxStackLength];
	char *strHeap;
	char *str; // Pointer to either strStack or strHeap
};
typedef struct YapDatabaseString YapDatabaseString;

/**
 * Initializes the YapDatabaseString structure.
 * It will automatically use heap storage if the given NSString is too long.
 * 
 * This method should always be balanced with a call to FreeYapDatabaseString.
**/
NS_INLINE void MakeYapDatabaseString(YapDatabaseString *dbStr, NSString *nsStr)
{
	if (nsStr)
	{
		// We convert to int because the sqlite3_bind_text() function expects an int parameter.
		// So we can change it to int here, or we can cast everywhere throughout the project.
		
		dbStr->length = (int)[nsStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
	
		if ((dbStr->length + 1) <= YapDatabaseStringMaxStackLength)
		{
			dbStr->strHeap = NULL;
			dbStr->str = dbStr->strStack;
		}
		else
		{
			dbStr->strHeap = (char *)malloc((dbStr->length + 1));
			dbStr->str = dbStr->strHeap;
		}
	
		[nsStr getCString:dbStr->str maxLength:(dbStr->length + 1) encoding:NSUTF8StringEncoding];
	}
	else
	{
		dbStr->length = 0;
		dbStr->strHeap = NULL;
		dbStr->str = NULL;
	}
}

/**
 * If heap storage was needed (because the string length exceeded YapDatabaseStringMaxStackLength),
 * this method frees the heap allocated memory.
 *
 * In the common case of stack storage, strHeap will be NULL, and this method is essentially a no-op.
 * 
 * This method should be invoked AFTER sqlite3_clear_bindings (assuming SQLITE_STATIC is used).
**/
NS_INLINE void FreeYapDatabaseString(YapDatabaseString *dbStr)
{
	if (dbStr->strHeap)
	{
		free(dbStr->strHeap);
		dbStr->strHeap = NULL;
		dbStr->str = NULL;
	}
}
