/** This tool converts a serialised property list to a text representation.
   Copyright (C) 1999 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Created: may 1999

   This file is part of the GNUstep Project

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; either version 2
   of the License, or (at your option) any later version.
    
   You should have received a copy of the GNU General Public  
   License along with this library; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

   */

#include "config.h"
#include	<Foundation/Foundation.h>
#include	<Foundation/NSArray.h>
#include	<Foundation/NSData.h>
#include	<Foundation/NSException.h>
#include	<Foundation/NSString.h>
#include	<Foundation/NSProcessInfo.h>
#include	<Foundation/NSUserDefaults.h>
#include	<Foundation/NSDebug.h>
#include	<Foundation/NSFileHandle.h>
#include	<Foundation/NSAutoreleasePool.h>


/** <p>This tool converts a binary serialised property list to a text
    representation.
</p> */
int
main(int argc, char** argv, char **env)
{
  NSAutoreleasePool	*pool;
  NSProcessInfo		*proc;
  NSArray		*args;
  unsigned		i;

#ifdef GS_PASS_ARGUMENTS
  [NSProcessInfo initializeWithArguments:argv count:argc environment:env];
#endif
  pool = [NSAutoreleasePool new];
  proc = [NSProcessInfo processInfo];
  if (proc == nil)
    {
      NSLog(@"pldes: unable to get process information!\n");
      [pool release];
      exit(EXIT_SUCCESS);
    }

  args = [proc arguments];

  if ([args count] <= 1)
    {
      GSPrintf(stderr, @"No file names given to deserialize.\n");
    }
  else
    {
      NSUserDefaults	*defs = [NSUserDefaults standardUserDefaults];
      NSDictionary	*locale = [defs dictionaryRepresentation];

      for (i = 1; i < [args count]; i++)
	{
	  NSString	*file = [args objectAtIndex: i];

	  NS_DURING
	    {
	      NSData	*myData;
	      NSString	*myString;
	      id	result;

	      myData = [NSData dataWithContentsOfFile: file];
	      result = [NSDeserializer deserializePropertyListFromData: myData
						     mutableContainers: NO];
	      if (result == nil)
		GSPrintf(stderr, @"Loading '%@' - nil property list\n", file);
	      else
		{
		  NSFileHandle	*out;

		  myString = [result descriptionWithLocale: locale indent: 0];
		  out = [NSFileHandle fileHandleWithStandardOutput];
		  myData = [myString dataUsingEncoding: NSASCIIStringEncoding];
		  [out writeData: myData];
		  [out synchronizeFile];
		}
	    }
	  NS_HANDLER
	    {
	      GSPrintf(stderr, @"Loading '%@' - %@\n", file,
		[localException reason]);
	    }
	  NS_ENDHANDLER
	}
    }
  [pool release];
  return 0;
}
