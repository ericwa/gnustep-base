/* Implementation of NSObject for GNUStep
   Copyright (C) 1994, 1995, 1996 Free Software Foundation, Inc.
   
   Written by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Date: August 1994
   
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
   Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
   */ 

#include <config.h>
#include <gnustep/base/preface.h>
#include <stdarg.h>
#include <Foundation/NSObject.h>
#include <objc/Protocol.h>
#include <objc/objc-api.h>
#include <Foundation/NSMethodSignature.h>
#include <gnustep/base/Invocation.h>
#include <Foundation/NSInvocation.h>
#include <Foundation/NSAutoreleasePool.h>
#include <Foundation/NSString.h>
#include <gnustep/base/o_map.h>
#include <Foundation/NSException.h>
#include <Foundation/NSZone.h>
#include <limits.h>


/*
 *	Reference count and memory management
 *
 *	If REFCNT_LOCAL is defined, reference counts for object are stored
 *	with the object, otherwise they are stored in a global map table
 *	that has to be protected by mutexes in a multithreraded environment.
 *	You therefore want REFCNT_LOCAL defined for best performance.
 *
 *	If CACHE_ZONE is defined, the zone in which an object has been
 *	allocated is stored with the object - this makes lookup of the
 *	correct zone to free memory very fast.
 */

#define	REFCNT_LOCAL	1
/* #define	CACHE_ZONE	1	*/

#if	defined(REFCNT_LOCAL) || defined(CACHE_ZONE)

/*
 *	Define a structure to hold information that is held locally
 *	(before the start) in each object.
 */ 

typedef struct obj_layout_unpadded {
#if	defined(REFCNT_LOCAL)
    unsigned	retained;
#endif
#if	defined(CACHE_ZONE)
    NSZone	*zone;
#endif
} unp;

/*
 *	Now do the REAL version - using the other version to determine
 *	what padding (if any) is required to get the alignment of the
 *	structure correct.
 */
struct obj_layout {
#if	defined(REFCNT_LOCAL)
    unsigned	retained;
#endif
#if	defined(CACHE_ZONE)
    NSZone	*zone;
#endif
    char	padding[__alignof(double) - sizeof(unp)%__alignof__(double)];
};
typedef	struct obj_layout *obj;

#endif	/* defined(REFCNT_LOCAL) || defined(CACHE_ZONE) */


/*
 *	Now do conditional compilation of reference count functions
 *	depending on whether we are using local or global counting.
 */
#if	defined(REFCNT_LOCAL)
void
NSIncrementExtraRefCount(id anObject)
{
  ((obj)anObject)[-1].retained++;
}

#define	NSIncrementExtraRefCount(X) \
	((obj)(X))[-1].retained++

BOOL
NSDecrementExtraRefCountWasZero(id anObject)
{
  if (((obj)anObject)[-1].retained-- == 0)
    return YES;
  else
    return NO;
}

#define	NSDecrementExtraRefCountWasZero(X) \
	(((obj)(X))[-1].retained-- == 0 ? YES : NO)

#define	extraRefCount(X)	(((obj)(X))[-1].retained)

#else

/* The maptable of retain counts on objects */
static o_map_t *retain_counts = NULL;
/* The mutex lock to protect multi-threaded use of `retain_counts' */
static objc_mutex_t retain_counts_gate = NULL;

void
NSIncrementExtraRefCount (id anObject)
{
  o_map_node_t *node;
  extern o_map_node_t *o_map_node_for_key (o_map_t *m, const void *k);

  objc_mutex_lock (retain_counts_gate);
  node = o_map_node_for_key (retain_counts, anObject);
  if (node)
    ((int)(node->value))++;
  else
    o_map_at_key_put_value_known_absent (retain_counts, anObject, (void*)1);
  objc_mutex_unlock (retain_counts_gate);
}

BOOL
NSDecrementExtraRefCountWasZero (id anObject)
{
  o_map_node_t *node;
  extern o_map_node_t *o_map_node_for_key (o_map_t *m, const void *k);
  extern void o_map_remove_node (o_map_node_t *node);

  objc_mutex_lock (retain_counts_gate);
  node = o_map_node_for_key (retain_counts, anObject);
  if (!node)
    {
      objc_mutex_unlock (retain_counts_gate);
      return YES;
    }
  assert ((int)(node->value) > 0);
  if (!--((int)(node->value)))
    o_map_remove_node (node);
  objc_mutex_unlock (retain_counts_gate);
  return NO;
}

static unsigned
extraRefCount (id anObject)
{
  unsigned ret;

  objc_mutex_lock (retain_counts_gate);
  ret = (unsigned) o_map_value_at_key (retain_counts, anObject);
  if (ret == (unsigned)o_map_not_a_key_marker(retain_counts) ||
      ret == (unsigned)o_map_not_a_value_marker(retain_counts)) ret = 0;
  objc_mutex_unlock (retain_counts_gate);
  return ret;	/* ExtraRefCount + 1	*/
}

#endif	/* defined(REFCNT_LOCAL) */


/*
 *	Now do conditional compilation of memory allocation functions
 *	depending on what information (if any) we are storing before
 *	the start of each object.
 */
#if	defined(REFCNT_LOCAL) || defined(CACHE_ZONE)

NSObject *NSAllocateObject (Class aClass, unsigned extraBytes, NSZone *zone)
{
  id new = nil;
  int size = aClass->instance_size + extraBytes + sizeof(struct obj_layout);
  if (CLS_ISCLASS (aClass))
    {
      if (zone == 0)
	zone = NSDefaultMallocZone();
      new = NSZoneMalloc(zone, size);
    }
  if (new != nil)
    {
      memset (new, 0, size);
#if	defined(CACHE_ZONE)
      ((obj)new)->zone = zone;
#endif
      new = (id)&((obj)new)[1];
      new->class_pointer = aClass;
    }
#ifndef	NDEBUG
  GSDebugAllocationAdd(aClass);
#endif
  return new;
}

void NSDeallocateObject(NSObject *anObject)
{
  if ((anObject!=nil) && CLS_ISCLASS(((id)anObject)->class_pointer))
    {
      NSZone	*z;
      obj	o = &((obj)anObject)[-1];

#ifndef	NDEBUG
      GSDebugAllocationRemove(((id)anObject)->class_pointer);
#endif
#if defined(CACHE_ZONE)
      z = o->zone;
#else
      z = [anObject zone];
#endif
      ((id)anObject)->class_pointer = (void*) 0xdeadface;
      NSZoneFree(z, o);
    }
  return;
}

#else

NSObject *NSAllocateObject (Class aClass, unsigned extraBytes, NSZone *zone)
{
  id new = nil;
  int size = aClass->instance_size + extraBytes;
  if (CLS_ISCLASS (aClass))
    new = NSZoneMalloc (zone, size);
  if (new != nil)
    {
      memset (new, 0, size);
      new->class_pointer = aClass;
    }
#ifndef	NDEBUG
  GSDebugAllocationAdd(aClass);
#endif
  return new;
}

void NSDeallocateObject(NSObject *anObject)
{
  if ((anObject!=nil) && CLS_ISCLASS(((id)anObject)->class_pointer))
    {
      NSZone	*z = [anObject zone];

#ifndef	NDEBUG
      GSDebugAllocationRemove(((id)anObject)->class_pointer);
#endif
      ((id)anObject)->class_pointer = (void*) 0xdeadface;
      NSZoneFree(z, anObject);
    }
  return;
}

#endif	/* defined(REFCNT_LOCAL) || defined(CACHE_ZONE) */

#if defined(CACHE_ZONE)
BOOL
NSShouldRetainWithZone (NSObject *anObject, NSZone *requestedZone)
{
  return (!requestedZone || requestedZone == NSDefaultMallocZone()
	  || ((obj)anObject)[-1].zone == requestedZone);
}
#else
BOOL
NSShouldRetainWithZone (NSObject *anObject, NSZone *requestedZone)
{
  return (!requestedZone || requestedZone == NSDefaultMallocZone()
	  || [anObject zone] == requestedZone);
}
#endif




/* The Class responsible for handling autorelease's.  This does not
   need mutex protection, since it is simply a pointer that gets read
   and set. */
static id autorelease_class = nil;

/* When this is `YES', every call to release/autorelease, checks to
   make sure isn't being set up to release itself too many times.
   This does not need mutex protection. */
static BOOL double_release_check_enabled = NO;


@implementation NSObject

+ (void) initialize
{
  if (self == [NSObject class])
    {
      // Create the global lock
      gnustep_global_lock = [[NSRecursiveLock alloc] init];
#if !defined(REFCNT_LOCAL)
      retain_counts = o_map_with_callbacks (o_callbacks_for_non_owned_void_p,
					    o_callbacks_for_int);
      retain_counts_gate = objc_mutex_allocate ();
#endif
      autorelease_class = [NSAutoreleasePool class];
    }
  return;
}

+ (id) alloc
{
  return [self allocWithZone: NSDefaultMallocZone()];
}

+ (id) allocWithZone: (NSZone*)z
{
  return NSAllocateObject (self, 0, z);
}

+ (id) copyWithZone: (NSZone*)z
{
  return self;
}

+ (id) new
{
  return [[self alloc] init];
}

- (id) copy
{
  return [(id)self copyWithZone: NULL];
}

- (void) dealloc
{
  NSDeallocateObject (self);
}

- free
{
  [NSException raise: NSGenericException
	       format: @"Use `dealloc' instead of `free'."];
  return nil;
}

- (id) init
{
  return self;
}

- (id) mutableCopy
{
  return [(id)self mutableCopyWithZone: NULL];
}

+ (Class) superclass
{
  return class_get_super_class (self);
}

- (Class) superclass
{
  return object_get_super_class (self);
}

+ (BOOL) instancesRespondToSelector: (SEL)aSelector
{
  return (class_get_instance_method(self, aSelector) != METHOD_NULL);
}

+ (BOOL) conformsToProtocol: (Protocol*)aProtocol
{
  int i;
  struct objc_protocol_list* proto_list;

  for (proto_list = ((struct objc_class*)self)->class_pointer->protocols;
       proto_list; proto_list = proto_list->next)
    {
      for (i=0; i < proto_list->count; i++)
      {
	/* xxx We should add conformsToProtocol to Protocol class. */
        if ([proto_list->list[i] conformsTo: aProtocol])
          return YES;
      }
    }

  if ([self superclass])
    return [[self superclass] conformsToProtocol: aProtocol];
  else
    return NO;
}

- (BOOL) conformsToProtocol: (Protocol*)aProtocol
{
  return [[self class] conformsToProtocol:aProtocol];
}

+ (IMP) instanceMethodForSelector: (SEL)aSelector
{
  return method_get_imp(class_get_instance_method(self, aSelector));
}
  
- (IMP) methodForSelector: (SEL)aSelector
{
  return (method_get_imp(object_is_instance(self)
                         ?class_get_instance_method(self->isa, aSelector)
                         :class_get_class_method(self->isa, aSelector)));
}

+ (NSMethodSignature*) instanceMethodSignatureForSelector: (SEL)aSelector
{
    struct objc_method* mth = class_get_instance_method(self, aSelector);
    return mth ? [NSMethodSignature signatureWithObjCTypes:mth->method_types]
		: nil;
}
  
- (NSMethodSignature*) methodSignatureForSelector: (SEL)aSelector
{
    struct objc_method* mth =
	    (object_is_instance(self) ?
		  class_get_instance_method(self->isa, aSelector)
		: class_get_class_method(self->isa, aSelector));
    return mth ? [NSMethodSignature signatureWithObjCTypes:mth->method_types]
		: nil;
}

- (NSString*) description
{
  return [NSString stringWithCString: object_get_class_name(self)];
}

+ (NSString*) description
{
  return [NSString stringWithCString: class_get_class_name(self)];
}

+ (void) poseAsClass: (Class)aClassObject
{
  class_pose_as(self, aClassObject);
}

- (void) doesNotRecognizeSelector: (SEL)aSelector
{
  [NSException raise: NSInvalidArgumentException
	       format: @"%s does not recognize %s",
	       object_get_class_name(self), sel_get_name(aSelector)];
}

- (retval_t) forward:(SEL)aSel :(arglist_t)argFrame
{
  NSInvocation *inv;

  inv = [[[NSInvocation alloc] initWithArgframe: argFrame
				       selector: aSel] autorelease];
  [self forwardInvocation:inv];
  return [inv returnFrame: argFrame];
}

- (void) forwardInvocation: (NSInvocation*)anInvocation
{
  [self doesNotRecognizeSelector:[anInvocation selector]];
  return;
}

- (id) awakeAfterUsingCoder: (NSCoder*)aDecoder
{
  return self;
}

- (Class) classForCoder
{
  return [self class];
}

- (id) replacementObjectForCoder: (NSCoder*)anEncoder
{
  return self;
}


/* NSObject protocol */

- autorelease
{
  if (double_release_check_enabled)
    {
      unsigned release_count;
      unsigned retain_count = [self retainCount];
      release_count = [autorelease_class autoreleaseCountForObject:self];
      if (release_count > retain_count)
        [NSException
	  raise: NSGenericException
	  format: @"Autorelease would release object too many times.\n"
	  @"%d release(s) versus %d retain(s)", release_count, retain_count];
    }

  [autorelease_class addObject:self];
  return self;
}

+ autorelease
{
  return self;
}

+ (Class) class
{
  return self;
}

- (Class) class
{
  return object_get_class(self);
}

- (unsigned) hash
{
  return (unsigned)self;
}

- (BOOL) isEqual: anObject
{
  return (self == anObject);
}

+ (BOOL) isKindOfClass: (Class)aClass
{
  Class class;

  for (class = self; 
       class != Nil;
       class = class_get_super_class (class))
    {
      if (class == aClass)
	return YES;
    }
  return NO;
}

- (BOOL) isKindOfClass: (Class)aClass
{
  Class class;

  for (class = self->isa; 
       class != Nil;
       class = class_get_super_class (class))
    {
      if (class == aClass)
	return YES;
    }
  return NO;
}

+ (BOOL) isMemberOfClass: (Class)aClass
{
  return self == aClass;
}

- (BOOL) isMemberOfClass: (Class)aClass
{
  return self->isa==aClass;
}

- (BOOL) isProxy
{
  return NO;
}

- performSelector: (SEL)aSelector
{
  IMP msg = objc_msg_lookup(self, aSelector);
  if (!msg)
    {
      [NSException
	raise: NSGenericException
	format: @"invalid selector passed to %s", sel_get_name(_cmd)];
      return nil;
    }
  return (*msg)(self, aSelector);
}

- performSelector: (SEL)aSelector withObject: anObject
{
  IMP msg = objc_msg_lookup(self, aSelector);
  if (!msg)
    {
      [NSException
	raise: NSGenericException
	format: @"invalid selector passed to %s", sel_get_name(_cmd)];
      return nil;
    }
  return (*msg)(self, aSelector, anObject);
}

- performSelector: (SEL)aSelector withObject: object1 withObject: object2
{
  IMP msg = objc_msg_lookup(self, aSelector);
  if (!msg)
    {
      [NSException
	raise: NSGenericException
	format: @"invalid selector passed to %s", sel_get_name(_cmd)];
      return nil;
    }
  return (*msg)(self, aSelector, object1, object2);
}

- (oneway void) release
{
  if (double_release_check_enabled)
    {
      unsigned release_count;
      unsigned retain_count = [self retainCount];
      release_count = [autorelease_class autoreleaseCountForObject:self];
      if (release_count >= retain_count)
        [NSException raise: NSGenericException
		     format: @"Release would release object too many times."];
    }

  if (NSDecrementExtraRefCountWasZero(self))
    [self dealloc];
  return;
}

+ (oneway void) release
{
  return;
}

- (BOOL) respondsToSelector: (SEL)aSelector
{
  return ((object_is_instance(self)
           ?class_get_instance_method(self->isa, aSelector)
           :class_get_class_method(self->isa, aSelector))!=METHOD_NULL);
}

- retain
{
  NSIncrementExtraRefCount(self);
  return self;
}

+ retain
{
  return self;
}

- (unsigned) retainCount
{
  return extraRefCount(self) + 1;
}

+ (unsigned) retainCount
{
  return UINT_MAX;
}

- self
{
  return self;
}

- (NSZone *)zone
{
#if defined(REFCNT_LOCAL) || defined(CACHE_ZONE)
#if defined(CACHE_ZONE)
  return ((obj)self)[-1].zone;
#else
  return NSZoneFromPointer(&((obj)self)[-1]);
#endif
#else
  return NSZoneFromPointer(self);
#endif
}

- (void) encodeWithCoder: (NSCoder*)aCoder
{
  return;
}

- initWithCoder: (NSCoder*)aDecoder
{
  return self;
}

+ (int)version
{
  return class_get_version(self);
}

+ setVersion:(int)aVersion
{
  class_set_version(self, aVersion);
  return self;
}

@end


@implementation NSObject (NEXTSTEP)

/* NEXTSTEP Object class compatibility */

- error:(const char *)aString, ...
{
#define FMT "error: %s (%s)\n%s\n"
  char fmt[(strlen((char*)FMT)+strlen((char*)object_get_class_name(self))
            +((aString!=NULL)?strlen((char*)aString):0)+8)];
  va_list ap;

  sprintf(fmt, FMT, object_get_class_name(self),
                    object_is_instance(self)?"instance":"class",
                    (aString!=NULL)?aString:"");
  va_start(ap, aString);
  /* xxx What should `code' argument be?  Current 0. */
  objc_verror (self, 0, fmt, ap);
  va_end(ap);
  return nil;
#undef FMT
}

- (const char *) name
{
  return object_get_class_name(self);
}

- (BOOL)isKindOf:(Class)aClassObject
{
  return [self isKindOfClass:aClassObject];
}

- (BOOL)isMemberOf:(Class)aClassObject
{
  return [self isMemberOfClass:aClassObject];
}

+ (BOOL)instancesRespondTo:(SEL)aSel
{
  return [self instancesRespondToSelector:aSel];
}

- (BOOL)respondsTo:(SEL)aSel
{
  return [self respondsToSelector:aSel];
}

+ (BOOL) conformsTo: (Protocol*)aProtocol
{
  return [self conformsToProtocol:aProtocol];
}

- (BOOL) conformsTo: (Protocol*)aProtocol
{
  return [self conformsToProtocol:aProtocol];
}

- (retval_t)performv:(SEL)aSel :(arglist_t)argFrame
{
  return objc_msg_sendv(self, aSel, argFrame);
}

+ (IMP)instanceMethodFor:(SEL)aSel
{
  return [self instanceMethodForSelector:aSel];
}

+ (NSMethodSignature*)instanceMethodSignatureForSelector:(SEL)aSelector
{
    struct objc_method* mth = class_get_instance_method(self, aSelector);

    return mth ? [NSMethodSignature signatureWithObjCTypes:mth->method_types]
		: nil;
}

- (IMP)methodFor:(SEL)aSel
{
  return [self methodForSelector:aSel];
}

+ poseAs:(Class)aClassObject
{
  [self poseAsClass:aClassObject];
  return self;
}

- notImplemented:(SEL)aSel
{
  [NSException
    raise: NSGenericException
    format: @"method %s not implemented", sel_get_name(aSel)];
  return nil;
}

- doesNotRecognize:(SEL)aSel
{
  [NSException raise: NSGenericException
	       format: @"%s does not recognize %s",
	       object_get_class_name(self), sel_get_name(aSel)];
  return nil;
}

- perform: (SEL)sel with: anObject
{
  return [self performSelector:sel withObject:anObject];
}

- perform: (SEL)sel with: anObject with: anotherObject
{
  return [self performSelector:sel withObject:anObject 
	       withObject:anotherObject];
}

- perform: (SEL)sel withObject: anObject
{
  return [self performSelector:sel withObject:anObject];
}

- perform: (SEL)sel withObject: anObject withObject: anotherObject
{
  return [self performSelector:sel withObject:anObject 
	       withObject:anotherObject];
}

@end


@implementation NSObject (GNU)

/* GNU Object class compatibility */

+ (void) setAutoreleaseClass: (Class)aClass
{
  autorelease_class = aClass;
}

+ (Class) autoreleaseClass
{
  return autorelease_class;
}

+ (void) enableDoubleReleaseCheck: (BOOL)enable
{
  double_release_check_enabled = enable;
}

- (int)compare:anotherObject;
{
  if ([self isEqual:anotherObject])
    return 0;
  // Ordering objects by their address is pretty useless, 
  // so subclasses should override this is some useful way.
  else if (self > anotherObject)
    return 1;
  else 
    return -1;
}

- (BOOL)isMetaClass
{
  return NO;
}

- (BOOL)isClass
{
  return object_is_class(self);
}

- (BOOL)isInstance
{
  return object_is_instance(self);
}

- (BOOL)isMemberOfClassNamed:(const char *)aClassName
{
  return ((aClassName!=NULL)
          &&!strcmp(class_get_class_name(self->isa), aClassName));
}

+ (struct objc_method_description *)descriptionForInstanceMethod:(SEL)aSel
{
  return ((struct objc_method_description *)
           class_get_instance_method(self, aSel));
}

- (struct objc_method_description *)descriptionForMethod:(SEL)aSel
{
  return ((struct objc_method_description *)
           (object_is_instance(self)
            ?class_get_instance_method(self->isa, aSel)
            :class_get_class_method(self->isa, aSel)));
}

- (Class)transmuteClassTo:(Class)aClassObject
{
  if (object_is_instance(self))
    if (class_is_class(aClassObject))
      if (class_get_instance_size(aClassObject)==class_get_instance_size(isa))
        if ([self isKindOfClass:aClassObject])
          {
            Class old_isa = isa;
            isa = aClassObject;
            return old_isa;
          }
  return nil;
}

- subclassResponsibility:(SEL)aSel
{
  [NSException
    raise: NSGenericException
    format: @"subclass should override %s", sel_get_name(aSel)];
  return nil;
}

- shouldNotImplement:(SEL)aSel
{
  [NSException
    raise: NSGenericException
    format: @"%s should not implement %s", 
    object_get_class_name(self), sel_get_name(aSel)];
  return nil;
}

+ (int)streamVersion: (TypedStream*)aStream
{
  if (aStream->mode == OBJC_READONLY)
    return objc_get_stream_class_version (aStream, self);
  else
    return class_get_version (self);
}

// These are used to write or read the instance variables 
// declared in this particular part of the object.  Subclasses
// should extend these, by calling [super read/write: aStream]
// before doing their own archiving.  These methods are private, in
// the sense that they should only be called from subclasses.

- read: (TypedStream*)aStream
{
  // [super read: aStream];  
  return self;
}

- write: (TypedStream*)aStream
{
  // [super write: aStream];
  return self;
}

- awake
{
  // [super awake];
  return self;
}

@end
