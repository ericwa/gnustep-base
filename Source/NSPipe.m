/** Implementation for NSPipe for GNUStep
   Copyright (C) 1997 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Date: 1997

   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.

   $Date$ $Revision$
   */

#include "config.h"
#include "GNUstepBase/preface.h"
#include "Foundation/NSObject.h"
#include "Foundation/NSFileHandle.h"
#include "Foundation/NSDebug.h"
#include "GSPrivate.h"
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

/**
 * <p>The NSPipe provides an encapsulation of the UNIX concept of pipe.<br />
 * With NSPipe, it is possible to redirect the standard input or
 * standard output.
 * </p>
 * <p>The file handles created by NSPipe are automatically closed when they
 * are no longer in use (ie when the NSPipe instance is deallocated), so you
 * don't need to close them explicitly.
 * </p>
 */
@implementation NSPipe

/**
 * Returns a newly allocated and initialized NSPipe object that has been
 * sent an autorelease message.
 */
+ (id) pipe
{
  return AUTORELEASE([[self alloc] init]);
}

- (void) dealloc
{
  RELEASE(readHandle);
  RELEASE(writeHandle);
  [super dealloc];
}

- (id) init
{
  self = [super init];
  if (self != nil)
    {
#ifndef __MINGW32__
      int	p[2];

      if (pipe(p) == 0)
        {
          readHandle = [[NSFileHandle alloc] initWithFileDescriptor: p[0]
						     closeOnDealloc: YES];
          writeHandle = [[NSFileHandle alloc] initWithFileDescriptor: p[1]
						      closeOnDealloc: YES];
        }
      else
	{
	  NSLog(@"Failed to create pipe ... %@", [NSError _last]);
	  DESTROY(self);
	}
#else
      SECURITY_ATTRIBUTES saAttr;
      HANDLE readh, writeh;

      saAttr.nLength = sizeof(SECURITY_ATTRIBUTES);
      saAttr.bInheritHandle = TRUE;
      saAttr.lpSecurityDescriptor = NULL;

      if (CreatePipe(&readh, &writeh, &saAttr, 0) != 0)
        {
          readHandle = [[NSFileHandle alloc] initWithNativeHandle: readh
						   closeOnDealloc: YES];
          writeHandle = [[NSFileHandle alloc] initWithNativeHandle: writeh
						    closeOnDealloc: YES];
        }
      else
	{
	  NSLog(@"Failed to create pipe ... %@", [NSError _last]);
	  DESTROY(self);
	}
#endif
    }
  return self;
}

/**
 * Returns the file handle for reading from the pipe.
 */
- (NSFileHandle*) fileHandleForReading
{
  return readHandle;
}

/**
 * Returns the file handle for writing to the pipe.
 */
- (NSFileHandle*) fileHandleForWriting
{
  return writeHandle;
}

@end

