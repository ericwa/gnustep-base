/* Interface for NSInvocation for GNUStep
   Copyright (C) 1998 Free Software Foundation, Inc.

   Written:	Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Date: 1998
   Based on code by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   
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
   */ 

#ifndef __NSInvocation_h_GNUSTEP_BASE_INCLUDE
#define __NSInvocation_h_GNUSTEP_BASE_INCLUDE

#include <Foundation/NSMethodSignature.h>


@interface NSInvocation : NSObject
{
  NSMethodSignature	*_sig;
  void                  *_cframe;
  void			*_retval;
  id			_target;
  SEL			_selector;
  unsigned int		_numArgs;
#ifndef	STRICT_MACOS_X
  NSArgumentInfo	*_info;
#else
  void			*_dummy;
#endif
  BOOL			_argsRetained;
  BOOL			_validReturn;
  BOOL			_sendToSuper;
}

/*
 *	Creating instances.
 */
+ (NSInvocation*) invocationWithMethodSignature: (NSMethodSignature*)_signature;

/*
 *	Accessing message elements.
 */
- (void) getArgument: (void*)buffer
	     atIndex: (int)index;
- (void) getReturnValue: (void*)buffer;
- (SEL) selector;
- (void) setArgument: (void*)buffer
	     atIndex: (int)index;
- (void) setReturnValue: (void*)buffer;
- (void) setSelector: (SEL)aSelector;
- (void) setTarget: (id)anObject;
- (id) target;

/*
 *	Managing arguments.
 */
- (BOOL) argumentsRetained;
- (void) retainArguments;

/*
 *	Dispatching an Invocation.
 */
- (void) invoke;
- (void) invokeWithTarget: (id)anObject;

/*
 *	Getting the method signature.
 */
- (NSMethodSignature*) methodSignature;

@end

#ifndef	NO_GNUSTEP
@interface NSInvocation (GNUstep)
- (id) initWithArgframe: (arglist_t)frame selector: (SEL)aSelector;
- (id) initWithMethodSignature: (NSMethodSignature*)aSignature;
- (id) initWithSelector: (SEL)aSelector;
- (id) initWithTarget: (id)anObject selector: (SEL)aSelector, ...;
- (void*) returnFrame: (arglist_t)argFrame;
- (BOOL) sendsToSuper;
- (void) setSendsToSuper: (BOOL)flag;
@end
#endif

#endif /* __NSInvocation_h_GNUSTEP_BASE_INCLUDE */

