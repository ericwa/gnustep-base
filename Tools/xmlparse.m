/** This tool parses and validates xml documents.

   <title>xmlparse ... a tool to parse xml documents</title>
   Copyright (C) 2003 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Created: May 2003

   This file is part of the GNUstep Project

   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; either version 2
   of the License, or (at your option) any later version.

   You should have received a copy of the GNU General Public
   License along with this program; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

   */

#include "config.h"
#include <stdio.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSAutoreleasePool.h>
#include <Foundation/NSObjCRuntime.h>
#include <Foundation/NSProcessInfo.h>
#include <gnustep/base/GSXML.h>

@interface GSXMLParser (Loader)
+ (NSString*) loadEntity: (NSString*)publicId
                      at: (NSString*)location;
@end
@implementation	GSXMLParser (Loader)
+ (NSString*) loadEntity: (NSString*)publicId
                      at: (NSString*)location
{
  char		buf[BUFSIZ];
  NSString	*str;
  int		len;

  GSPrintf(stdout, @"Enter filename to load entity '%@' at '%@': ",
    publicId, location);
  fgets(buf, sizeof(buf)-1, stdin);
  buf[sizeof(buf)-1] = '\0';
  len = strlen(buf);
  // Strip trailing space
  while (len > 0 && buf[len-1] <= ' ')
    {
      buf[--len] = '\0';
    }
  str = [NSString stringWithCString: buf];
  return str;
}
@end

int
main(int argc, char **argv, char **env)
{
  NSProcessInfo		*proc;
  NSArray		*files;
  unsigned int		count;
  unsigned int		i;
  CREATE_AUTORELEASE_POOL(pool);

#ifdef GS_PASS_ARGUMENTS
  [NSProcessInfo initializeWithArguments: argv count: argc environment: env];
#endif

#ifndef HAVE_LIBXML
  NSLog(@"ERROR: The GNUstep Base Library was built\n"
@"        without an available libxml library. xmlparse needs the libxml\n"
@"        library to function. Aborting");
  exit(EXIT_FAILURE);
#endif

  proc = [NSProcessInfo processInfo];
  if (proc == nil)
    {
      NSLog(@"unable to get process information!");
      exit(EXIT_FAILURE);
    }

  files = [proc arguments];
  count = [files count];
  for (i = 1; i < count; i++)
    {
      NSString		*file = [files objectAtIndex: i];
      GSXMLNode		*root;
      GSXMLParser	*parser;

      parser = [GSXMLParser parserWithContentsOfFile: file];
      [parser substituteEntities: NO];
      [parser doValidityChecking: YES];
      [parser keepBlanks: NO];
      [parser saveMessages: YES];
      if ([parser parse] == NO)
	{
	  NSLog(@"WARNING %@ is not a valid document", file);
	  NSLog(@"Errors: %@", [parser messages]);
	}
      root = [[parser document] root];
      NSLog(@"Document is %@", [root name]);
    }
  RELEASE(pool);
  return 0;
}
