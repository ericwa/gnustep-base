/** Implementation for GNU Objective-C version of NSProxy
   Copyright (C) 1997 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Created: August 1997

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
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.

   <title>NSProxy class reference</title>
   $Date$ $Revision$
   */

#include "config.h"
#include "GNUstepBase/preface.h"
#include "Foundation/NSInvocation.h"
#include "Foundation/NSProxy.h"
#include "Foundation/NSMethodSignature.h"
#include "Foundation/NSAutoreleasePool.h"
#include "Foundation/NSException.h"
#include "Foundation/NSObjCRuntime.h"
#include "Foundation/NSDistantObject.h"
#include "Foundation/NSPortCoder.h"

#ifdef	HAVE_LIMITS_H
/* For UINT_MAX */
#include <limits.h>
#endif

@class	NSDistantObject;

#ifndef NeXT_RUNTIME
extern BOOL __objc_responds_to(id, SEL);
#endif

/**
 * <p>The NSProxy class provides a basic implementation of a class whose
 * instances are used to <em>stand in</em> for other objects.<br />
 * The class provides the most basic methods of NSObject, and expects
 * messages for other methods to be forwarded to the <em>real</em>
 * object represented by the proxy.  You must subclass NSProxy to
 * implement -forwardInvocation: to these <em>real</em> objects.</p>
 *
 * <p>Note that <code>NSProxy</code> is a different sort of class than others
 *  in the GNUstep Base library in that it is the only example of a root class
 *  besides [NSObject].  Thus, it defines its own <code><em>isa</em></code>
 *  variable and implements the <code>NSObject</code> protocol.</p>
 */
@implementation NSProxy

/**
 * Allocates and returns an NSProxy instance in the default zone.
 */
+ (id) alloc
{
  return [self allocWithZone: NSDefaultMallocZone()];
}

/**
 * Allocates and returns an NSProxy instance in the specified zone z.
 */
+ (id) allocWithZone: (NSZone*)z
{
  NSProxy*	ob = (NSProxy*) NSAllocateObject(self, 0, z);
  return ob;
}

/**
 * Returns the receiver.
 */
+ (id) autorelease
{
  return self;
}

/**
 * Returns the receiver.
 */
+ (Class) class
{
  return self;
}

/**
 * Returns a string describing the receiver.
 */
+ (NSString*) description
{
  return [NSString stringWithFormat: @"<%s>", GSClassNameFromObject(self)];
}

/**
 * Returns NO ... the NSProxy class cannot be an instance of any class.
 */
+ (BOOL) isKindOfClass: (Class)aClass
{
  return NO;
}

/**
 * Returns YES if aClass is identical to the receiver, NO otherwise.
 */
+ (BOOL) isMemberOfClass: (Class)aClass
{
  return(self == aClass);
}

/**
 * A dummy method ...
 */
+ (void) load
{
  /* Do nothing	*/
}

- (IMP) methodForSelector: (SEL)aSelector
{
  return get_imp(GSObjCClass((id)self), aSelector);
}

/**
 * Returns the method signature for the specified selector.
 */
+ (NSMethodSignature*) methodSignatureForSelector: (SEL)aSelector
{
  struct objc_method	*mth;

  if (aSelector == 0)
    {
      return nil;
    }
  mth = GSGetMethod(self, aSelector, NO, YES);
  if (mth != 0)
    {
      const char	*types = mth->method_types;

      if (types != 0)
	{
	  return [NSMethodSignature signatureWithObjCTypes: types];
	}
    }
  return nil;
}

/**
 * A dummy method to ensure that the class can safely be held in containers.
 */
+ (void) release
{
  /* Do nothing	*/
}

/**
 * Returns YES if the receiver responds to aSelector, NO otherwise.
 */
+ (BOOL) respondsToSelector: (SEL)aSelector
{
  if (__objc_responds_to(self, aSelector))
    return YES;
  else
    return NO;
}

/**
 * Returns the receiver.
 */
+ (id) retain
{
  return self;
}

/**
 * Returns the maximum unsigned integer value.
 */
+ (unsigned int) retainCount
{
  return UINT_MAX;
}

/**
 * Returns the superclass of the receiver.
 */
+ (Class) superclass
{
  return GSObjCSuper(self);
}

/**
 * Adds the receiver to the current autorelease pool and returns self.
 */
- (id) autorelease
{
#if	GS_WITH_GC == 0
  [NSAutoreleasePool addObject: self];
#endif
  return self;
}

/**
 * Dummy method ... returns the receiver.
 */
- (id) awakeAfterUsingCoder: (NSCoder*)aDecoder
{
  return self;
}

/**
 * Returns the class of the receiver.
 */
- (Class) class
{
  return object_get_class(self);
}

/**
 * Calls the -forwardInvocation: method to determine if the 'real' object
 * referred to by the proxy conforms to aProtocol.  Returns the result.<br />
 * NB. The default operation of -forwardInvocation: is to raise an exception.
 */
- (BOOL) conformsToProtocol: (Protocol*)aProtocol
{
  NSMethodSignature	*sig;
  NSInvocation		*inv;
  BOOL			ret;

  sig = [self methodSignatureForSelector: _cmd];
  inv = [NSInvocation invocationWithMethodSignature: sig];
  [inv setSelector: _cmd];
  [inv setArgument: &aProtocol atIndex: 2];
  [self forwardInvocation: inv];
  [inv getReturnValue: &ret];
  return ret;
}

/**
 * Frees the memory used by the receiver.
 */
- (void) dealloc
{
  NSDeallocateObject((NSObject*)self);
}

/**
 * Returns a text descrioption of the receiver.
 */
- (NSString*) description
{
  return [NSString stringWithFormat: @"<%s %lx>",
	GSClassNameFromObject(self), (unsigned long)self];
}

/**
 * Calls the -forwardInvocation: method and returns the result.
 */
- (retval_t) forward:(SEL)aSel :(arglist_t)argFrame
{
  NSInvocation *inv;

  inv = AUTORELEASE([[NSInvocation alloc] initWithArgframe: argFrame
						  selector: aSel]);
  [self forwardInvocation: inv];
  return [inv returnFrame: argFrame];
}

/** <override-subclass />
 * Raises an <code>NSInvalidArgumentException</code>.
 */
- (void) forwardInvocation: (NSInvocation*)anInvocation
{
  [NSException raise: NSInvalidArgumentException
	      format: @"NSProxy should not implement '%s'",
				GSNameFromSelector(_cmd)];
}

/**
 * Returns the address of the receiver ... so it can be stored in a dictionary.
 */
- (unsigned int) hash
{
  /*
   * Ideally we would shift left to lose any zero bits produced by the
   * alignment of the object in memory ... but that depends on the
   * processor architecture and the memory allocatiion implementation.
   * In the absence of detailed information, pick a reasonable value
   * assuming the object will be aligned to an eight byte boundary.
   */
  return ((unsigned)self)>>3;
}

/** <init /> <override-subclass />
 * Initialises the receiver and returns the resulting instance.
 */
- (id) init
{
  [NSException raise: NSGenericException
    format: @"subclass %s should override %s", GSClassNameFromObject(self),
    GSNameFromSelector(_cmd)];
  return self;
}

/**
 * Tests for pointer equality with anObject.
 */
- (BOOL) isEqual: (id)anObject
{
  return (self == anObject);
}

/**
 * Calls the -forwardInvocation: method to determine if the 'real' object
 * referred to by the proxy is an instance of the specified class.
 * Returns the result.<br />
 * NB. The default operation of -forwardInvocation: is to raise an exception.
 */
- (BOOL) isKindOfClass: (Class)aClass
{
  NSMethodSignature	*sig;
  NSInvocation		*inv;
  BOOL			ret;

  sig = [self methodSignatureForSelector: _cmd];
  inv = [NSInvocation invocationWithMethodSignature: sig];
  [inv setSelector: _cmd];
  [inv setArgument: &aClass atIndex: 2];
  [self forwardInvocation: inv];
  [inv getReturnValue: &ret];
  return ret;
}

/**
 * Calls the -forwardInvocation: method to determine if the 'real' object
 * referred to by the proxy is an instance of the specified class.
 * Returns the result.<br />
 * NB. The default operation of -forwardInvocation: is to raise an exception.
 */
- (BOOL) isMemberOfClass: (Class)aClass
{
  NSMethodSignature	*sig;
  NSInvocation		*inv;
  BOOL			ret;

  sig = [self methodSignatureForSelector: _cmd];
  inv = [NSInvocation invocationWithMethodSignature: sig];
  [inv setSelector: _cmd];
  [inv setArgument: &aClass atIndex: 2];
  [self forwardInvocation: inv];
  [inv getReturnValue: &ret];
  return ret;
}

/**
 * Returns YES.
 */
- (BOOL) isProxy
{
  return YES;
}

- (id) notImplemented: (SEL)aSel
{
  [NSException raise: NSGenericException
	      format: @"NSProxy notImplemented %s", GSNameFromSelector(aSel)];
  return self;
}

/**
 * If we respond to the method directly, create and return a method
 * signature.  Otherwise raise an exception.
 */
- (NSMethodSignature*) methodSignatureForSelector: (SEL)aSelector
{
  struct objc_method	*mth;

  if (aSelector == 0)
    {
      return nil;
    }
  mth = GSGetMethod(GSObjCClass(self), aSelector, YES, YES);
  if (mth != 0)
    {
      const char	*types = mth->method_types;

      if (types != 0)
	{
	  return [NSMethodSignature signatureWithObjCTypes: types];
	}
    }
  [NSException raise: NSInvalidArgumentException format:
    @"NSProxy should not implement 'methodSignatureForSelector:'"];
  return nil;
}

- (id) performSelector: (SEL)aSelector
{
  IMP msg = objc_msg_lookup(self, aSelector);

  if (!msg)
    {
      [NSException raise: NSGenericException
		  format: @"invalid selector passed to %s",
				GSNameFromSelector(_cmd)];
      return nil;
    }
  return (*msg)(self, aSelector);
}

- (id) performSelector: (SEL)aSelector
	    withObject: (id)anObject
{
  IMP msg = objc_msg_lookup(self, aSelector);

  if (!msg)
    {
      [NSException raise: NSGenericException
		  format: @"invalid selector passed to %s",
				GSNameFromSelector(_cmd)];
      return nil;
    }
  return (*msg)(self, aSelector, anObject);
}

- (id) performSelector: (SEL)aSelector
	    withObject: (id)anObject
	    withObject: (id)anotherObject
{
  IMP msg = objc_msg_lookup(self, aSelector);

  if (!msg)
    {
      [NSException raise: NSGenericException
		  format: @"invalid selector passed to %s",
				GSNameFromSelector(_cmd)];
      return nil;
    }
  return (*msg)(self, aSelector, anObject, anotherObject);
}

/**
 * Decrement the retain count for the receiver ... deallocate if it would
 * become negative.
 */
- (void) release
{
#if	GS_WITH_GC == 0
  if (_retain_count == 0)
    {
      [self dealloc];
    }
  else
    {
      _retain_count--;
    }
#endif
}

/**
 * Returns the actual object to be encoded for sending over the
 * network on a Distributed Objects connection.
 */
- (id) replacementObjectForPortCoder: (NSPortCoder*)aCoder
{
  static Class	proxyClass = 0;
  static IMP	proxyImp = 0;

  if (proxyImp == 0)
    {
      proxyClass = [NSDistantObject class];
      /*
       * use get_imp() because NSDistantObject doesn't implement
       * methodForSelector:
       */
      proxyImp = get_imp(GSObjCClass((id)proxyClass),
	@selector(proxyWithLocal:connection:));
    }

  return (*proxyImp)(proxyClass, @selector(proxyWithLocal:connection:),
    self, [aCoder connection]);
}

/**
 * If we respond to the method directly, return YES, otherwise
 * forward this request to the object we are acting as a proxy for.
 */
- (BOOL) respondsToSelector: (SEL)aSelector
{
  if (aSelector == 0)
    {
      return NO;
    }
  if (__objc_responds_to(self, aSelector))
    {
      return YES;
    }
  else
    {
      NSMethodSignature	*sig;
      NSInvocation	*inv;
      BOOL		ret;

      sig = [self methodSignatureForSelector: _cmd];
      inv = [NSInvocation invocationWithMethodSignature: sig];
      [inv setSelector: _cmd];
      [inv setArgument: &aSelector atIndex: 2];
      [self forwardInvocation: inv];
      [inv getReturnValue: &ret];
      return ret;
    }
}

/**
 * Increment the retain count for the receiver.
 */
- (id) retain
{
#if	GS_WITH_GC == 0
  _retain_count++;
#endif
  return self;
}

/**
 * Return the retain count for the receiver.
 */
- (unsigned int) retainCount
{
  return _retain_count + 1;
}

/**
 * Returns the receiver.
 */
- (id) self
{
  return self;
}

/**
 * Returns the superclass of the receiver's class.
 */
- (Class) superclass
{
  return object_get_super_class(self);
}

/**
 * Returns the zone in which the receiver was allocated.
 */
- (NSZone*) zone
{
  return NSZoneFromPointer(self);
}

@end

