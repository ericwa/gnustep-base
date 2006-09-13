/* Interface to debugging utilities for GNUStep and OpenStep
   Copyright (C) 1997,1999 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Date: August 1997
   Extended by: Nicola Pero <n.pero@mi.flashnet.it>
   Date: December 2000, April 2001

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
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
   MA 02111 USA.
   */

#ifndef __NSDebug_h_GNUSTEP_BASE_INCLUDE
#define __NSDebug_h_GNUSTEP_BASE_INCLUDE

#include <errno.h>
#include <Foundation/NSObject.h>


#if	defined(__cplusplus)
extern "C" {
#endif

/*
 *	Functions for debugging object allocation/deallocation
 *
 *	Internal functions:
 *	GSDebugAllocationAdd()		is used by NSAllocateObject()
 *	GSDebugAllocationRemove()	is used by NSDeallocateObject()
 *
 *	Public functions:
 *	GSDebugAllocationActive()	
 *	GSDebugAllocationCount()	
 *      GSDebugAllocationTotal()
 *      GSDebugAllocationPeak()
 *      GSDebugAllocationClassList()
 *	GSDebugAllocationList()
 *	GSDebugAllocationListAll()
 * GSSetDebugAllocationFunctions()
 *
 * When the previous functions have allowed you to find a memory leak,
 * and you know that you are leaking objects of class XXX, but you are
 * hopeless about actually finding out where the leak is, the
 * following functions could come handy as they allow you to find
 * exactly *what* objects you are leaking (warning! these functions
 * could slow down your system appreciably - use them only temporarily
 * and only in debugging systems):
 *
 *  GSDebugAllocationActiveRecordingObjects()
 *  GSDebugAllocationListRecordedObjects() 
 */
#ifndef	NDEBUG

/**
 * Used internally by NSAllocateObject() ... you probably don't need this.
 */
GS_EXPORT void		GSDebugAllocationAdd(Class c, id o);

/**
 * Used internally by NSDeallocateObject() ... you probably don't need this.
 */
GS_EXPORT void		GSDebugAllocationRemove(Class c, id o);

/**
 * Activates or deactivates object allocation debugging.
 * Returns previous state.
 */
GS_EXPORT BOOL		GSDebugAllocationActive(BOOL active);

/**
 * Returns the number of instances of the specified class
 * which are currently allocated.
 */
GS_EXPORT int		GSDebugAllocationCount(Class c);

/**
 * Returns the peak number of instances of the specified class
 * which have been concurrently allocated.
 */
GS_EXPORT int		GSDebugAllocationPeak(Class c);

/**
 * Returns the total number of instances of the specified class
 * which have been allocated.
 */
GS_EXPORT int		GSDebugAllocationTotal(Class c);

/**
 * Returns a NULL terminated array listing all the classes 
 * for which statistical information has been collected.
 */
GS_EXPORT Class*        GSDebugAllocationClassList(void);

/**
 * Returns a newline separated list of the classes which
 * have instances allocated, and the instance counts.
 * If 'changeFlag' is YES then the list gives the number
 * of instances allocated/deallocated since the function
 * was last called.
 */
GS_EXPORT const char*	GSDebugAllocationList(BOOL changeFlag);

/**
 * Returns a newline separated list of the classes which
 * have had instances allocated at any point, and the total
 * count of the number of instances allocated for each class.
 */
GS_EXPORT const char*	GSDebugAllocationListAll(void);

/**
 * Starts recording all allocated objects of a certain class.<br />
 * Use with extreme care ... this could slow down your application
 * enormously.
 */
GS_EXPORT void     GSDebugAllocationActiveRecordingObjects(Class c);

/**
 * Returns an array containing all the allocated objects
 * of a certain class which have been recorded.
 * Presumably, you will immediately call [NSObject-description] on
 * them to find out the objects you are leaking.
 * Warning - the objects are put in an array, so until
 * the array is autoreleased, the objects are not released.
 */
GS_EXPORT NSArray *GSDebugAllocationListRecordedObjects(Class c);

/**
 * This function associates the supplied tag with a recorded
 * object and returns the tag which was previously associated
 * with it (if any).<br />
 * If the object was not recorded, the method returns nil<br />
 * The tag is retained while it is associated with the object.<br />
 * See also the NSDebugFRLog() and NSDebugMRLog() macros.
 */
GS_EXPORT id GSDebugAllocationTagRecordedObject(id object, id tag);

/**
 * Used to produce a format string for logging a message with function
 * location details.
 */
GS_EXPORT NSString*	GSDebugFunctionMsg(const char *func, const char *file,
				int line, NSString *fmt);
/**
 * Used to produce a format string for logging a message with method
 * location details.
 */
GS_EXPORT NSString*	GSDebugMethodMsg(id obj, SEL sel, const char *file,
				int line, NSString *fmt);

/**
 * This functions allows to set own function callbacks for debugging allocation
 * of objects. Useful if you intend to write your own object allocation code.
 */
GS_EXPORT void  GSSetDebugAllocationFunctions(
  void (*newAddObjectFunc)(Class c, id o),
  void (*newRemoveObjectFunc)(Class c, id o));

#endif

/**
 * Enable/disable zombies.
 * <p>When an object is deallocated, its isa pointer is normally modified
 * to the hexadecimal value 0xdeadface, so that any attempt to send a
 * message to the deallocated object will cause a crash, and examination
 * of the object within the debugger will show the 0xdeadface value ...
 * making it obvious why the program crashed.
 * </p>
 * <p>Turning on zombies changes this behavior so that the isa pointer
 * is modified to be that of the NSZombie class.  When messages are
 * sent to the object, instead of crashing, NSZombie will use NSLog() to
 * produce an error message.  By default the memory used by the object
 * will not really be freed, so error messages will continue to
 * be generated whenever a message is sent to the object, and the object
 * instance variables will remain available for examination by the debugger.
 * </p>
 * The default value of this boolean is NO, but this can be controlled
 * by the NSZombieEnabled environment variable.
 */
GS_EXPORT BOOL NSZombieEnabled;

/**
 * Enable/disable object deallocation.
 * <p>If zombies are enabled, objects are by default <em>not</em>
 * deallocated, and memory leaks.  The NSDeallocateZombies variable
 * lets you say that the the memory used by zombies should be freed.
 * </p>
 * <p>Doing this makes the behavior of zombies similar to that when zombies
 * are not enabled ... the memory occupied by the zombie may be re-used for
 * other purposes, at which time the isa pointer may be overwritten and the
 * zombie behavior will cease.
 * </p>
 * The default value of this boolean is NO, but this can be controlled
 * by the NSDeallocateZombies environment variable.
 */
GS_EXPORT BOOL NSDeallocateZombies;



#ifdef GSDIAGNOSE
#include	<Foundation/NSObjCRuntime.h>
#include	<Foundation/NSProcessInfo.h>

/**
   <p>NSDebugLLog() is the basic debug logging macro used to display
   log messages using NSLog(), if debug logging was enabled at compile
   time and the appropriate logging level was set at runtime.
   </p>
   <p>Debug logging which can be enabled/disabled by defining GSDIAGNOSE
   when compiling and also setting values in the mutable set which
   is set up by NSProcessInfo. GSDIAGNOSE is defined automatically
   unless diagnose=no is specified in the make arguments.
   </p>
   <p>NSProcess initialises a set of strings that are the names of active
   debug levels using the '--GNU-Debug=...' command line argument.
   Each command-line argument of that form is removed from
   <code>NSProcessInfo</code>'s list of arguments and the variable part
   (...) is added to the set.
   This means that as far as the program proper is concerned, it is
   running with the same arguments as if debugging had not been enabled.
   </p>
   <p>For instance, to debug the NSBundle class, run your program with 
    '--GNU-Debug=NSBundle'
   You can of course supply multiple '--GNU-Debug=...' arguments to
   output debug information on more than one thing.
   </p>
   <p>NSUserDefaults also adds debug levels from the array given by the
   GNU-Debug key ... but these values will not take effect until the
   +standardUserDefaults method is called ... so they are useless for
   debugging NSUserDefaults itself or for debugging any code executed
   before the defaults system is used.
   </p>
   <p>To embed debug logging in your code you use the NSDebugLLog() or
   NSDebugLog() macro.  NSDebugLog() is just NSDebugLLog() with the debug
   level set to 'dflt'.  So, to activate debug statements that use
   NSDebugLog(), you supply the '--GNU-Debug=dflt' argument to your program.
   </p>
   <p>You can also change the active debug levels under your programs control -
   NSProcessInfo has a [-debugSet] method that returns the mutable set that
   contains the active debug levels - your program can modify this set.
   </p>
   <p>Two debug levels have a special effect - 'dflt' is the level used for
   debug logs statements where no debug level is specified, and 'NoWarn'
   is used to *disable* warning messages.
   </p>
   <p>As a convenience, there are four more logging macros you can use -
   NSDebugFLog(), NSDebugFLLog(), NSDebugMLog() and NSDebugMLLog().
   These are the same as the other macros, but are specifically for use in
   either functions or methods and prepend information about the file, line
   and either function or class/method in which the message was generated.
   </p>
 */
#define NSDebugLLog(level, format, args...) \
  do { if (GSDebugSet(level) == YES) \
    NSLog(format , ## args); } while (0)

/**
 * This macro is a shorthand for NSDebugLLog() using then default debug
 * level ... 'dflt'
 */
#define NSDebugLog(format, args...) \
  do { if (GSDebugSet(@"dflt") == YES) \
    NSLog(format , ## args); } while (0)

/**
 * This macro is like NSDebugLLog() but includes the name and location
 * of the function in which the macro is used as part of the log output.
 */
#define NSDebugFLLog(level, format, args...) \
  do { if (GSDebugSet(level) == YES) { \
    NSString *fmt = GSDebugFunctionMsg( \
	__PRETTY_FUNCTION__, __FILE__, __LINE__, format); \
    NSLog(fmt , ## args); }} while (0)

/**
 * This macro is a shorthand for NSDebugFLLog() using then default debug
 * level ... 'dflt'
 */
#define NSDebugFLog(format, args...) \
  do { if (GSDebugSet(@"dflt") == YES) { \
    NSString *fmt = GSDebugFunctionMsg( \
	__PRETTY_FUNCTION__, __FILE__, __LINE__, format); \
    NSLog(fmt , ## args); }} while (0)

/**
 * This macro is like NSDebugLLog() but includes the name and location
 * of the <em>method</em> in which the macro is used as part of the log output.
 */
#define NSDebugMLLog(level, format, args...) \
  do { if (GSDebugSet(level) == YES) { \
    NSString *fmt = GSDebugMethodMsg( \
	self, _cmd, __FILE__, __LINE__, format); \
    NSLog(fmt , ## args); }} while (0)

/**
 * This macro is a shorthand for NSDebugMLLog() using then default debug
 * level ... 'dflt'
 */
#define NSDebugMLog(format, args...) \
  do { if (GSDebugSet(@"dflt") == YES) { \
    NSString *fmt = GSDebugMethodMsg( \
	self, _cmd, __FILE__, __LINE__, format); \
    NSLog(fmt , ## args); }} while (0)

/**
 * This macro saves the name and location of the function in
 * which the macro is used, along with a short string msg as
 * the tag associated with a recorded object.
 */
#define NSDebugFRLog(object, msg) \
  do { \
    NSString *tag = GSDebugFunctionMsg( \
	__PRETTY_FUNCTION__, __FILE__, __LINE__, msg); \
    GSDebugAllocationTagRecordedObject(object, tag); } while (0)

/**
 * This macro saves the name and location of the method in
 * which the macro is used, along with a short string msg as
 * the tag associated with a recorded object.
 */
#define NSDebugMRLog(object, msg) \
  do { \
    NSString *tag = GSDebugMethodMsg( \
	self, _cmd, __FILE__, __LINE__, msg); \
    GSDebugAllocationTagRecordedObject(object, tag); } while (0)

#else
#define NSDebugLLog(level, format, args...)
#define NSDebugLog(format, args...)
#define NSDebugFLLog(level, format, args...)
#define NSDebugFLog(format, args...)
#define NSDebugMLLog(level, format, args...)
#define NSDebugMLog(format, args...)
#define NSDebugFRLog(object, msg)
#define NSDebugMRLog(object, msg)
#endif

/**
 * Macro to log a message only the first time it is encountered.<br />
 * Not entirely thread safe ... but that's not really important,
 * it just means that it's possible for the message to be logged
 * more than once if two threads call it simultaneously when it
 * has not already been called.<br />
 * Use this from inside a function.  Pass an NSString as a format,
 * followed by zero or more arguments for the format string.
 * Example: GSOnceMLog(@"This function is deprecated, use another");
 */
#define GSOnceFLog(format, args...) \
  do { static BOOL beenHere = NO; if (beenHere == NO) {\
    NSString *fmt = GSDebugFunctionMsg( \
	__PRETTY_FUNCTION__, __FILE__, __LINE__, format); \
    beenHere = YES; \
    NSLog(fmt , ## args); }} while (0)
/**
 * Macro to log a message only the first time it is encountered.<br />
 * Not entirely thread safe ... but that's not really important,
 * it just means that it's possible for the message to be logged
 * more than once if two threads call it simultaneously when it
 * has not already been called.<br />
 * Use this from inside a method. Pass an NSString as a format
 * followed by zero or more arguments for the format string.<br />
 * Example: GSOnceMLog(@"This method is deprecated, use another");
 */
#define GSOnceMLog(format, args...) \
  do { static BOOL beenHere = NO; if (beenHere == NO) {\
    NSString *fmt = GSDebugMethodMsg( \
	self, _cmd, __FILE__, __LINE__, format); \
    beenHere = YES; \
    NSLog(fmt , ## args); }} while (0)



#ifdef GSWARN
#include	<Foundation/NSObjCRuntime.h>

/**
   <p>NSWarnLog() is the basic debug logging macro used to display
   warning messages using NSLog(), if warn logging was not disabled at compile
   time and the disabling logging level was not set at runtime.
   </p>
   <p>Warning messages which can be enabled/disabled by defining GSWARN
   when compiling.
   </p>
   <p>You can also disable these messages at runtime by supplying a
   '--GNU-Debug=NoWarn' argument to the program, or by adding 'NoWarn'
   to the user default array named 'GNU-Debug'.
   </p>
   <p>These logging macros are intended to be used when the software detects
   something that it not necessarily fatal or illegal, but looks like it
   might be a programming error.  eg. attempting to remove 'nil' from an
   NSArray, which the Spec/documentation does not prohibit, but which a
   well written program should not be attempting (since an NSArray object
   cannot contain a 'nil').
   </p>
   <p>NB. The 'warn=yes' option is understood by the GNUstep make package
   to mean that GSWARN should be defined, and the 'warn=no' means that
   GSWARN should be undefined.  Default is to define it.
   </p>
   <p>To embed debug logging in your code you use the NSWarnLog() macro.
   </p>
   <p>As a convenience, there are two more logging macros you can use -
   NSWarnFLog(), and NSWarnMLog().
   These are specifically for use in either functions or methods and
   prepend information about the file, line and either function or
   class/method in which the message was generated.
   </p>
 */

#define NSWarnLog(format, args...) \
  do { if (GSDebugSet(@"NoWarn") == NO) { \
    NSLog(format , ## args); }} while (0)

/**
 * This macro is like NSWarnLog() but includes the name and location of the
 * <em>function</em> in which the macro is used as part of the log output.
 */
#define NSWarnFLog(format, args...) \
  do { if (GSDebugSet(@"NoWarn") == NO) { \
    NSString *fmt = GSDebugFunctionMsg( \
	__PRETTY_FUNCTION__, __FILE__, __LINE__, format); \
    NSLog(fmt , ## args); }} while (0)

/**
 * This macro is like NSWarnLog() but includes the name and location of the
 * <em>method</em> in which the macro is used as part of the log output.
 */
#define NSWarnMLog(format, args...) \
  do { if (GSDebugSet(@"NoWarn") == NO) { \
    NSString *fmt = GSDebugMethodMsg( \
	self, _cmd, __FILE__, __LINE__, format); \
    NSLog(fmt , ## args); }} while (0)
#else
#define NSWarnLog(format, args...)
#define NSWarnFLog(format, args...)
#define NSWarnMLog(format, args...)
#endif

/**
 *  Retrieve stack information.  Use caution: uses built-in gcc functions
 *  and currently only works up to 100 frames.
 */
GS_EXPORT void *NSFrameAddress(int offset);

/**
 *  Retrieve stack information.  Use caution: uses built-in gcc functions
 *  and currently only works up to 100 frames.
 */
GS_EXPORT void *NSReturnAddress(int offset);

/**
 *  Retrieve stack information.  Use caution: uses built-in gcc functions
 *  and currently only works up to 100 frames.
 */
GS_EXPORT unsigned NSCountFrames(void);

#if	defined(__cplusplus)
}
#endif

#endif
