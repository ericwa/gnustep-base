/** NSAssertionHandler - Object encapsulation of assertions
   Copyright (C) 1995, 1997 Free Software Foundation, Inc.
   
   Written by:  Adam Fedor <fedor@boulder.colorado.edu>
   Date: Apr 1995
   
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

   <title>NSAssertionHandler class reference</title>
   $Date$ $Revision$
   */

#include "config.h"
#include "gnustep/base/preface.h"
#include "Foundation/NSException.h"
#include "Foundation/NSDictionary.h"
#include "Foundation/NSObjCRuntime.h"
#include "Foundation/NSString.h"
#include "Foundation/NSThread.h"

/**
 * <p>NSAssertionHandler objects are used to raise exceptions on behalf of
 * macros implementing assertions.<br />
 * Each thread has its own assertion handler instance.<br />
 * </p>
 * <p>The macros work together with the assertion handler object to
 * produce meaningful exception messages containing the name of the
 * source file, the position within that file, and the name of the
 * ObjC method or C function in which the assertion failed.
 * </p>
 * The assertion macros are:
 * NSAssert(), NSCAssert(),
 * NSAssert1(), NSCAssert1(),
 * NSAssert2(), NSCAssert2(),
 * NSAssert3(), NSCAssert3(),
 * NSAssert4(), NSCAssert4(),
 * NSAssert5(), NSCAssert5(),
 * NSParameterAssert(), NSCParameterAssert()
 */
@implementation NSAssertionHandler

/* Key for thread dictionary. */
static NSString *dict_key = @"_NSAssertionHandler";

/**
 * Returns the assertion handler object for the current thread.<br />
 * If none exists, creates one and returns it.
 */
+ (NSAssertionHandler*) currentHandler
{
  NSMutableDictionary	*dict;
  NSAssertionHandler	*handler;

  dict = GSCurrentThreadDictionary();
  handler = [dict objectForKey: dict_key];
  if (handler == nil)
    {
      handler = [[NSAssertionHandler alloc] init];
      [dict setObject: handler forKey: dict_key];
      RELEASE(handler);
    }
  return handler;
}

/**
 * Handles an assertion failure by using NSLogv() to print an error
 * message built from the supplied arguments, and then raising an
 * NSInternalInconsistencyException
 */
- (void) handleFailureInFunction: (NSString*)functionName 
			    file: (NSString*)fileName 
		      lineNumber: (int)line 
		     description: (NSString*)format,...
{
  id		message;
  va_list	ap;

  va_start(ap, format);
  message =
    [NSString
      stringWithFormat: @"%@:%d  Assertion failed in %@.  %@",
      fileName, line, functionName, format];
  NSLogv(message, ap);

  [NSException raise: NSInternalInconsistencyException
	      format: message arguments: ap];
  va_end(ap);
  /* NOT REACHED */
}

/**
 * Handles an assertion failure by using NSLogv() to print an error
 * message built from the supplied arguments, and then raising an
 * NSInternalInconsistencyException
 */
- (void) handleFailureInMethod: (SEL) aSelector
                        object: object
                          file: (NSString *) fileName
                    lineNumber: (int) line
                   description: (NSString *) format,...
{
  id		message;
  va_list	ap;

  va_start(ap, format);
  message =
    [NSString
      stringWithFormat: @"%@:%d  Assertion failed in %@(%@), method %@.  %@",
      fileName, line, NSStringFromClass([object class]), 
      [object isInstance] ? @"instance" : @"class",
      NSStringFromSelector(aSelector), format];
  NSLogv(message, ap);

  [NSException raise: NSInternalInconsistencyException 
	      format: message arguments: ap];
  va_end(ap);
  /* NOT REACHED */
}

@end
