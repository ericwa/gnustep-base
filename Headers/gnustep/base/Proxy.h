/* Interface for GNU Objective-C proxy for remote objects messaging
   Copyright (C) 1994, 1995, 1996 Free Software Foundation, Inc.
   
   Written by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Created: July 1994
   
   This file is part of the Gnustep Base Library.

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

#ifndef __Proxy_h_GNUSTEP_BASE_INCLUDE
#define __Proxy_h_GNUSTEP_BASE_INCLUDE

#include <gnustep/base/preface.h>
#include <gnustep/base/Connection.h>
#include <gnustep/base/Retaining.h>

@class ConnectedCoder;

@interface Proxy <Retaining>
{
@public
  struct objc_class *isa;
  unsigned _target;
  Connection *_connection;
  unsigned _retain_count;
#if NeXT_runtime
  coll_cache_ptr _method_types;
  Protocol *protocol;
#endif
}

/* xxx Change name to newForTarget:connection: */
+ newForRemoteTarget: (unsigned)target connection: (Connection*)c;

- self;
#if NeXT_runtime
+ class;
#else
+ (Class) class;
#endif

- (void) invalidateProxy;
- (BOOL) isProxy;
- (unsigned) targetForProxy;
- connectionForProxy;

- forward: (SEL)aSel :(arglist_t)frame;

- classForConnectedCoder: aRmc;
+ (void) encodeObject: anObject withConnectedCoder: aRmc;

+ newWithCoder: aCoder;
- (void) encodeWithCoder: aCoder;

/* Only needed with NeXT runtime. */
- (const char *) selectorTypeForProxy: (SEL)selector; 

@end

@interface Object (IsProxy)
- (BOOL) isProxy;
@end

@interface Protocol (RemoteSelfCoding)
- classForConnectedCoder: aRmc;
@end

#endif /* __Proxy_h_GNUSTEP_BASE_INCLUDE */
