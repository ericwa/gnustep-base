/** Implementation of NSInvocation for GNUStep
   Copyright (C) 1998,2003 Free Software Foundation, Inc.

   Author:     Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Date: August 1998
   Based on code by: Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>

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
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.

   <title>NSInvocation class reference</title>
   $Date$ $Revision$
   */

#include "Foundation/NSException.h"
#include "Foundation/NSCoder.h"
#include "Foundation/NSInvocation.h"
#include "GSInvocation.h"
#include "config.h"
#include <mframe.h>
#if defined(USE_LIBFFI)
#include "cifframe.h"
#elif defined(USE_FFCALL)
#include "callframe.h"
#endif

static Class   NSInvocation_abstract_class;
static Class   NSInvocation_concrete_class;

@interface GSInvocationProxy
{
@public
  Class		isa;
  id		target;
  NSInvocation	*invocation;
}
+ (id) _newWithTarget: (id)t;
- (NSInvocation*) _invocation;
- (void) forwardInvocation: (NSInvocation*)anInvocation;
- (NSMethodSignature*) methodSignatureForSelector: (SEL)aSelector;
@end
@interface GSMessageProxy : GSInvocationProxy
@end



/**
 * <p>The <code>NSInvocation</code> class implements a mechanism of constructing
 * messages (as <code>NSInvocation</code> instances), sending these to other
 * objects, and handling the returned values.
 * </p>
 * <p>An <code>NSInvocation</code> object may contain a target object to which a
 * message can be sent, or may send the message to an arbitrary object.<br />
 * Each message consists of a selector for that method and an argument
 * list.  Once the message has been sent, the invocation will contain
 * a return value whose contents may be copied out of it.
 * </p>
 * <p>The target, selector, and arguments of an instance be constructed
 * dynamically, providing a great deal of power/flexibility.
 * </p>
 * <p>The sending of the message to the target object (using the -invoke
 * or -invokeWithTarget: method) can be done at any time, but a standard
 * use of this is by the [NSObject-forwardInvocation:] method which is
 * called whenever a method is not implemented by the class of the
 * object to which it was sent.
 * </p>
 * <p>Related to the class are two convenience macros ... NS_MESSAGE()
 * and NS_INVOCATION() ... to allow easy construction of invocations
 * with all the arguments set up.
 * </p>
 */
@implementation NSInvocation

#ifdef USE_LIBFFI
static inline void
_get_arg(NSInvocation *inv, int index, void *buffer)
{
  cifframe_get_arg((cifframe_t *)inv->_cframe, index, buffer,
		   inv->_info[index+1].size);
}

static inline void
_set_arg(NSInvocation *inv, int index, void *buffer)
{
  cifframe_set_arg((cifframe_t *)inv->_cframe, index, buffer,
		   inv->_info[index+1].size);
}

static inline void *
_arg_addr(NSInvocation *inv, int index)
{
  return cifframe_arg_addr((cifframe_t *)inv->_cframe, index);
}

#elif defined(USE_FFCALL)
static inline void
_get_arg(NSInvocation *inv, int index, void *buffer)
{
  callframe_get_arg((callframe_t *)inv->_cframe, index, buffer,
		    inv->_info[index+1].size);
}

static inline void
_set_arg(NSInvocation *inv, int index, void *buffer)
{
  callframe_set_arg((callframe_t *)inv->_cframe, index, buffer,
		    inv->_info[index+1].size);
}

static inline void *
_arg_addr(NSInvocation *inv, int index)
{
  return callframe_arg_addr((callframe_t *)inv->_cframe, index);
}

#else
static inline void
_get_arg(NSInvocation *inv, int index, void *buffer)
{
  mframe_get_arg((arglist_t)inv->_cframe, &inv->_info[index+1], buffer);
}

static inline void
_set_arg(NSInvocation *inv, int index, void *buffer)
{
  mframe_set_arg((arglist_t)inv->_cframe, &inv->_info[index+1], buffer);
}

static inline void *
_arg_addr(NSInvocation *inv, int index)
{
  return mframe_arg_addr((arglist_t)inv->_cframe, &inv->_info[index+1]);
}

#endif

+ (id) allocWithZone: (NSZone*)aZone
{
  if (self == NSInvocation_abstract_class)
    {
      return NSAllocateObject(NSInvocation_concrete_class, 0, aZone);
    }
  else
    {
      return NSAllocateObject(self, 0, aZone);
    }
}

+ (void) initialize
{
  if (self == [NSInvocation class])
    {
      NSInvocation_abstract_class = self;
#if defined(USE_LIBFFI)
      NSInvocation_concrete_class = [GSFFIInvocation class];
#elif defined(USE_FFCALL)
      NSInvocation_concrete_class = [GSFFCallInvocation class];
#else
      NSInvocation_concrete_class = [GSFrameInvocation class];
#endif
    }
}

/**
 * Returns an invocation instance which can be used to send messages to
 * a target object using the described signature.<br />
 * You must set the target and selector (using -setTarget: and -setSelector:)
 * before you attempt to use the invocation.<br />
 * Raises an NSInvalidArgumentException if the signature is nil.
 */
+ (NSInvocation*) invocationWithMethodSignature: (NSMethodSignature*)_signature
{
  return AUTORELEASE([[NSInvocation_concrete_class alloc]
    initWithMethodSignature: _signature]);
}

- (void) dealloc
{
  if (_targetRetained)
    {
      _targetRetained = NO;
      RELEASE(_target);
    }
  if (_argsRetained)
    {
      _argsRetained = NO;
      if (_cframe && _sig)
	{
	  unsigned int	i;

	  for (i = 3; i <= _numArgs; i++)
	    {
	      if (*_info[i].type == _C_CHARPTR)
		{
		  char	*str;

		  _get_arg(self, i-1, &str);
		  NSZoneFree(NSDefaultMallocZone(), str);
		}
	      else if (*_info[i].type == _C_ID)
		{
		  id	obj;

		  _get_arg(self, i-1, &obj);
		  RELEASE(obj);
		}
	    }
	}
    }


  CLEAR_RETURN_VALUE_IF_OBJECT;

#if	defined(USE_LIBFFI)
  if (_cframe)
    {
      NSZoneFree(NSDefaultMallocZone(), _cframe);
      _retval = 0;	// Part of _cframe
    }
#elif defined(USE_FFCALL)
  if (_cframe)
    {
      NSZoneFree(NSDefaultMallocZone(), _cframe);
      _retval = 0;	// Part of _cframe
    }
#else
  if (_cframe)
    {
      mframe_destroy_argframe([_sig methodType], (arglist_t)_cframe);
    }
  if (_retval)
    {
      NSZoneFree(NSDefaultMallocZone(), _retval);
    }
#endif
  RELEASE(_sig);
  [super dealloc];
}

/**
 * Copies the argument identified by index into the memory location specified
 * by the buffer argument.<br />
 * An index of zero is the target object, an index of one is the selector,
 * so the actual method arguments start at index 2.
 */
- (void) getArgument: (void*)buffer
	     atIndex: (int)index
{
  if ((unsigned)index >= _numArgs)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"bad invocation argument index"];
    }
  if (index == 0)
    {
      *(id*)buffer = _target;
    }
  else if (index == 1)
    {
      *(SEL*)buffer = _selector;
    }
  else
    {
      _get_arg(self, index, buffer);
    }		
}

/**
 * Copies the invocations return value to the location pointed to by buffer
 * if a return value has been set (see the -setReturnValue: method).<br />
 * If there isn't a return value then this method raises an exception.
 */
- (void) getReturnValue: (void*)buffer
{
  const char	*type;

  if (_validReturn == NO)
    {
      [NSException raise: NSGenericException
		  format: @"getReturnValue with no value set"];
    }

  type = [_sig methodReturnType];

  if (*_info[0].type != _C_VOID)
    {
      int	length = _info[0].size;
#if !defined(USE_LIBFFI) && !defined(USE_FFCALL)
/* NOTE: This won't work unless -[NSMethodSignature methodReturnLength]
   is also changed, but since mframe is depreciated, this should all
   be removed in the near future anyway... */
#if WORDS_BIGENDIAN
      if (length < sizeof(void*))
	length = sizeof(void*);
#endif
#endif
      memcpy(buffer, _retval, length);
    }
}

/**
 * Returns the selector of the invocation (the argument at index 1)
 */
- (SEL) selector
{
  return _selector;
}

/**
 * Sets the argument identified by index from the memory location specified
 * by the buffer argument.<br />
 * Using an index of 0 is equivalent to calling -setTarget: and using an
 * argument of 1 is equivalent to -setSelector:<br />
 * Proper arguments start at index 2.<br />
 * NB. Unlike -setTarget: and -setSelector: the value of buffer must be
 * <em>a pointer to</em> the argument to be set in the invocation.<br />
 * If -retainArguments was called, then any object argument set in the
 * receiver is retained by it.
 */
- (void) setArgument: (void*)buffer
	     atIndex: (int)index
{
  if ((unsigned)index >= _numArgs)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"bad invocation argument index"];
    }
  if (index == 0)
    {
      [self setTarget: *(id*)buffer];
    }
  else if (index == 1)
    {
      [self setSelector: *(SEL*)buffer];
    }
  else
    {
      int		i = index+1;	/* Allow for return type in '_info' */
      const char	*type = _info[i].type;

      if (_argsRetained && (*type == _C_ID || *type == _C_CHARPTR))
	{
	  if (*type == _C_ID)
	    {
	      id	old;

	      _get_arg(self, index, &old);
	      _set_arg(self, index, buffer);
	      IF_NO_GC(RETAIN(*(id*)buffer));
	      if (old != nil)
		{
		  RELEASE(old);
		}
	    }
	  else
	    {
	      char	*oldstr;
	      char	*newstr = *(char**)buffer;

	      _get_arg(self, index, &oldstr);
	      if (newstr == 0)
		{
		  _set_arg(self, index, buffer);
		}
	      else
		{
		  char	*tmp;

		  tmp = NSZoneMalloc(NSDefaultMallocZone(), strlen(newstr)+1);
		  strcpy(tmp, newstr);
		  _set_arg(self, index, tmp);
		}
	      if (oldstr != 0)
		{
		  NSZoneFree(NSDefaultMallocZone(), oldstr);
		}
	    }
	}
      else
	{
	  _set_arg(self, index, buffer);
	}
    }		
}

/**
 * Sets the return value of the invocation to the item that buffer points to.
 */
- (void) setReturnValue: (void*)buffer
{
  const char	*type;

  type = _info[0].type;

  CLEAR_RETURN_VALUE_IF_OBJECT;

  if (*type != _C_VOID)
    {
      int	length = _info[0].size;

#if !defined(USE_LIBFFI) && !defined(USE_FFCALL)
/* NOTE: This won't work unless -[NSMethodSignature methodReturnLength]
   is also changed, but since mframe is depreciated, this should all
   be removed in the near future anyway... */
#if WORDS_BIGENDIAN
      if (length < sizeof(void*))
	length = sizeof(void*);
#endif
#endif
      memcpy(_retval, buffer, length);
    }

  RETAIN_RETURN_VALUE;
  _validReturn = YES;
}

/**
 * Sets the selector for the invocation.
 */
- (void) setSelector: (SEL)aSelector
{
  _selector = aSelector;
}

/**
 * Sets the target object for the invocation.<br />
 * If -retainArguments was called, then the target is retained.
 */
- (void) setTarget: (id)anObject
{
  if (_targetRetained)
    {
      ASSIGN(_target, anObject);
    }
  else
    {
      _target = anObject;
    }
}

/**
 * Returns the target object of the invocation.
 */
- (id) target
{
  return _target;
}

/**
 * Returns a flag to indicate whether object arguments of the invocation
 * (including its target) are retained by the invocation.
 */
- (BOOL) argumentsRetained
{
  return _argsRetained;
}

/**
 * Instructs the invocation to retain its object arguments (including the
 * target). The default is not to retain them.
 */
- (void) retainArguments
{
  [self retainArgumentsIncludingTarget: YES];
}

/**
 * Returns YES if target has been retained yet, NO otherwise.
 */
- (BOOL) targetRetained
{
  return _targetRetained;
}

/**
 * Similar to -[NSInvocation retainArguments], but allows the sender to
 * explicitly control whether the target is retained as well. Retaining
 * the target is sometimes not desirable (such as in NSUndoManager), as
 * retain loops could result.
 */
- (void) retainArgumentsIncludingTarget: (BOOL)retainTargetFlag
{
  if (_argsRetained == NO)
    {
      unsigned int	i;

      _argsRetained = YES;
      if (_cframe == 0)
	{
	  return;
	}
      for (i = 3; i <= _numArgs; i++)
	{
	  if (*_info[i].type == _C_ID)
	    {
              id        old;

	      _get_arg(self, i-1, &old);
	      if (old != nil)
		{
		  IF_NO_GC(RETAIN(old));
		}
            }
	  else if (*_info[i].type == _C_CHARPTR)
	    {
	      char      *str;

	      _get_arg(self, i-1, &str);
	      if (str != 0)
	        {
		  char  *tmp;

		  tmp = NSZoneMalloc(NSDefaultMallocZone(), strlen(str)+1);
		  strcpy(tmp, str);
		  _set_arg(self, i-1, &tmp);
		}
	    }
	}
    }

  if (retainTargetFlag && _targetRetained == NO)
    {
      _targetRetained = YES;

      IF_NO_GC(RETAIN(_target));
    }
}

/**
 * Sends the message encapsulated in the invocation to its target.
 */
- (void) invoke
{
  [self invokeWithTarget: _target];
}

/**
 * Sends the message encapsulated in the invocation to anObject.
 */
- (void) invokeWithTarget: (id)anObject
{
  id		old_target;
  retval_t	returned;
  IMP		imp;
  int		stack_argsize;


  CLEAR_RETURN_VALUE_IF_OBJECT;
  _validReturn = NO;

  /*
   *	A message to a nil object returns nil.
   */
  if (anObject == nil)
    {
      _validReturn = YES;
      memset(_retval, '\0', _info[0].size);	/* Clear return value */
      return;
    }

  NSAssert(_selector != 0, @"you must set the selector before invoking");

  /*
   *	Temporarily set new target and copy it (and the selector) into the
   *	_cframe.
   */
  old_target = RETAIN(_target);
  [self setTarget: anObject];

  _set_arg(self, 0, &_target);
  _set_arg(self, 1, &_selector);

  if (_sendToSuper == YES)
    {
      Super	s;

#ifndef NeXT_RUNTIME
      s.self = _target;
#else
      s.receiver = _target;
#endif
      if (GSObjCIsInstance(_target))
	s.class = GSObjCSuper(GSObjCClass(_target));
      else
	s.class = GSObjCSuper((Class)_target);
      imp = objc_msg_lookup_super(&s, _selector);
    }
  else
    {
      GSMethod method;
      method = GSGetMethod((GSObjCIsInstance(_target)
			    ? (id)GSObjCClass(_target)
			    : (id)_target),
			   _selector,
			   GSObjCIsInstance(_target),
			   YES);
      imp = method_get_imp(method);
	/*
	 * If fast lookup failed, we may be forwarding or something ...
	 */
      if (imp == 0)
	imp = objc_msg_lookup(_target, _selector);
    }
  [self setTarget: old_target];
  RELEASE(old_target);

  stack_argsize = [_sig frameLength];

  returned = __builtin_apply((void(*)(void))imp,
    (arglist_t)_cframe, stack_argsize);
  if (_info[0].size)
    {
      mframe_decode_return(_info[0].type, _retval, returned);
    }

  RETAIN_RETURN_VALUE;
  _validReturn = YES;
}

/**
 * Returns the method signature of the invocation.
 */
- (NSMethodSignature*) methodSignature
{
  return _sig;
}

- (NSString*) description
{
  /*
   *	Don't use -[NSString stringWithFormat:] method because it can cause
   *	infinite recursion.
   */
  char buffer[1024];

  snprintf (buffer, 1024, "<%s %p selector: %s target: %s>", \
                GSClassNameFromObject(self), \
                self, \
                _selector ? GSNameFromSelector(_selector) : "nil", \
                _target ?   GSNameFromClass([_target class]) : "nil" \
               );

  return [NSString stringWithCString: buffer];
}

- (void) encodeWithCoder: (NSCoder*)aCoder
{
  const char	*types = [_sig methodType];
  unsigned int	i;

  [aCoder encodeValueOfObjCType: @encode(char*)
			     at: &types];

  [aCoder encodeObject: _target];

  [aCoder encodeValueOfObjCType: _info[2].type
			     at: &_selector];

  for (i = 3; i <= _numArgs; i++)
    {
      const char	*type = _info[i].type;
      void		*datum;

      datum = _arg_addr(self, i-1);

      if (*type == _C_ID)
	{
	  [aCoder encodeObject: *(id*)datum];
	}
#if !defined(USE_LIBFFI) && !defined(USE_FFCALL)
#if     MFRAME_STRUCT_BYREF
      else if (*type == _C_STRUCT_B || *type == _C_UNION_B || *type == _C_ARY_B)
        {
	  [aCoder encodeValueOfObjCType: type at: *(void**)datum];
        }
#endif
#endif
      else
	{
	  [aCoder encodeValueOfObjCType: type at: datum];
	}
    }
  if (*_info[0].type != _C_VOID)
    {
      [aCoder encodeValueOfObjCType: @encode(BOOL) at: &_validReturn];
      if (_validReturn)
	{
	  [aCoder encodeValueOfObjCType: _info[0].type at: _retval];
	}
    }
}

- (id) initWithCoder: (NSCoder*)aCoder
{
  NSMethodSignature	*newSig;
  const char		*types;
  void			*datum;
  unsigned int		i;

  [aCoder decodeValueOfObjCType: @encode(char*) at: &types];
  newSig = [NSMethodSignature signatureWithObjCTypes: types];
  NSZoneFree(NSDefaultMallocZone(), (void*)types);

  RELEASE(self);
  self  = [NSInvocation invocationWithMethodSignature: newSig];
  RETAIN(self);

  [aCoder decodeValueOfObjCType: @encode(id) at: &_target];

  [aCoder decodeValueOfObjCType: @encode(SEL) at: &_selector];

  for (i = 3; i <= _numArgs; i++)
    {
      datum = _arg_addr(self, i-1);
#if !defined(USE_LIBFFI) && !defined(USE_FFCALL)
#if     MFRAME_STRUCT_BYREF
      {
        const char      *t = _info[i].type;
        if (*t == _C_STRUCT_B || *t == _C_UNION_B || *t == _C_ARY_B)
          {
	    *(void**)datum = GSAutoreleasedBuffer(_info[i].size);
            datum = *(void**)datum;
          }
      }
#endif
#endif
      [aCoder decodeValueOfObjCType: _info[i].type at: datum];
    }
  _argsRetained = YES;
  if (*_info[0].type != _C_VOID)
    {
      [aCoder decodeValueOfObjCType: @encode(BOOL) at: &_validReturn];
      if (_validReturn)
        {
          [aCoder decodeValueOfObjCType: _info[0].type at: _retval];
        }
    }
  return self;
}

@end

/**
 * Provides some minor extensions and some utility methods to aid
 * integration of <code>NSInvocation</code> with the Objective-C runtime.
 */
@implementation NSInvocation (GNUstep)

- (BOOL) sendsToSuper
{
  return _sendToSuper;
}

- (void) setSendsToSuper: (BOOL)flag
{
  _sendToSuper = flag;
}
@end

/**
 * These methods are for internal use only ... not public API<br />
 * They are used by the NS_INVOCATION() and NS_MESSAGE() macros to help
 * create invocations.
 */
@implementation NSInvocation (MacroSetup)
/**
 * Internal use.<br />
 * Initialises the receiver with a known selector and argument list
 * as supplied to the forward:: method by the ObjectiveC runtime
 * when it is unable to locate an implementation for the selector
 * in a class.
 */
- (id) initWithArgframe: (arglist_t)frame selector: (SEL)aSelector
{
  [self subclassResponsibility: _cmd];
  return nil;
}

/** <init /><override-subclass />
 * Initialised an invocation instance which can be used to send messages to
 * a target object using aSignature.<br />
 * You must set the target and selector (using -setTarget: and -setSelector:)
 * before you attempt to use the invocation.<br />
 * Raises an NSInvalidArgumentException if aSignature is nil.
 */
- (id) initWithMethodSignature: (NSMethodSignature*)aSignature
{
  [self subclassResponsibility: _cmd];
  return nil;
}

/**
 * Tries to produce a method signature based on aSelector and uses that to
 * initialise self by calling the -initWithMethodSignature: method.<br />
 * If the argument type of aSelector cannot be determined, this releases self
 * and returns nil.
 */
- (id) initWithSelector: (SEL)aSelector
{
  const char *types;
  NSMethodSignature *newSig;

  types = sel_get_type(aSelector);
  if (types == 0)
    {
      types = sel_get_type(sel_get_any_typed_uid(GSNameFromSelector(aSelector)));
    }
  if (types == 0)
    {
      NSLog(@"Couldn't find encoding type for selector %s.",
	   GSNameFromSelector(aSelector));
      RELEASE(self);
      return nil;
    }
  newSig = [NSMethodSignature signatureWithObjCTypes: types];
  return [self initWithMethodSignature: newSig];
}

/**
 * Initialises the receiver with the specified target, selector, and
 * a variable number of arguments.
 */
- (id) initWithTarget: anObject selector: (SEL)aSelector, ...
{
  va_list	     ap;
  NSMethodSignature *newSig;

  if (anObject)
    {
      newSig = [anObject methodSignatureForSelector: aSelector];
      self = [self initWithMethodSignature: newSig];
    }
  else
    {
      self = [self initWithSelector: aSelector];
    }
  if (self)
    {
      unsigned int	i;

      [self setTarget: anObject];
      [self setSelector: aSelector];
      va_start (ap, aSelector);
      for (i = 3; i <= _numArgs; i++)
	{
	  const char	*type = _info[i].type;
	  unsigned	size = _info[i].size;
	  void		*datum;

	  datum = _arg_addr(self, i-1);

#define CASE_TYPE(_C,_T) case _C: *(_T*)datum = va_arg (ap, _T); break
	  switch (*type)
	    {
	      case _C_ID:
		*(id*)datum = va_arg (ap, id);
		if (_argsRetained)
		  {
		    IF_NO_GC(RETAIN(*(id*)datum));
		  }
		break;
	      case _C_CHARPTR:
		*(char**)datum = va_arg (ap, char*);
		if (_argsRetained)
		  {
		    char	*old = *(char**)datum;

		    if (old != 0)
		      {
			char	*tmp;

			tmp = NSZoneMalloc(NSDefaultMallocZone(),strlen(old)+1);
			strcpy(tmp, old);
			*(char**)datum = tmp;
		      }
		  }
		break;
	      CASE_TYPE(_C_CLASS, Class);
	      CASE_TYPE(_C_SEL, SEL);
	      CASE_TYPE(_C_LNG, long);
	      CASE_TYPE(_C_ULNG, unsigned long);
	      CASE_TYPE(_C_INT, int);
	      CASE_TYPE(_C_UINT, unsigned int);
	      case _C_SHT:
		*(short*)datum = (short)va_arg(ap, int);
		break;
	      case _C_USHT:
		*(unsigned short*)datum = (unsigned short)va_arg(ap, int);
		break;
	      case _C_CHR:
		*(char*)datum = (char)va_arg(ap, int);
		break;
	      case _C_UCHR:
		*(unsigned char*)datum = (unsigned char)va_arg(ap, int);
		break;
	      case _C_FLT:
		*(float*)datum = (float)va_arg(ap, double);
		break;
	      CASE_TYPE(_C_DBL, double);
	      CASE_TYPE(_C_PTR, void*);
	      case _C_STRUCT_B:
	      default:
#if !defined(USE_LIBFFI) && !defined(USE_FFCALL)
#if defined(sparc) || defined(powerpc)
		/* FIXME: This only appears on sparc and ppc machines so far.
		structures appear to be aligned on word boundaries.
		Hopefully there is a more general way to figure this out */
		size = (size<sizeof(int))?4:size;
#endif
#endif
	      NSLog(@"Unsafe handling of type of %d argument.", i-1);
	      {
		struct {
		  char	x[size];
		} dummy;
		dummy = va_arg(ap, typeof(dummy));
	        memcpy(datum, dummy.x, size);
	      }
	      break;
	    }
	}
    }
  return self;
}

/**
 * Internal use.<br />
 * Provides a return frame that the ObjectiveC runtime can use to
 * return the result of an invocation to a calling function.
 */
- (void*) returnFrame: (arglist_t)argFrame
{
  [self subclassResponsibility: _cmd];
  return NULL;
}

+ (id) _newProxyForInvocation: (id)target
{
  return [GSInvocationProxy _newWithTarget: target];
}
+ (id) _newProxyForMessage: (id)target
{
  return [GSMessageProxy _newWithTarget: target];
}
+ (NSInvocation*) _returnInvocationAndDestroyProxy: (id)proxy
{
  NSInvocation	*inv = [proxy _invocation];
  NSDeallocateObject(proxy);
  return inv;
}
@end

@implementation NSInvocation (BackwardCompatibility)

- (void) invokeWithObject: (id)obj
{
  [self invokeWithTarget: (id)obj];
}

@end

@implementation GSFrameInvocation

- (id) initWithArgframe: (arglist_t)frame selector: (SEL)aSelector
{
  self = [self initWithSelector: aSelector];
  if (self)
    {
      [self setSelector: aSelector];
      /*
       *	Copy the _cframe we were given.
       */
      if (frame)
	{
	  unsigned int	i;

	  mframe_get_arg(frame, &_info[1], &_target);
	  for (i = 1; i <= _numArgs; i++)
	    {
	      mframe_cpy_arg((arglist_t)_cframe, frame, &_info[i]);
	    }
	}
    }
  return self;
}

/*
 *	This is the de_signated initialiser.
 */
- (id) initWithMethodSignature: (NSMethodSignature*)aSignature
{
  if (aSignature == nil)
    {
      RELEASE(self);
      return nil;
    }
  _sig = RETAIN(aSignature);
  _numArgs = [aSignature numberOfArguments];
  _info = [aSignature methodInfo];
  _cframe = mframe_create_argframe([_sig methodType], &_retval);
  if (_retval == 0 && _info[0].size > 0)
    {
      _retval = NSZoneMalloc(NSDefaultMallocZone(), _info[0].size);
    }
  return self;
}

- (void*) returnFrame: (arglist_t)argFrame
{
  return mframe_handle_return(_info[0].type, _retval, argFrame);
}
@end


@implementation	GSInvocationProxy
+ (id) _newWithTarget: (id)t
{
  GSInvocationProxy	*o;
  o = (GSInvocationProxy*) NSAllocateObject(self, 0, NSDefaultMallocZone());
  o->target = RETAIN(t);
  return o;
}
- (NSInvocation*) _invocation
{
  return invocation;
}
- (retval_t) forward: (SEL)aSel : (arglist_t)argFrame
{
  NSInvocation	*inv;

  if (aSel == 0)
    [NSException raise: NSInvalidArgumentException
		format: @"%@ null selector given", NSStringFromSelector(_cmd)];

  inv = AUTORELEASE([[NSInvocation alloc] initWithArgframe: argFrame
						  selector: aSel]);
  [self forwardInvocation: inv];
  return [inv returnFrame: argFrame];
}
- (void) forwardInvocation: (NSInvocation*)anInvocation
{
  invocation = anInvocation;
}
- (NSMethodSignature*) methodSignatureForSelector: (SEL)aSelector
{
  return [target methodSignatureForSelector: aSelector];
}
@end

@implementation	GSMessageProxy
- (NSInvocation*) _invocation
{
  [invocation setTarget: target];
  return invocation;
}
@end
