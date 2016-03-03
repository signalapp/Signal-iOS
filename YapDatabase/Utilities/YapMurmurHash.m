#import "YapMurmurHash.h"

/**
 * MurmurHash2 was written by Austin Appleby, and is placed in the public domain.
 * http://code.google.com/p/smhasher
**/
NSUInteger YapMurmurHash2(NSUInteger hash1, NSUInteger hash2)
{
	if (NSUIntegerMax == UINT32_MAX) // Should be optimized out via compiler since these are constants
	{
		// MurmurHash2 (32-bit)
		//
		// uint32_t MurmurHash2 ( const void * key, int len, uint32_t seed )
		//
		// Normally one would pass a chunk of data ('key') and associated data chunk length ('len').
		// Instead we're going to use our 2 hashes.
		// And we're going to randomly make up a 'seed'.
		
		const uint32_t seed = 0xa2f1b6f; // Some random value I made up
		const uint32_t len = 8;          // 2 hashes, each 4 bytes = 8 bytes
		
		// 'm' and 'r' are mixing constants generated offline.
		// They're not really 'magic', they just happen to work well.
		
		const uint32_t m = 0x5bd1e995;
		const int r = 24;
		
		// Initialize the hash to a 'random' value
		
		uint32_t h = seed ^ len;
		uint32_t k;
		
		// Mix hash1
		
		k = hash1;
		
		k *= m;
		k ^= k >> r;
		k *= m;
		
		h *= m;
		h ^= k;
		
		// Mix khash
		
		k = hash2;
		
		k *= m;
		k ^= k >> r;
		k *= m;
		
		h *= m;
		h ^= k;
		
		// Do a few final mixes of the hash to ensure the last few
		// bytes are well-incorporated.
		
		h ^= h >> 13;
		h *= m;
		h ^= h >> 15;
		
		return (NSUInteger)h;
	}
	else
	{
		// MurmurHash2 (64-bit)
		//
		// uint64_t MurmurHash64A ( const void * key, int len, uint64_t seed )
		//
		// Normally one would pass a chunk of data ('key') and associated data chunk length ('len').
		// Instead we're going to use our 3 hashes.
		// And we're going to randomly make up a 'seed'.
		
		const uint32_t seed = 0xa2f1b6f; // Some random value I made up
		const uint32_t len = 16;         // 2 hashes, each 8 bytes = 16 bytes
		
		// 'm' and 'r' are mixing constants generated offline.
		// They're not really 'magic', they just happen to work well.
		
		const uint64_t m = 0xc6a4a7935bd1e995LLU;
		const int r = 47;
		
		// Initialize the hash to a 'random' value
		
		uint64_t h = seed ^ (len * m);
		uint64_t k;
		
		// Mix hash1
		
		k = hash1;
		
		k *= m;
		k ^= k >> r;
		k *= m;
		
		h ^= k;
		h *= m;
		
		// Mix hash2
		
		k = hash2;
		
		k *= m;
		k ^= k >> r;
		k *= m;
		
		h ^= k;
		h *= m;
		
		// Do a few final mixes of the hash to ensure the last few
		// bytes are well-incorporated.
		
		h ^= h >> r;
		h *= m;
		h ^= h >> r;
		
		return (NSUInteger)h;
	}
}


/**
 * MurmurHash2 was written by Austin Appleby, and is placed in the public domain.
 * http://code.google.com/p/smhasher
**/
NSUInteger YapMurmurHash3(NSUInteger hash1, NSUInteger hash2, NSUInteger hash3)
{
	if (NSUIntegerMax == UINT32_MAX) // Should be optimized out via compiler since these are constants
	{
		// MurmurHash2 (32-bit)
		//
		// uint32_t MurmurHash2 ( const void * key, int len, uint32_t seed )
		// 
		// Normally one would pass a chunk of data ('key') and associated data chunk length ('len').
		// Instead we're going to use our 3 hashes.
		// And we're going to randomly make up a 'seed'.
		
		const uint32_t seed = 0xa2f1b6f; // Some random value I made up
		const uint32_t len = 12;         // 3 hashes, each 4 bytes = 12 bytes
		
		// 'm' and 'r' are mixing constants generated offline.
		// They're not really 'magic', they just happen to work well.
		
		const uint32_t m = 0x5bd1e995;
		const int r = 24;
		
		// Initialize the hash to a 'random' value
		
		uint32_t h = seed ^ len;
		uint32_t k;
		
		// Mix hash1
		
		k = hash1;
		
		k *= m;
		k ^= k >> r;
		k *= m;
		
		h *= m;
		h ^= k;
		
		// Mix hash2
		
		k = hash2;
		
		k *= m;
		k ^= k >> r;
		k *= m;
		
		h *= m;
		h ^= k;
		
		// Mix hash3
		
		k = hash3;
		
		k *= m;
		k ^= k >> r;
		k *= m;
		
		h *= m;
		h ^= k;
		
		// Do a few final mixes of the hash to ensure the last few
		// bytes are well-incorporated.
		
		h ^= h >> 13;
		h *= m;
		h ^= h >> 15;
		
		return (NSUInteger)h;
	}
	else
	{
		// MurmurHash2 (64-bit)
		// 
		// uint64_t MurmurHash64A ( const void * key, int len, uint64_t seed )
		// 
		// Normally one would pass a chunk of data ('key') and associated data chunk length ('len').
		// Instead we're going to use our 3 hashes.
		// And we're going to randomly make up a 'seed'.
		
		const uint32_t seed = 0xa2f1b6f; // Some random value I made up
		const uint32_t len = 24;         // 3 hashes, each 8 bytes = 24 bytes
		
		// 'm' and 'r' are mixing constants generated offline.
		// They're not really 'magic', they just happen to work well.
		
		const uint64_t m = 0xc6a4a7935bd1e995LLU;
		const int r = 47;
		
		// Initialize the hash to a 'random' value
		
		uint64_t h = seed ^ (len * m);
		uint64_t k;
		
		// Mix hash1
		
		k = hash1;
		
		k *= m; 
		k ^= k >> r; 
		k *= m; 
		
		h ^= k;
		h *= m;
		
		// Mix hash2
		
		k = hash2;
		
		k *= m; 
		k ^= k >> r; 
		k *= m; 
		
		h ^= k;
		h *= m;
		
		// Mix hash3
		
		k = hash3;
		
		k *= m; 
		k ^= k >> r; 
		k *= m; 
		
		h ^= k;
		h *= m;
		
		// Do a few final mixes of the hash to ensure the last few
		// bytes are well-incorporated.
		
		h ^= h >> r;
		h *= m;
		h ^= h >> r;
		
		return (NSUInteger)h;
	}
}

/**
 * MurmurHash2 was written by Austin Appleby, and is placed in the public domain.
 * http://code.google.com/p/smhasher
**/
NSUInteger YapMurmurHashData(NSData *inData)
{
	if (NSUIntegerMax == UINT32_MAX) // Should be optimized out via compiler since these are constants
	{
		return (NSUInteger)YapMurmurHashData_32(inData);
	}
	else
	{
		return (NSUInteger)YapMurmurHashData_64(inData);
	}
}

uint32_t YapMurmurHashData_32(NSData *inData)
{
	// MurmurHash2 (32-bit)
	//
	// uint32_t MurmurHash2 ( const void * key, int len, uint32_t seed )
	//
	// The 'key' and 'len' parameters come from the passed data.
	// And we're going to randomly make up a 'seed'.
	
	const unsigned char *data = (const unsigned char *)[inData bytes];
	uint32_t len = (uint32_t)[inData length];
	
	const uint32_t seed = 0xa2f1b6f; // Some random value I made up
	
	// 'm' and 'r' are mixing constants generated offline.
	// They're not really 'magic', they just happen to work well.
	
	const uint32_t m = 0x5bd1e995;
	const int r = 24;
	
	// Initialize the hash to a 'random' value
	
	uint32_t h = seed ^ len;
	
	// Mix 4 bytes at a time into the hash
	
	while (len >= 4)
	{
		uint32_t k = *(uint32_t*)data;
		
		k *= m;
		k ^= k >> r;
		k *= m;
		
		h *= m;
		h ^= k;
		
		data += 4;
		len -= 4;
	}
	
	// Handle the last few bytes of the input data
	
	switch (len)
	{
		case 3: h ^= data[2] << 16;
		case 2: h ^= data[1] << 8;
		case 1: h ^= data[0];
			h *= m;
	};
	
	// Do a few final mixes of the hash to ensure the last few
	// bytes are well-incorporated.
	
	h ^= h >> 13;
	h *= m;
	h ^= h >> 15;
	
	return h;
}

uint64_t YapMurmurHashData_64(NSData *inData)
{
	// MurmurHash2 (64-bit)
	//
	// uint64_t MurmurHash64A ( const void * key, int len, uint64_t seed )
	//
	// he 'key' and 'len' parameters come from the passed data.
	// And we're going to randomly make up a 'seed'.
	
	const uint32_t seed = 0xa2f1b6f; // Some random value I made up
	
	int len = (int)[inData length];
	
	const uint64_t * data = (const uint64_t *)[inData bytes];
	const uint64_t * end = data + (len/8);
	
	// 'm' and 'r' are mixing constants generated offline.
	// They're not really 'magic', they just happen to work well.
	
	const uint64_t m = 0xc6a4a7935bd1e995LLU;
	const int r = 47;
	
	// Initialize the hash to a 'random' value
	
	uint64_t h = seed ^ (len * m);
	
	// Mix 8 bytes at a time into the hash
	
	while(data != end)
	{
		uint64_t k = *data++;
		
		k *= m;
		k ^= k >> r;
		k *= m;
		
		h ^= k;
		h *= m;
	}
	
	// Handle the last few bytes of the input data
	
	const unsigned char *data2 = (const unsigned char *)data;
	
	switch (len & 7)
	{
		case 7: h ^= (uint64_t)(data2[6]) << 48;
		case 6: h ^= (uint64_t)(data2[5]) << 40;
		case 5: h ^= (uint64_t)(data2[4]) << 32;
		case 4: h ^= (uint64_t)(data2[3]) << 24;
		case 3: h ^= (uint64_t)(data2[2]) << 16;
		case 2: h ^= (uint64_t)(data2[1]) << 8;
		case 1: h ^= (uint64_t)(data2[0]);
			h *= m;
	};
	
	// Do a few final mixes of the hash to ensure the last few
	// bytes are well-incorporated.
	
	h ^= h >> r;
	h *= m;
	h ^= h >> r;
	
	return h;
}
