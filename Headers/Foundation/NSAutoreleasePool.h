/* Interface for NSAutoreleasePool for GNUStep
   Copyright (C) 1995, 1996, 1997 Free Software Foundation, Inc.

   Written by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Date: 1995
   
   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.
   
   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02111 USA.
   */ 

#ifndef __NSAutoreleasePool_h_GNUSTEP_BASE_INCLUDE
#define __NSAutoreleasePool_h_GNUSTEP_BASE_INCLUDE

#include <Foundation/NSObject.h>

@class NSAutoreleasePool;
@class NSThread;


/**
 * Each thread has its own copy of these variables.
 <example>
{
  NSAutoreleasePool *current_pool; // current pool for thread
  unsigned total_objects_count;    // total #/autoreleased objects over thread's lifetime
  id *pool_cache;                  // cache of previously-allocated pools,
  int pool_cache_size;             //  used internally for recycling
  int pool_cache_count;
}
 </example>
*/
typedef struct autorelease_thread_vars
{
  /* The current, default NSAutoreleasePool for the calling thread;
     the one that will hold objects that are arguments to
     [NSAutoreleasePool +addObject:]. */
  NSAutoreleasePool *current_pool;

  /* The total number of objects autoreleased since the thread was
     started, or since -resetTotalAutoreleasedObjects was called
     in this thread. (if compiled in) */
  unsigned total_objects_count;

  /* A cache of NSAutoreleasePool's already alloc'ed.  Caching old pools
     instead of deallocating and re-allocating them will save time. */
  id *pool_cache;
  int pool_cache_size;
  int pool_cache_count;
} thread_vars_struct;

/* Initialize an autorelease_thread_vars structure for a new thread.
   This function is called in NSThread each time an NSThread is created.
   TV should be of type `struct autorelease_thread_vars *' */
#define init_autorelease_thread_vars(TV)  memset (TV, 0, sizeof (typeof (*TV)))



/**
 *  Each pool holds its objects-to-be-released in a linked-list of 
    these structures.
    <example>
{
  struct autorelease_array_list *next;
  unsigned size;
  unsigned count;
  id objects[0];
}
    </example>
 */
typedef struct autorelease_array_list
{
  struct autorelease_array_list *next;
  unsigned size;
  unsigned count;
  id objects[0];
} array_list_struct;



/**
 * <p>
 *   The standard OpenStep system of memory management employs retain counts.
 *   When an object is created, it has a retain count of 1.  When an object
 *   is retained, the retain count is incremented.  When it is released the
 *   retain count is decremented, and when the retain count goes to zero the
 *   object gets deallocated.
 * </p>
 * <p>
 *   A simple retain/release mechanism has problems with passing objects
 *   from one scope to another,
 *   so it's augmented with autorelease pools.  You can use the
 *   AUTORELEASE() macro to call the [NSObject-autorelease]
 *   method, which adds an object to the current autorelease pool by
 *   calling [NSAutoreleasePool+addObject:].<br />
 *   An autorelease pool simply maintains a reference to each object
 *   added to it, and for each addition, the autorelease pool will
 *   call the [NSObject-release] method of the object when the pool
 *   is released.  So doing an AUTORELEASE() is just the same as
 *   doing a RELEASE(), but deferred until the current autorelease
 *   pool is deallocated.
 * </p>
 * <p>
 *   The NSAutoreleasePool class maintains a separate stack of
 *   autorelease pools objects in each thread.
 * </p>
 * <p>
 *   When an autorelease pool is created, it is automatically
 *   added to the stack of pools in the thread.
 * </p>
 * <p>
 *   When a pool is destroyed, it (and any pool later in
 *   the stack) is removed from the stack.
 * </p>
 * <p>
 *   This mechanism provides a simple but controllable and reasonably
 *   efficient way of managing temporary objects.  An object can be
 *   autoreleased and then passed around and used until the topmost 
 *   pool in the stack is destroyed.
 * </p>   
 * <p>
 *   Most methods return objects which are either owned by autorelease
 *   pools or by the receiver of the method, so the lifetime of the
 *   returned object can be assumed to be the shorter of the lifetime
 *   of the current autorelease pool, or that of the receiver on which
 *   the method was called.<br />
 *   The exceptions to this are those object returned by -
 * </p>
 * <deflist>
 *   <term>[NSObject+alloc], [NSObject+allocWithZone:]</term>
 *   <desc>
 *     Methods whose names begin with alloc return an uninitialised
 *     object, owned by the caller.
 *   </desc>
 *   <term>[NSObject-init]</term>
 *   <desc>
 *     Methods whose names begin with init return an initialised
 *     version of the receiving object, owned by the caller.<br />
 *     NB. The returned object may not actually be the same as the
 *     receiver ... sometimes an init method releases the original
 *     receiver and returns an alternative.
 *   </desc>
 *   <term>[NSObject+new]</term>
 *   <desc>
 *     Methods whose names begin with new combine the effects of
 *     allocation and initialisation.
 *   </desc>
 *   <term>[NSObject-copy], [(NSCopying)-copyWithZone:]</term>
 *   <desc>
 *     Methods whose names begin with copy create a copy of the receiver
 *     which is owned by the caller.
 *   </desc>
 *   <term>[NSObject-mutableCopy], [(NSMutableCopying)-mutableCopyWithZone:]</term>
 *   <desc>
 *     Methods whose names begin with mutableCopy create a copy of the receiver
 *     which is owned by the caller.
 *   </desc>
 * </deflist>
 */
@interface NSAutoreleasePool : NSObject 
{
  /* For re-setting the current pool when we are dealloc'ed. */
  NSAutoreleasePool *_parent;
  /* This pointer to our child pool is  necessary for co-existing
     with exceptions. */
  NSAutoreleasePool *_child;
  /* A collection of the objects to be released. */
  struct autorelease_array_list *_released;
  struct autorelease_array_list *_released_head;
  /* The total number of objects autoreleased in this pool. */
  unsigned _released_count;
  /* The method to add an object to this pool */
  void 	(*_addImp)(id, SEL, id);
}

/**
 * Adds anObj to the current autorelease pool.<br />
 * If there is no autorelease pool in the thread,
 * a warning is logged and the object is leaked (ie it will not be released).
 */
+ (void) addObject: (id)anObj;

/**
 * Allocate and return an autorelease pool instance.<br />
 * If there is an already-allocated NSAutoreleasePool available,
 * save time by just returning that, rather than allocating a new one.<br />
 * The pool instance becomes the current autorelease pool for this thread.
 */
+ (id) allocWithZone: (NSZone*)zone;

/**
 * Adds anObj to this autorelease pool.
 */
- (void) addObject: (id)anObj;

/**
 * Raises an exception - pools should not be autoreleased.
 */
- (id) autorelease;

/**
 * Destroys the receiver (calls -dealloc).
 */
- (oneway void) release;

/**
 * Raises an exception ... pools should not be retained.
 */
- (id) retain;

#ifndef	NO_GNUSTEP
/**
 * <p>
 *   Counts the number of times that the specified object occurs
 *   in autorelease pools in the current thread.
 * </p>
 * <p>
 *   This method is <em>slow</em> and should probably only be
 *   used for debugging purposes.
 * </p>
 */
+ (unsigned) autoreleaseCountForObject: (id)anObject;

/** 
 * Return the currently active autorelease pool.
 */
+ (id) currentPool;

/**
 * <p>
 *   Specifies whether objects contained in autorelease pools are to
 *   be released when the pools are deallocated (by default YES).
 * </p>
 * <p>
 *   You can set this to NO for debugging purposes.
 * </p>
 */
+ (void) enableRelease: (BOOL)enable;

/**
 * <p>
 *   When autorelease pools are deallocated, the memory they used
 *   is retained in a cache for re-use so that new polls can be
 *   created very quickly.
 * </p>
 * <p>
 *   This method may be used to empty that cache, ensuring that
 *   the minimum memory is used by the application.
 * </p>
 */
+ (void) freeCache;

/**
 * <p>
 *   Specifies a limit to the number of objects that may be added to
 *   an autorelease pool.  When this limit is reached an exception is
 *   raised.
 * </p>
 * <p>
 *   You can set this to a smallish value to catch problems with code
 *   that autoreleases too many objects to operate efficiently.
 * </p>
 * <p>
 *   Default value is maxint.
 * </p>
 */
+ (void) setPoolCountThreshhold: (unsigned)c;

/**
 * Destroys all the autorelease pools in the thread.<br />
 * You should not call this directly, it's called automatically
 * when a thread exits.
 */
+ (void) _endThread: (NSThread*)thread;

/**
 * Return the number of objects in this pool.
 */
- (unsigned) autoreleaseCount;

/**
 * Empties the current pool by releasing all the autoreleased objects
 * in it.  Also destroys any child pools (ones created after
 * the receiver in the same thread) causing any objects in those pools
 * to be released.<br />
 * This is a low cost (efficient) method which may be used to get rid of
 * autoreleased objects in the pool, but carry on using the pool.
 */
- (void) emptyPool;
#endif
@end

#endif /* __NSAutoreleasePool_h_GNUSTEP_BASE_INCLUDE */
