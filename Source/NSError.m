/** Implementation for NSError for GNUStep
   Copyright (C) 2004 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Date: May 2004

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

#include	<Foundation/NSDictionary.h>
#include	<Foundation/NSString.h>
#include	<Foundation/NSError.h>
#include	<Foundation/NSCoder.h>

NSString* const NSLocalizedDescriptionKey = @"NSLocalizedDescriptionKey";
NSString* const NSUnderlyingErrorKey = @"NSUnderlyingErrorKey";
NSString* const NSMACHErrorDomain = @"NSMACHErrorDomain";
NSString* const NSOSStatusErrorDomain = @"NSOSStatusErrorDomain";
NSString* const NSPOSIXErrorDomain = @"NSPOSIXErrorDomain";

@implementation	NSError

+ (id) errorWithDomain: (NSString*)aDomain
		  code: (int)aCode
	      userInfo: (NSDictionary*)aDictionary
{
  NSError	*e = [self allocWithZone: NSDefaultMallocZone()];

  e = [e initWithDomain: aDomain code: aCode userInfo: aDictionary];
  return AUTORELEASE(e);
}

- (int) code
{
  return _code;
}

- (id) copyWithZone: (NSZone*)z
{
  NSError	*e = [[self class] allocWithZone: z];

  e = [e initWithDomain: _domain code: _code userInfo: _userInfo];
  return e;
}

- (void) dealloc
{
  DESTROY(_domain);
  DESTROY(_userInfo);
  [super dealloc];
}

- (NSString*) domain
{
  return _domain;
}

- (void) encodeWithCoder: (NSCoder*)aCoder
{
  if ([aCoder allowsKeyedCoding])
    {
      [aCoder encodeInt: _code forKey: @"NSCode"];
      [aCoder encodeObject: _domain forKey: @"NSDomain"];
      [aCoder encodeObject: _userInfo forKey: @"NSUserInfo"];
    }
  else
    {
      [aCoder encodeValueOfObjCType: @encode(int) at: &_code];
      [aCoder encodeValueOfObjCType: @encode(id) at: &_domain];
      [aCoder encodeValueOfObjCType: @encode(id) at: &_userInfo];
    }
}

- (id) init
{
  return [self initWithDomain: nil code: 0 userInfo: nil];
}

- (id) initWithCoder: (NSCoder*)aCoder
{
  if ([aCoder allowsKeyedCoding])
    {
      int	c;
      id	d;
      id	u;

      c = [aCoder decodeIntForKey: @"NSCode"];
      d = [aCoder decodeObjectForKey: @"NSDomain"];
      u = [aCoder decodeObjectForKey: @"NSUserInfo"];
      self = [self initWithDomain: d code: c userInfo: u];
    }
  else
    {
      [aCoder decodeValueOfObjCType: @encode(int) at: &_code];
      [aCoder decodeValueOfObjCType: @encode(id) at: &_domain];
      [aCoder decodeValueOfObjCType: @encode(id) at: &_userInfo];
    }
  return self;
}

- (id) initWithDomain: (NSString*)aDomain
		 code: (int)aCode
	     userInfo: (NSDictionary*)aDictionary
{
  if (aDomain == nil)
    {
      NSLog(@"[%@-%@] with nil domain",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd));
      DESTROY(self);
    }
  else if ((self = [super init]) != nil)
    {
      ASSIGN(_domain, aDomain);
      _code = aCode;
      ASSIGN(_userInfo, aDictionary);
    }
  return self;
}

- (NSString *)localizedDescription
{
  NSString	*desc = [_userInfo objectForKey: NSLocalizedDescriptionKey];

  if (desc == nil)
    {
      desc = [NSString stringWithFormat: @"%@ %d", _domain, _code];
    }
  return desc;
}

- (NSDictionary*) userInfo
{
  return _userInfo;
}
@end

