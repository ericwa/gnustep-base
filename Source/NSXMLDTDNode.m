/* Implementation for NSXMLDTDNode for GNUStep
   Copyright (C) 2008 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Created: September 2008

   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 3 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.
*/

#import "common.h"

#import	"NSXMLPrivate.h"

#define GSInternal              NSXMLDTDNodeInternal
#include        "GSInternal.h"
GS_PRIVATE_INTERNAL(NSXMLDTDNode)

@implementation NSXMLDTDNode

- (void) dealloc
{
  if (GS_EXISTS_INTERNAL)
    {
      [internal->notationName release];
      [internal->publicID release];
      [internal->systemID release];
    }
  [super dealloc];
}

- (NSXMLDTDNodeKind) DTDKind
{
  return internal->DTDKind;
}

- (id) initWithKind: (NSXMLNodeKind)kind options: (NSUInteger)theOptions
{
  if (NSXMLEntityDeclarationKind == kind
    || NSXMLElementDeclarationKind
    || NSXMLNotationDeclarationKind)
    {
      /* Create holder for internal instance variables so that we'll have
       * all our ivars available rather than just those of the superclass.
       */
      GS_CREATE_INTERNAL(NSXMLDTDNode)
    }
  return [super initWithKind: kind options: theOptions];
}

- (id) initWithXMLString: (NSString*)string
{
  [self notImplemented: _cmd];
  return nil;
}

- (BOOL) isExternal
{
  if (internal->systemID != nil)
    {
// FIXME ... libxml integration?
      return YES;
    }
  return NO;
}

- (NSString*) notationName
{
  if (internal->notationName == nil)
    {
      [self notImplemented: _cmd];
    }
  return internal->notationName;
}

- (NSString*) publicID
{
  if (internal->publicID == nil)
    {
      [self notImplemented: _cmd];
    }
  return internal->publicID;
}

- (void) setDTDKind: (NSXMLDTDNodeKind)kind
{
  internal->DTDKind = kind;
  // FIXME ... libxml integration?
}

- (void) setNotationName: (NSString*)notationName
{
  ASSIGNCOPY(internal->notationName, notationName);
  // FIXME ... libxml integration?
}

- (void) setPublicID: (NSString*)publicID
{
  ASSIGNCOPY(internal->publicID, publicID);
  // FIXME ... libxml integration?
}

- (void) setSystemID: (NSString*)systemID
{
  ASSIGNCOPY(internal->systemID, systemID);
  // FIXME ... libxml integration?
}

- (NSString*) systemID
{
  if (internal->systemID == nil)
    {
      [self notImplemented: _cmd];
    }
  return internal->systemID;
}

@end

