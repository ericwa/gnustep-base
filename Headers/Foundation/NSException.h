/** Interface for NSException for GNUStep
   Copyright (C) 1995, 1996 Free Software Foundation, Inc.

   Written by:  Adam Fedor <fedor@boulder.colorado.edu>
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
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.

    <title>NSException and NSAssertionHandler class reference</title>

    AutogsdocSource: NSAssertionHandler.m
    AutogsdocSource: NSException.m

   */ 

#ifndef __NSException_h_GNUSTEP_BASE_INCLUDE
#define __NSException_h_GNUSTEP_BASE_INCLUDE

#include <Foundation/NSString.h>
#include <setjmp.h>
#include <stdarg.h>

@class NSDictionary;

@interface NSException : NSObject <NSCoding, NSCopying>
{    
  NSString *_e_name;
  NSString *_e_reason;
  NSDictionary *_e_info;
}

+ (NSException*) exceptionWithName: (NSString*)name
			    reason: (NSString*)reason
			  userInfo: (NSDictionary*)userInfo;
+ (void) raise: (NSString*)name
	format: (NSString*)format,...;
+ (void) raise: (NSString*)name
	format: (NSString*)format
     arguments: (va_list)argList;

- (id) initWithName: (NSString*)name 
	     reason: (NSString*)reason 
	   userInfo: (NSDictionary*)userInfo;
- (void) raise;

// Querying Exceptions
- (NSString*) name;
- (NSString*) reason;
- (NSDictionary*) userInfo;

@end

/* Common exceptions */
GS_EXPORT NSString* const NSGenericException;
GS_EXPORT NSString* const NSInternalInconsistencyException;
GS_EXPORT NSString* const NSInvalidArgumentException;
GS_EXPORT NSString* const NSMallocException;
GS_EXPORT NSString* const NSRangeException;
GS_EXPORT NSString* const NSCharacterConversionException;
#ifndef	STRICT_OPENSTEP
GS_EXPORT NSString* const NSParseErrorException;
#endif

/* Exception handler definitions */

/**
 * The actual structure for an NSHandler.  You shouldn't need to worry about it.
 */
typedef struct _NSHandler 
{
    jmp_buf jumpState;			/* place to longjmp to */
    struct _NSHandler *next;		/* ptr to next handler */
    NSException *exception;
} NSHandler;

/**
 *  This is the type of the exception handler called when an exception is
 *  generated and not caught by the programmer.  See
 *  NSGetUncaughtExceptionHandler(), NSSetUncaughtExceptionHandler().
 */
typedef void NSUncaughtExceptionHandler(NSException *exception);

/**
 *  Variable used to hold the current uncaught exception handler.  Use the
 *  function NSSetUncaughtExceptionHandler() to set.
 */
GS_EXPORT NSUncaughtExceptionHandler *_NSUncaughtExceptionHandler;

/**
 *  Returns the exception handler called when an exception is generated and
 *  not caught by the programmer (by enclosing in <code>NS_DURING</code> and
 *  <code>NS_HANDLER</code>...<code>NS_ENDHANDLER</code>).  The default prints
 *  an error message and exits the program.  You can change this behavior by
 *  calling NSSetUncaughtExceptionHandler().
 */
#define NSGetUncaughtExceptionHandler() _NSUncaughtExceptionHandler

/**
 *  Sets the exception handler called when an exception is generated and
 *  not caught by the programmer (by enclosing in <code>NS_DURING</code> and
 *  <code>NS_HANDLER</code>...<code>NS_ENDHANDLER</code>).  The default prints
 *  an error message and exits the program.  proc should take a single argument
 *  of type <code>NSException *</code>.
 */
#define NSSetUncaughtExceptionHandler(proc) \
			(_NSUncaughtExceptionHandler = (proc))

/* NS_DURING, NS_HANDLER and NS_ENDHANDLER are always used like: 

	NS_DURING
	    some code which might raise an error
	NS_HANDLER
	    code that will be jumped to if an error occurs
	NS_ENDHANDLER

   If any error is raised within the first block of code, the second block
   of code will be jumped to.  Typically, this code will clean up any
   resources allocated in the routine, possibly case on the error code
   and perform special processing, and default to RERAISE the error to
   the next handler.  Within the scope of the handler, a local variable
   called exception holds information about the exception raised.

   It is illegal to exit the first block of code by any other means than
   NS_VALRETURN, NS_VOIDRETURN, or just falling out the bottom.
 */

/** Private support routine.  Do not call directly. */
GS_EXPORT void _NSAddHandler( NSHandler *handler );
/** Private support routine.  Do not call directly. */
GS_EXPORT void _NSRemoveHandler( NSHandler *handler );

#define NS_DURING { NSHandler NSLocalHandler;			\
		    _NSAddHandler(&NSLocalHandler);		\
		    if( !setjmp(NSLocalHandler.jumpState) ) {

#define NS_HANDLER _NSRemoveHandler(&NSLocalHandler); } else { \
		    NSException *localException;               \
		    localException = NSLocalHandler.exception; \
		    {

#define NS_ENDHANDLER }}}

#define NS_VALRETURN(val)  do { typeof(val) temp = (val);	\
			_NSRemoveHandler(&NSLocalHandler);	\
			return(temp); } while (0)

#define NS_VALUERETURN(object, id) do { id temp = object;	\
			_NSRemoveHandler(&NSLocalHandler);	\
			return(temp); } while (0) 

#define NS_VOIDRETURN	do { _NSRemoveHandler(&NSLocalHandler);	\
			return; } while (0)

/* ------------------------------------------------------------------------ */
/*   Assertion Handling */
/* ------------------------------------------------------------------------ */

@interface NSAssertionHandler : NSObject

+ (NSAssertionHandler*) currentHandler;

- (void) handleFailureInFunction: (NSString*)functionName 
			    file: (NSString*)fileName 
		      lineNumber: (int)line 
		     description: (NSString*)format,...;

- (void) handleFailureInMethod: (SEL)aSelector 
			object: object 
			  file: (NSString*)fileName 
		    lineNumber: (int)line 
		   description: (NSString*)format,...;

@end

#ifdef	NS_BLOCK_ASSERTIONS
#define _NSAssertArgs(condition, desc, args...)		
#define _NSCAssertArgs(condition, desc, args...)	
#else
#define _NSAssertArgs(condition, desc, args...)			\
    do {							\
	if (!(condition)) {					\
	    [[NSAssertionHandler currentHandler] 		\
	    	handleFailureInMethod: _cmd 			\
		object: self 					\
		file: [NSString stringWithCString: __FILE__] 	\
		lineNumber: __LINE__ 				\
		description: (desc) , ## args]; 			\
	}							\
    } while(0)

#define _NSCAssertArgs(condition, desc, args...)		\
    do {							\
	if (!(condition)) {					\
	    [[NSAssertionHandler currentHandler] 		\
	    handleFailureInFunction: [NSString stringWithCString: __PRETTY_FUNCTION__] 				\
	    file: [NSString stringWithCString: __FILE__] 		\
	    lineNumber: __LINE__ 				\
	    description: (desc) , ## args]; 			\
	}							\
    } while(0)
#endif

/** Used in an ObjC method body.<br />
 * See [NSAssertionHandler] for details.<br />
 * When condition is false, raise an exception using desc and arg1, arg2,
 * arg3, arg4, arg5 */
#define NSAssert5(condition, desc, arg1, arg2, arg3, arg4, arg5)	\
    _NSAssertArgs((condition), (desc), (arg1), (arg2), (arg3), (arg4), (arg5))

/** Used in an ObjC method body.<br />
 * See [NSAssertionHandler] for details.<br />
 * When condition is false, raise an exception using desc and arg1, arg2,
 * arg3, arg4 */
#define NSAssert4(condition, desc, arg1, arg2, arg3, arg4)	\
    _NSAssertArgs((condition), (desc), (arg1), (arg2), (arg3), (arg4))

/** Used in an ObjC method body.<br />
 * See [NSAssertionHandler] for details.<br />
 * When condition is false, raise an exception using desc and arg1, arg2,
 * arg3 */
#define NSAssert3(condition, desc, arg1, arg2, arg3)	\
    _NSAssertArgs((condition), (desc), (arg1), (arg2), (arg3))

/** Used in an ObjC method body.<br />
 * See [NSAssertionHandler] for details.<br />
 * When condition is false, raise an exception using desc and arg1, arg2 */
#define NSAssert2(condition, desc, arg1, arg2)		\
    _NSAssertArgs((condition), (desc), (arg1), (arg2))

/** Used in an ObjC method body.<br />
 * See [NSAssertionHandler] for details.<br />
 * When condition is false, raise an exception using desc  and arg1 */
#define NSAssert1(condition, desc, arg1)		\
    _NSAssertArgs((condition), (desc), (arg1))

/** Used in an ObjC method body.<br />
 * See [NSAssertionHandler] for details.<br />
 * When condition is false, raise an exception using desc */
#define NSAssert(condition, desc)			\
    _NSAssertArgs((condition), (desc))

/** Used in an ObjC method body.<br />
 * See [NSAssertionHandler] for details.<br />
 * When condition is false, raise an exception saying that an invalid
 * parameter was supplied to the method. */
#define NSParameterAssert(condition)			\
    _NSAssertArgs((condition), @"Invalid parameter not satisfying: %s", #condition)

/** Used in plain C code (not in an ObjC method body).<br />
 * See [NSAssertionHandler] for details.<br />
 * When condition is false, raise an exception using desc and arg1, arg2,
 * arg3, arg4, arg5 */
#define NSCAssert5(condition, desc, arg1, arg2, arg3, arg4, arg5)	\
    _NSCAssertArgs((condition), (desc), (arg1), (arg2), (arg3), (arg4), (arg5))

/** Used in plain C code (not in an ObjC method body).<br />
 * See [NSAssertionHandler] for details.<br />
 * When condition is false, raise an exception using desc and arg1, arg2,
 * arg3, arg4 */
#define NSCAssert4(condition, desc, arg1, arg2, arg3, arg4)	\
    _NSCAssertArgs((condition), (desc), (arg1), (arg2), (arg3), (arg4))

/** Used in plain C code (not in an ObjC method body).<br />
 * See [NSAssertionHandler] for details.<br />
 * When condition is false, raise an exception using desc and arg1, arg2,
 * arg3 */
#define NSCAssert3(condition, desc, arg1, arg2, arg3)	\
    _NSCAssertArgs((condition), (desc), (arg1), (arg2), (arg3))

/** Used in plain C code (not in an ObjC method body).<br />
 * See [NSAssertionHandler] for details.<br />
 * When condition is false, raise an exception using desc and arg1, arg2
 */
#define NSCAssert2(condition, desc, arg1, arg2)		\
    _NSCAssertArgs((condition), (desc), (arg1), (arg2))

/** Used in plain C code (not in an ObjC method body).<br />
 * See [NSAssertionHandler] for details.<br />
 * When condition is false, raise an exception using desc and arg1
 */
#define NSCAssert1(condition, desc, arg1)		\
    _NSCAssertArgs((condition), (desc), (arg1))

/** Used in plain C code (not in an ObjC method body).<br />
 * See [NSAssertionHandler] for details.<br />
 * When condition is false, raise an exception using desc
 */
#define NSCAssert(condition, desc)			\
    _NSCAssertArgs((condition), (desc))

/** Used in plain C code (not in an ObjC method body).<br />
 * See [NSAssertionHandler] for details.<br />
 * When condition is false, raise an exception saying that an invalid
 * parameter was supplied to the method. */
#define NSCParameterAssert(condition)			\
    _NSCAssertArgs((condition), @"Invalid parameter not satisfying: %s", #condition)

#endif /* __NSException_h_GNUSTEP_BASE_INCLUDE */
