/* Implementation for NSProcessInfo for GNUStep
   Copyright (C) 1995 Free Software Foundation, Inc.

   Written by:  Georg Tuparev, EMBL & Academia Naturalis, 
                Heidelberg, Germany
                Tuparev@EMBL-Heidelberg.de
   
   This file is part of the GNU Objective C Class Library.

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

/*************************************************************************
 * File Name  : NSProcessInfo.m
 * Version    : 0.6 beta
 * Date       : 06-aug-1995
 *************************************************************************
 * Notes      : 
 * 1) The class functionality depends on the following UNIX functions and
 * global variables: gethostname(), getpid(), and environ. For all system
 * I had the opportunity to test them they are defined and have the same
 * behavior. The same is true for the meaning of argv[0] (process name).
 * 2) The global variable _gnu_sharedProcessInfoObject should NEVER be
 * deallocate during the process runtime. Therefore I implemented a 
 * concrete NSProcessInfo subclass (_NSConcreteProcessInfo) with the only
 * purpose to override the autorelease, retain, and release methods.
 * To Do      : 
 * 1) To test the class on more platforms;
 * 2) To change the format of the string renurned by globallyUniqueString;
 * Bugs       : Not known
 * Last update: 08-aug-1995
 * History    : 06-aug-1995    - Birth and the first beta version (v. 0.5);
 *              08-aug-1995    - V. 0.6 (tested on NS, SunOS, Solaris, OSF/1
 *              The use of the environ global var was changed to more 
 *              conventional env[] (main function) so now the class could be
 *              used on SunOS and Solaris. [GT]
 *************************************************************************
 * Acknowledgments:
 * - Adam Fedor, Andrew McCallum, and Paul Kunz for their help;
 * - To the NEXTSTEP/GNUStep community
 *************************************************************************/

#ifdef NeXT
#ifdef SCITOOLS
#import <basekit/LibobjectsMain.h>
#import <foundation/NSString.h>
#import <foundation/NSArray.h>
#import <foundation/NSDictionary.h>
#import <foundation/NSDate.h>
#import <foundation/NSException.h>
#import <basekit/NSProcessInfo.h>
#else   /* SCITOOLS */
#import <foundation/NSString.h>
#import <foundation/NSArray.h>
#import <foundation/NSDictionary.h>
#import <foundation/NSDate.h>
#import <foundation/NSException.h>
#import <foundation/NSProcessInfo.h>
#endif  /* SCITOOLS */
#else
#include <string.h>
#include <Foundation/NSString.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSDictionary.h>
#include <Foundation/NSDate.h>
#include <Foundation/NSException.h>
#include <Foundation/NSProcessInfo.h>
#endif  /* NeXT */



/* This is the longest max host name allowed for all different systems
 * I had a chance to read the man pages. 
 */
#define _GNU_MAX_HOST_NAMELEN    256

/* This error message should be called only if the private main function
 * was not executed successfully. This may heppen ONLY if onother library
 * or kit defines its own main function (as libobjects does).
 */
#define _GNU_MISSING_MAIN_FUNCTION_CALL @"libobjects internal error: \
the private libobjects main() function was not called. Please contact \
libobjects authors for furrther information"

/*************************************************************************
 *** _NSConcreteProcessInfo
 *************************************************************************/
@interface _NSConcreteProcessInfo:NSProcessInfo
- (id)autorelease;
- (void)release;
- (id)retain;
@end

@implementation _NSConcreteProcessInfo
- (id)autorelease
{
	return self;
}

- (void)release
{
	return;
}

- (id)retain
{
	return self;
}
@end

/*************************************************************************
 *** NSProcessInfo implementation
 *************************************************************************/
@implementation NSProcessInfo
/*************************************************************************
 *** Static global vars
 *************************************************************************/
// The shared NSProcessInfo instance
static NSProcessInfo* _gnu_sharedProcessInfoObject = nil;

// Host name of the CPU executing the process
static NSString* _gnu_hostName = nil;   

// Current process name
static NSString* _gnu_processName = nil;

// Array of NSStrings (argv[1] .. argv[argc-1])
static NSMutableArray* _gnu_arguments = nil;

// Dictionary of environment vars and their values
static NSMutableDictionary* _gnu_environment = nil;

/*************************************************************************
 *** Implementing the Libobjects main function
 *************************************************************************/
#undef main

int main(int argc, char *argv[], char *env[])
{
	int i;
	
	/* Getting the process name */
	_gnu_processName = [NSString stringWithCString:argv[0]];
	[_gnu_processName retain];
	
	/* Copy the argument list */
	_gnu_arguments = [[NSMutableArray arrayWithCapacity:0] retain];
	for (i = 1; i < argc; i++) {
		[_gnu_arguments addObject:[NSString stringWithCString:argv[i]]];
	}
	
	/* Copy the evironment list */
	_gnu_environment = [[NSMutableDictionary dictionaryWithCapacity:0] retain];
	i = 0;
	while (env[i]) {
		char* cp;
		cp = strchr(env[i],'=');
		/* Temporary set *cp to \000 ... for copying purpose */
		*cp = '\000';
		[_gnu_environment setObject:[NSString stringWithCString:(cp+1)]
			forKey:[NSString stringWithCString:env[i]]];
		/* Return the original value of environ[i] */
		*cp = '=';
		i++;
	}
	
	/* Call the user defined main function */
	return LibobjectsMain(argc,argv);
}

/*************************************************************************
 *** Getting an NSProcessInfo Object
 *************************************************************************/
+ (NSProcessInfo *)processInfo
{
	// Check if the main() function was successfully called
#ifdef NeXT
	NSAssert(_gnu_processName && _gnu_arguments _gnu_environment,
		_GNU_MISSING_MAIN_FUNCTION_CALL);
#endif /* NeXT */

	if (!_gnu_sharedProcessInfoObject)
		_gnu_sharedProcessInfoObject = [[_NSConcreteProcessInfo alloc] init];
		
	return _gnu_sharedProcessInfoObject;
}

/*************************************************************************
 *** Returning Process Information
 *************************************************************************/
- (NSArray *)arguments
{
	return [[_gnu_arguments copyWithZone:[self zone]] autorelease];
}

- (NSDictionary *)environment
{
	return [[_gnu_environment copyWithZone:[self zone]] autorelease];
}

- (NSString *)hostName
{
	if (!_gnu_hostName) {
		char *hn = NSZoneMalloc([self zone], _GNU_MAX_HOST_NAMELEN);
		
		gethostname(hn, _GNU_MAX_HOST_NAMELEN);
		_gnu_hostName = [NSString stringWithCString:hn];
		[_gnu_hostName retain];
		NSZoneFree([self zone], hn);
	}
	
	return [[_gnu_hostName copyWithZone:[self zone]] autorelease];
}

- (NSString *)processName
{
	return [[_gnu_processName copyWithZone:[self zone]] autorelease];
}

- (NSString *)globallyUniqueString
{
	// $$$ The format of the string is not specified by the OpenStep 
	// specification. It could be useful to change this format after
	// NeXTSTEP release 4.0 comes out.
	return [NSString stringWithFormat:@"%@:%d:[%@]",
		[self hostName],(int)getpid(),[[NSDate date] description]];
}

/*************************************************************************
 *** Specifying a Process Name
 *************************************************************************/
- (void)setProcessName:(NSString *)newName
{
	if (newName && [newName length]) {
		[_gnu_processName autorelease];
		_gnu_processName = [newName copyWithZone:[self zone]];
	}
	return;
}

@end
