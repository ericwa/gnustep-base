/* A fast (Inline) map/hash table implementation for NSObjects
 * Copyright (C) 1998,1999  Free Software Foundation, Inc.
 * 
 * Author:	Richard Frith-Macdonald <richard@brainstorm.co.uk>
 * Created:	Thu Oct  1 09:30:00 GMT 1998
 * 
 * Based on original o_map code by Albin L. Jones <Albin.L.Jones@Dartmouth.EDU>
 *
 * This file is part of the GNUstep Base Library.
 * 
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 * 
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free
 * Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02111 USA. */

#import	<GNUstepBase/GSVersionMacros.h>

#if	OS_API_VERSION(GS_API_NONE,GS_API_LATEST)

#include <Foundation/NSObject.h>
#include <Foundation/NSZone.h>

#if	defined(__cplusplus)
extern "C" {
#endif

/* To easily un-inline functions for debugging */
#ifndef	INLINE
#define INLINE inline
#endif

/*
 *	This file should be INCLUDED in files wanting to use the GSIMap
 *	functions - these are all declared inline for maximum performance.
 *
 *	The file including this one may predefine some macros to alter
 *	the behaviour
 *
 *	GSI_MAP_HAS_VALUE
 *		If defined as 0, then this becomes a hash table rather than
 *		a map table.
 *
 *	GSI_MAP_RETAIN_KEY()
 *		Macro to retain the key item in a map or hash table.
 *
 *	GSI_MAP_RETAIN_VAL()
 *		Macro to retain the value item in a map table.
 *
 *	GSI_MAP_RELEASE_KEY()
 *		Macro to release the key item in a map or hash table.
 *
 *	GSI_MAP_RELEASE_VAL()
 *		Macro to release the value item in a map table.
 *
 *	GSI_MAP_HASH()
 *		Macro to get the hash of a key item.
 *
 *	GSI_MAP_EQUAL()
 *		Macro to compare two key items for equality - produces zero
 *		if the items are not equal.
 *
 *	GSI_MAP_EXTRA
 *		If this value is defined, there is an 'extra' field in each
 *		map table whose type is that specified by the value of the
 *		preprocessor constant. This field can be used
 *		to store additional information for the map.
 *
 *	GSI_MAP_NOCLEAN
 *		Define this to a non-zero integer value if the map keys and
 *		values do not need to be released when the map is emptied.
 *		This permits some optimisation.
 *
 */

#ifndef	GSI_MAP_HAS_VALUE
#define	GSI_MAP_HAS_VALUE	1
#endif

#ifndef	GSI_MAP_RETAIN_KEY
#define	GSI_MAP_RETAIN_KEY(M, X)	[(X).obj retain]
#endif
#ifndef	GSI_MAP_RELEASE_KEY
#define	GSI_MAP_RELEASE_KEY(M, X)	[(X).obj release]
#endif
#ifndef	GSI_MAP_RETAIN_VAL
#define	GSI_MAP_RETAIN_VAL(M, X)	[(X).obj retain]
#endif
#ifndef	GSI_MAP_RELEASE_VAL
#define	GSI_MAP_RELEASE_VAL(M, X)	[(X).obj release]
#endif
#ifndef	GSI_MAP_HASH
#define	GSI_MAP_HASH(M, X)		[(X).obj hash]
#endif
#ifndef	GSI_MAP_EQUAL
#define	GSI_MAP_EQUAL(M, X, Y)		[(X).obj isEqual: (Y).obj]
#endif

/*
 *      If there is no bitmask defined to supply the types that
 *      may be used as keys in the  map, default to permitting all types.
 */
#ifndef GSI_MAP_KTYPES
#define GSI_MAP_KTYPES        GSUNION_ALL
#endif

/*
 *	Set up the name of the union to store keys.
 */
#ifdef	GSUNION
#undef	GSUNION
#endif
#define	GSUNION	GSIMapKey

/*
 *	Set up the types that will be storable in the union.
 *	See 'GSUnion.h' for further information.
 */
#ifdef	GSUNION_TYPES
#undef	GSUNION_TYPES
#endif
#define	GSUNION_TYPES	GSI_MAP_KTYPES
#ifdef	GSUNION_EXTRA
#undef	GSUNION_EXTRA
#endif
#ifdef	GSI_MAP_KEXTRA
#define	GSUNION_EXTRA	GSI_MAP_KEXTRA
#endif

/*
 *	Generate the union typedef
 */
#include <GNUstepBase/GSUnion.h>


#if (GSI_MAP_KTYPES) & GSUNION_OBJ
#define GSI_MAP_CLEAR_KEY(node)  node->key.obj = nil
#elif  (GSI_MAP_KTYPES) & GSUNION_PTR
#define GSI_MAP_CLEAR_KEY(node)  node->key.ptr = 0
#else
#define GSI_MAP_CLEAR_KEY(node)  
#endif

/*
 *      If there is no bitmask defined to supply the types that
 *      may be used as values in the  map, default to permitting all types.
 */
#ifndef GSI_MAP_VTYPES
#define GSI_MAP_VTYPES        GSUNION_ALL
#endif

/*
 *	Set up the name of the union to store map values.
 */
#ifdef	GSUNION
#undef	GSUNION
#endif
#define	GSUNION	GSIMapVal

/*
 *	Set up the types that will be storable in the union.
 *	See 'GSUnion.h' for further information.
 */
#ifdef	GSUNION_TYPES
#undef	GSUNION_TYPES
#endif
#define	GSUNION_TYPES	GSI_MAP_VTYPES
#ifdef	GSUNION_EXTRA
#undef	GSUNION_EXTRA
#endif
#ifdef	GSI_MAP_VEXTRA
#define	GSUNION_EXTRA	GSI_MAP_VEXTRA
#endif

#ifndef	GSI_MAP_SIMPLE
#define	GSI_MAP_SIMPLE	0
#endif

/*
 *	Generate the union typedef
 */
#include <GNUstepBase/GSUnion.h>

#if (GSI_MAP_VTYPES) & GSUNION_OBJ
#define GSI_MAP_CLEAR_VAL(node)  node->value.obj = nil
#elif  (GSI_MAP_VTYPES) & GSUNION_PTR
#define GSI_MAP_CLEAR_VAL(node)  node->value.ptr = 0
#else
#define GSI_MAP_CLEAR_VAL(node)  
#endif

/*
 *  Description of the datastructure
 *  --------------------------------
 *  The complete GSIMap implementation can be viewed in two different ways,
 *
 *  (1) viewed as a structure to add and retrieve elements
 *  (2) viewed as a memory management structure to facilitate (1)
 *
 *  The first view is best described as follows:
 *
 *   _GSIMapTable   ----->  C-array of buckets 
 *
 *  Where each bucket contains a count (nodeCount), describing the number
 *  of nodes in the bucket and a pointer (firstNode) to a single linked
 *  list of nodes.
 *  
 *  The second view is slightly more complicated.
 *  The individual nodes are allocated and deallocated in chunks.
 *  In order to keep track of this we have:
 *
 *   _GSIMapTable   ----->  C-array of chunks
 *
 *  Where each chunk points to a C-array of nodes.
 *  Also the _GSIMapTable contains a pointer to the free nodes
 *
 *   _GSIMapTable   ----->  single linked list of free nodes
 *
 *  Consequence of this is that EVERY node is part of a single linked list.
 *  Either it is in use and reachable from a bucket, or it is part of the
 *  freeNodes linked list.
 *  Also EVERY node is part of chunk, due to the way the nodes are allocated.
 *
 *  A rough picture is include below:
 *   
 *  
 *   This is the map                C - array of the buckets
 *   +---------------+             +---------------+
 *   | _GSIMapTable  |      /----->| nodeCount     |  
 *   |---------------|     /       | firstNode ----+--\  
 *   | buckets    ---+----/        | ..........    |  |
 *   | bucketCount  =| size of --> | nodeCount     |  |
 *   | nodeChunks ---+--\          | firstNode     |  |
 *   | chunkCount  =-+\ |          |     .         |  | 
 *   |   ....        || |          |     .         |  |
 *   +---------------+| |          | nodeCount     |  |
 *                    | |          | fistNode      |  | 
 *                    / |          +---------------+  | 
 *         ----------   v                             v
 *       /       +----------+      +---------------------------+ 
 *       |       |  * ------+----->| Node1 | Node2 | Node3 ... | a chunk
 *   chunkCount  |  * ------+--\   +---------------------------+
 *  is size of = |  .       |   \  +-------------------------------+
 *               |  .       |    ->| Node n | Node n + 1 | ...     | another
 *               +----------+      +-------------------------------+
 *               array pointing
 *               to the chunks
 *
 *
 *  NOTES on the way chunks are allocated
 *  -------------------------------------
 *  Chunks are allocated when needed, that is a new chunk is allocated
 *  whenever the freeNodes list is empty and a new node is required.
 *  In gnustep-base-1.9.0 the size of the new chunk is calculated as
 *  roughly 3/4 of the number of nodes in use.
 *  The problem with this approach is that it can lead to unnecessary
 *  address space fragmentation.  So in this version the algorithm we
 *  will use the 3/4 rule until the nodeCount reaches the "increment"
 *  member variable.
 *  If nodeCount is bigger than the "increment" it will allocate chunks
 *  of size "increment".
 */

typedef struct _GSIMapTable GSIMapTable_t;
typedef struct _GSIMapBucket GSIMapBucket_t;
typedef struct _GSIMapNode GSIMapNode_t;

typedef GSIMapTable_t *GSIMapTable;
typedef GSIMapBucket_t *GSIMapBucket;
typedef GSIMapNode_t *GSIMapNode;

struct	_GSIMapNode {
  GSIMapNode	nextInBucket;	/* Linked list of bucket.	*/
  GSIMapKey	key;
#if	GSI_MAP_HAS_VALUE
  GSIMapVal	value;
#endif
};

struct	_GSIMapBucket {
  size_t	nodeCount;	/* Number of nodes in bucket.	*/
  GSIMapNode	firstNode;	/* The linked list of nodes.	*/
};

struct	_GSIMapTable {
  NSZone	*zone;
  size_t	nodeCount;	/* Number of used nodes in map.	*/
  size_t	bucketCount;	/* Number of buckets in map.	*/
  GSIMapBucket	buckets;	/* Array of buckets.		*/
  GSIMapNode	freeNodes;	/* List of unused nodes.	*/
  size_t	chunkCount;	/* Number of chunks in array.	*/
  GSIMapNode	*nodeChunks;	/* Chunks of allocated memory.	*/
  size_t	increment;
#ifdef	GSI_MAP_EXTRA
  GSI_MAP_EXTRA	extra;
#endif
};

typedef struct	_GSIMapEnumerator {
  GSIMapTable	map;		/* the map being enumerated.	*/
  GSIMapNode	node;		/* The next node to use.	*/
  size_t	bucket;		/* The next bucket to use.	*/
} *_GSIE;

#ifdef	GSI_MAP_ENUMERATOR
typedef GSI_MAP_ENUMERATOR	GSIMapEnumerator_t;
#else
typedef struct _GSIMapEnumerator GSIMapEnumerator_t;
#endif
typedef GSIMapEnumerator_t	*GSIMapEnumerator;

static INLINE GSIMapBucket
GSIMapPickBucket(unsigned hash, GSIMapBucket buckets, size_t bucketCount)
{
  return buckets + hash % bucketCount;
}

static INLINE GSIMapBucket
GSIMapBucketForKey(GSIMapTable map, GSIMapKey key)
{
  return GSIMapPickBucket(GSI_MAP_HASH(map, key),
    map->buckets, map->bucketCount);
}

static INLINE void
GSIMapLinkNodeIntoBucket(GSIMapBucket bucket, GSIMapNode node)
{
  node->nextInBucket = bucket->firstNode;
  bucket->firstNode = node;
}

static INLINE void
GSIMapUnlinkNodeFromBucket(GSIMapBucket bucket, GSIMapNode node)
{
  if (node == bucket->firstNode)
    {
      bucket->firstNode = node->nextInBucket;
    }
  else
    {
      GSIMapNode	tmp = bucket->firstNode;

      while (tmp->nextInBucket != node)
	{
	  tmp = tmp->nextInBucket;
	}
      tmp->nextInBucket = node->nextInBucket;
    }
  node->nextInBucket = 0;
}

static INLINE void
GSIMapAddNodeToBucket(GSIMapBucket bucket, GSIMapNode node)
{
  GSIMapLinkNodeIntoBucket(bucket, node);
  bucket->nodeCount += 1;
}

static INLINE void
GSIMapAddNodeToMap(GSIMapTable map, GSIMapNode node)
{
  GSIMapBucket	bucket;

  bucket = GSIMapBucketForKey(map, node->key);
  GSIMapAddNodeToBucket(bucket, node);
  map->nodeCount++;
}

static INLINE void
GSIMapRemoveNodeFromBucket(GSIMapBucket bucket, GSIMapNode node)
{
  bucket->nodeCount--;
  GSIMapUnlinkNodeFromBucket(bucket, node);
}

static INLINE void
GSIMapRemoveNodeFromMap(GSIMapTable map, GSIMapBucket bkt, GSIMapNode node)
{
  map->nodeCount--;
  GSIMapRemoveNodeFromBucket(bkt, node);
}

static INLINE void
GSIMapRemangleBuckets(GSIMapTable map,
  GSIMapBucket old_buckets, size_t old_bucketCount,
  GSIMapBucket new_buckets, size_t new_bucketCount)
{
  while (old_bucketCount-- > 0)
    {
      GSIMapNode	node;

      while ((node = old_buckets->firstNode) != 0)
	{
	  GSIMapBucket	bkt;

	  GSIMapRemoveNodeFromBucket(old_buckets, node);
	  bkt = GSIMapPickBucket(GSI_MAP_HASH(map, node->key),
	    new_buckets, new_bucketCount);
	  GSIMapAddNodeToBucket(bkt, node);
	}
      old_buckets++;
    }
}

static INLINE void
GSIMapMoreNodes(GSIMapTable map, unsigned required)
{
  GSIMapNode	*newArray;
  size_t	arraySize = (map->chunkCount+1)*sizeof(GSIMapNode);

#if	GS_WITH_GC == 1
  /*
   * Our nodes may be allocated from the atomic zone - but we don't want
   * them freed - so we must keep the array of pointers to memory chunks in
   * the default zone
   */
  if (map->zone == GSAtomicMallocZone())
    {
      newArray = (GSIMapNode*)NSZoneMalloc(NSDefaultMallocZone(), arraySize);
    }
  else
#endif
  newArray = (GSIMapNode*)NSZoneMalloc(map->zone, arraySize);
  if (newArray)
    {
      GSIMapNode	newNodes;
      size_t		chunkCount;
      size_t		chunkSize;

      if (map->nodeChunks != 0)
	{
	  memcpy(newArray, map->nodeChunks, (map->chunkCount)*sizeof(GSIMapNode));
	  NSZoneFree(map->zone, map->nodeChunks);
	}
      map->nodeChunks = newArray;

      if (required == 0)
	{
	  if (map->chunkCount == 0)
	    {
	      chunkCount = map->bucketCount > 1 ? map->bucketCount : 2;
	    }
	  else
	    {
	      chunkCount = ((map->nodeCount>>2)+1)<<1;
	    }
	}
      else
	{
	  chunkCount = required;
	}
      chunkSize = chunkCount * sizeof(GSIMapNode_t);
      newNodes = (GSIMapNode)NSZoneMalloc(map->zone, chunkSize);
      if (newNodes)
	{
	  map->nodeChunks[map->chunkCount++] = newNodes;
	  newNodes[--chunkCount].nextInBucket = map->freeNodes;
	  while (chunkCount--)
	    {
	      newNodes[chunkCount].nextInBucket = &newNodes[chunkCount+1];
	    }
	  map->freeNodes = newNodes;
	}
    }
}

#if	GSI_MAP_HAS_VALUE
static INLINE GSIMapNode
GSIMapNewNode(GSIMapTable map, GSIMapKey key, GSIMapVal value)
{
  GSIMapNode	node = map->freeNodes;

  if (node == 0)
    {
      GSIMapMoreNodes(map, map->nodeCount < map->increment ? 0: map->increment);
      node = map->freeNodes;
      if (node == 0)
	{
	  return 0;
	}
    }

  map->freeNodes = node->nextInBucket;
  node->key = key;
  node->value = value;
  node->nextInBucket = 0;

  return node;
}
#else
static INLINE GSIMapNode
GSIMapNewNode(GSIMapTable map, GSIMapKey key)
{
  GSIMapNode	node = map->freeNodes;

  if (node == 0)
    {
      GSIMapMoreNodes(map, map->nodeCount < map->increment ? 0: map->increment);
      node = map->freeNodes;
      if (node == 0)
	{
	  return 0;
	}
    }

  map->freeNodes = node->nextInBucket;
  node->key = key;
  node->nextInBucket = 0;
  return node;
}
#endif

static INLINE void
GSIMapFreeNode(GSIMapTable map, GSIMapNode node)
{
  GSI_MAP_RELEASE_KEY(map, node->key);
  GSI_MAP_CLEAR_KEY(node);
#if	GSI_MAP_HAS_VALUE
  GSI_MAP_RELEASE_VAL(map, node->value);
  GSI_MAP_CLEAR_VAL(node);
#endif
  
  node->nextInBucket = map->freeNodes;
  map->freeNodes = node;
}

static INLINE GSIMapNode 
GSIMapNodeForKeyInBucket(GSIMapTable map, GSIMapBucket bucket, GSIMapKey key)
{
  GSIMapNode	node = bucket->firstNode;

  while ((node != 0) && GSI_MAP_EQUAL(map, node->key, key) == NO)
    {
      node = node->nextInBucket;
    }
  return node;
}

static INLINE GSIMapNode 
GSIMapNodeForKey(GSIMapTable map, GSIMapKey key)
{
  GSIMapBucket	bucket;
  GSIMapNode	node;

  if (map->nodeCount == 0)
    {
      return 0;
    }
  bucket = GSIMapBucketForKey(map, key);
  node = GSIMapNodeForKeyInBucket(map, bucket, key);
  return node;
}

#if     (GSI_MAP_KTYPES & GSUNION_INT)
/*
 * Specialized lookup for the case where keys are known to be simple integer
 * or pointer values that are their own hash values and con be compared with
 * a test for integer equality.
 */
static INLINE GSIMapNode 
GSIMapNodeForSimpleKey(GSIMapTable map, GSIMapKey key)
{
  GSIMapBucket	bucket;
  GSIMapNode	node;

  if (map->nodeCount == 0)
    {
      return 0;
    }
  bucket = map->buckets + key.addr % map->bucketCount;
  node = bucket->firstNode;
  while ((node != 0) && node->key.addr != key.addr)
    {
      node = node->nextInBucket;
    }
  return node;
}
#endif

static INLINE void
GSIMapResize(GSIMapTable map, size_t new_capacity)
{
  GSIMapBucket	new_buckets;
  size_t	size = 1;
  size_t	old = 1;

  /*
   *	Find next size up in the fibonacci series
   */
  while (size < new_capacity)
    {
      size_t	tmp = old;

      old = size;
      size += tmp;
    }
  /*
   *	Avoid even numbers - since hash functions frequently generate uneven
   *	distributions around powers of two -
   *	we don't want lots of keys falling into a single bucket.
   */
  if (size % 2 == 0)
    {
      size++;
    }

  /*
   *	Make a new set of buckets for this map
   */
  new_buckets = (GSIMapBucket)NSZoneCalloc(map->zone, size,
    sizeof(GSIMapBucket_t));
  if (new_buckets != 0)
    {
      GSIMapRemangleBuckets(map, map->buckets, map->bucketCount, new_buckets,
	size);

      if (map->buckets != 0)
	{
	  NSZoneFree(map->zone, map->buckets);
	}
      map->buckets = new_buckets;
      map->bucketCount = size;
    }
}

static INLINE void
GSIMapRightSizeMap(GSIMapTable map, size_t capacity)
{
  /* FIXME: Now, this is a guess, based solely on my intuition.  If anyone
   * knows of a better ratio (or other test, for that matter) and can
   * provide evidence of its goodness, please get in touch with me, Albin
   * L. Jones <Albin.L.Jones@Dartmouth.EDU>. */

  if (3 * capacity >= 4 * map->bucketCount)
    {
      GSIMapResize(map, (3 * capacity)/4 + 1);
    }
}

/** Enumerating **/

/* IMPORTANT WARNING: Enumerators have a wonderous property.
 * Once a node has been returned by `GSIMapEnumeratorNextNode()', it may be
 * removed from the map without effecting the rest of the current
 * enumeration. */

/* EXTREMELY IMPORTANT WARNING: The purpose of this warning is point
 * out that, various (i.e., many) functions currently depend on
 * the behaviour outlined above.  So be prepared for some serious
 * breakage when you go fudging around with these things. */

/**
 * Create an return an enumerator for the specified map.<br />
 * You must call GSIMapEndEnumerator() when you have finished
 * with the enumerator.<br />
 * <strong>WARNING</strong> You should not alter a map while an enumeration
 * is in progress.  The results of doing so are reasonably unpredictable.
 * <br />Remember, DON'T MESS WITH A MAP WHILE YOU'RE ENUMERATING IT.
 */
static INLINE GSIMapEnumerator_t
GSIMapEnumeratorForMap(GSIMapTable map)
{
  GSIMapEnumerator_t	enumerator;

  enumerator.map = map;
  enumerator.node = 0;
  enumerator.bucket = 0;
  /*
   * Locate next bucket and node to be returned.
   */
  while (enumerator.bucket < map->bucketCount)
    {
      enumerator.node = map->buckets[enumerator.bucket].firstNode;
      if (enumerator.node != 0)
	{
	  break;	// Got first node, and recorded its bucket.
	}
      enumerator.bucket++;
    }

  return enumerator;
}

/**
 * Tidies up after map enumeration ... effectively destroys the enumerator.
 */
static INLINE void
GSIMapEndEnumerator(GSIMapEnumerator enumerator)
{
  ((_GSIE)enumerator)->map = 0;
  ((_GSIE)enumerator)->node = 0;
  ((_GSIE)enumerator)->bucket = 0;
}

/**
 * Returns the bucket from which the next node in the enumeration will
 * come.  Once the next node has been enumerated, you can use the
 * bucket and node to remove the node from the map using the
 * GSIMapRemoveNodeFromMap() function.
 */
static INLINE GSIMapBucket 
GSIMapEnumeratorBucket(GSIMapEnumerator enumerator)
{
  if (((_GSIE)enumerator)->node != 0)
    {
      GSIMapTable	map = ((_GSIE)enumerator)->map;

      return &((map->buckets)[((_GSIE)enumerator)->bucket]);
    }
  return 0;
}

/**
 * Returns the next node in the map, or a nul pointer if at the end.
 */
static INLINE GSIMapNode 
GSIMapEnumeratorNextNode(GSIMapEnumerator enumerator)
{
  GSIMapNode	node = ((_GSIE)enumerator)->node;

  if (node != 0)
    {
      GSIMapNode	next = node->nextInBucket;

      if (next == 0)
	{
	  GSIMapTable	map = ((_GSIE)enumerator)->map;
	  size_t	bucketCount = map->bucketCount;
	  size_t	bucket = ((_GSIE)enumerator)->bucket;

	  while (next == 0 && ++bucket < bucketCount)
	    {
	      next = (map->buckets[bucket]).firstNode;
	    }
	  ((_GSIE)enumerator)->bucket = bucket;
	}
      ((_GSIE)enumerator)->node = next;
    }
  return node;
}

#if	GSI_MAP_HAS_VALUE
static INLINE GSIMapNode
GSIMapAddPairNoRetain(GSIMapTable map, GSIMapKey key, GSIMapVal value)
{
  GSIMapNode node;

  node = GSIMapNewNode(map, key, value);

  if (node != 0)
    {
      GSIMapRightSizeMap(map, map->nodeCount);
      GSIMapAddNodeToMap(map, node);
    }
  return node;
}

static INLINE GSIMapNode
GSIMapAddPair(GSIMapTable map, GSIMapKey key, GSIMapVal value)
{
  GSIMapNode node;

  GSI_MAP_RETAIN_KEY(map, key);
  GSI_MAP_RETAIN_VAL(map, value);
  node = GSIMapNewNode(map, key, value);

  if (node != 0)
    {
      GSIMapRightSizeMap(map, map->nodeCount);
      GSIMapAddNodeToMap(map, node);
    }
  return node;
}
#else
static INLINE GSIMapNode
GSIMapAddKeyNoRetain(GSIMapTable map, GSIMapKey key)
{
  GSIMapNode node;

  node = GSIMapNewNode(map, key);

  if (node != 0)
    {
      GSIMapRightSizeMap(map, map->nodeCount);
      GSIMapAddNodeToMap(map, node);
    }
  return node;
}

static INLINE GSIMapNode
GSIMapAddKey(GSIMapTable map, GSIMapKey key)
{
  GSIMapNode node;

  GSI_MAP_RETAIN_KEY(map, key);
  node = GSIMapNewNode(map, key);

  if (node != 0)
    {
      GSIMapRightSizeMap(map, map->nodeCount);
      GSIMapAddNodeToMap(map, node);
    }
  return node;
}
#endif

/**
 * Removes the item for the specified key from the map.
 * If the key was present, returns YES, otherwise returns NO.
 */
static INLINE BOOL
GSIMapRemoveKey(GSIMapTable map, GSIMapKey key)
{
  GSIMapBucket	bucket = GSIMapBucketForKey(map, key);
  GSIMapNode	node;
  
  node = GSIMapNodeForKeyInBucket(map, bucket, key);
  if (node != 0)
    {
      GSIMapRemoveNodeFromMap(map, bucket, node);
      GSIMapFreeNode(map, node);
      return YES;
    }
  return NO;
}

static INLINE void
GSIMapCleanMap(GSIMapTable map)
{
  if (map->nodeCount > 0)
    {
      GSIMapBucket	bucket = map->buckets;
      unsigned int	i;
      GSIMapNode	startNode = 0;
      GSIMapNode	prevNode = 0;
      GSIMapNode	node;
      
      map->nodeCount = 0;
      for (i = 0; i < map->bucketCount; i++)
	{
	  node = bucket->firstNode;
	  if (prevNode != 0)
	    {
	      prevNode->nextInBucket = node;
	    }
	  else
	    {
	      startNode = node;
	    }
	  while(node != 0)
	    {
	      GSI_MAP_RELEASE_KEY(map, node->key);
	  
#if	GSI_MAP_HAS_VALUE
	      GSI_MAP_RELEASE_VAL(map, node->value);
#endif
	      prevNode = node;
	      node = node->nextInBucket;
	    }
	  bucket->nodeCount = 0;
	  bucket->firstNode = 0;
	  bucket++;
	}
      
      prevNode->nextInBucket = map->freeNodes;
      map->freeNodes = startNode;
    }
}

static INLINE void
GSIMapEmptyMap(GSIMapTable map)
{
  unsigned int	i;

#ifdef	GSI_MAP_NOCLEAN
  if (GSI_MAP_NOCLEAN)
    {
      map->nodeCount = 0;
    }
  else
    {
      GSIMapCleanMap(map);
    }
#else
  GSIMapCleanMap(map);
#endif
  if (map->buckets != 0)
    {
      NSZoneFree(map->zone, map->buckets);
      map->buckets = 0;
      map->bucketCount = 0;
    }
  if (map->nodeChunks != 0)
    {
      for (i = 0; i < map->chunkCount; i++)
	{
	  NSZoneFree(map->zone, map->nodeChunks[i]);
	}
      map->chunkCount = 0;
      NSZoneFree(map->zone, map->nodeChunks);
      map->nodeChunks = 0;
    }
  map->freeNodes = 0;
  map->zone = 0;
}

static INLINE void 
GSIMapInitWithZoneAndCapacity(GSIMapTable map, NSZone *zone, size_t capacity)
{
  map->zone = zone;
  map->nodeCount = 0;
  map->bucketCount = 0;
  map->buckets = 0;
  map->nodeChunks = 0;
  map->freeNodes = 0;
  map->chunkCount = 0;
  map->increment = 300000;   // choosen so the chunksize will be less than 4Mb
  GSIMapRightSizeMap(map, capacity);
  GSIMapMoreNodes(map, capacity);
}

#if	defined(__cplusplus)
}
#endif

#endif	/* OS_API_VERSION(GS_API_NONE,GS_API_NONE) */

