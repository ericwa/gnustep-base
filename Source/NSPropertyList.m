/** Interface for NSPropertyList for GNUStep
   Copyright (C) 2003,2004 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   
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

#include "config.h"
#include <string.h>
#include "GNUstepBase/preface.h"
#include "GNUstepBase/GSMime.h"

#include "Foundation/NSArray.h"
#include "Foundation/NSAutoreleasePool.h"
#include "Foundation/NSCalendarDate.h"
#include "Foundation/NSCharacterSet.h"
#include "Foundation/NSData.h"
#include "Foundation/NSDictionary.h"
#include "Foundation/NSException.h"
#include "Foundation/NSPropertyList.h"
#include "Foundation/NSSerialization.h"
#include "Foundation/NSString.h"
#include "Foundation/NSUserDefaults.h"
#include "Foundation/NSValue.h"
#include "Foundation/NSDebug.h"

extern BOOL GSScanDouble(unichar*, unsigned, double*);

@class	GSString;
@class	GSMutableString;
@class	GSMutableArray;
@class	GSMutableDictionary;


/*
 * Cache classes and method implementations for speed.
 */
static Class	NSDataClass;
static Class	NSStringClass;
static Class	NSMutableStringClass;
static Class	GSStringClass;
static Class	GSMutableStringClass;

static Class	plArray;
static id	(*plAdd)(id, SEL, id) = 0;

static Class	plDictionary;
static id	(*plSet)(id, SEL, id, id) = 0;


#define IS_BIT_SET(a,i) ((((a) & (1<<(i)))) > 0)

static unsigned const char *hexdigitsBitmapRep = NULL;
#define GS_IS_HEXDIGIT(X) IS_BIT_SET(hexdigitsBitmapRep[(X)/8], (X) % 8)

static void setupHexdigits(void)
{
  if (hexdigitsBitmapRep == NULL)
    {
      NSCharacterSet *hexdigits;
      NSData *bitmap;

      hexdigits = [NSCharacterSet characterSetWithCharactersInString:
	@"0123456789abcdefABCDEF"];
      bitmap = RETAIN([hexdigits bitmapRepresentation]);
      hexdigitsBitmapRep = [bitmap bytes];
    }
}

static NSCharacterSet *quotables = nil;
static NSCharacterSet *oldQuotables = nil;
static NSCharacterSet *xmlQuotables = nil;

static unsigned const char *quotablesBitmapRep = NULL;
#define GS_IS_QUOTABLE(X) IS_BIT_SET(quotablesBitmapRep[(X)/8], (X) % 8)

static void setupQuotables(void)
{
  if (quotablesBitmapRep == NULL)
    {
      NSMutableCharacterSet	*s;
      NSData			*bitmap;

      s = [[NSCharacterSet characterSetWithCharactersInString:
	@"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	@"abcdefghijklmnopqrstuvwxyz!#$%&*+-./:?@|~_^"]
	mutableCopy];
      [s invert];
      quotables = [s copy];
      RELEASE(s);
      bitmap = RETAIN([quotables bitmapRepresentation]);
      quotablesBitmapRep = [bitmap bytes];
      s = [[NSCharacterSet characterSetWithCharactersInString:
	@"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	@"abcdefghijklmnopqrstuvwxyz$./_"]
	mutableCopy];
      [s invert];
      oldQuotables = [s copy];
      RELEASE(s);

      s = [[NSCharacterSet characterSetWithCharactersInString:
	@"&<>'\\\""] mutableCopy];
      [s addCharactersInRange: NSMakeRange(0x0001, 0x001f)];
      [s removeCharactersInRange: NSMakeRange(0x0009, 0x0002)];
      [s removeCharactersInRange: NSMakeRange(0x000D, 0x0001)];
      [s addCharactersInRange: NSMakeRange(0xD800, 0x07FF)];
      [s addCharactersInRange: NSMakeRange(0xFFFE, 0x0002)];
      xmlQuotables = [s copy];
      RELEASE(s);
    }
}

static unsigned const char *whitespaceBitmapRep = NULL;
#define GS_IS_WHITESPACE(X) IS_BIT_SET(whitespaceBitmapRep[(X)/8], (X) % 8)

static void setupWhitespace(void)
{
  if (whitespaceBitmapRep == NULL)
    {
      NSCharacterSet *whitespace;
      NSData *bitmap;

/*
  We can not use whitespaceAndNewlineCharacterSet here as this would lead
  to a recursion, as this also reads in a property list.
      whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
*/
      whitespace = [NSCharacterSet characterSetWithCharactersInString:
				    @" \t\r\n\f\b"];

      bitmap = RETAIN([whitespace bitmapRepresentation]);
      whitespaceBitmapRep = [bitmap bytes];
    }
}

static id	GSPropertyListFromStringsFormat(NSString *string);


#ifdef	HAVE_LIBXML
#include	"GNUstepBase/GSXML.h"
static int      XML_ELEMENT_NODE;
#endif

#define inrange(ch,min,max) ((ch)>=(min) && (ch)<=(max))
#define char2num(ch) \
inrange(ch,'0','9') \
? ((ch)-0x30) \
: (inrange(ch,'a','f') \
? ((ch)-0x57) : ((ch)-0x37))

typedef	struct	{
  const unsigned char	*ptr;
  unsigned	end;
  unsigned	pos;
  unsigned	lin;
  NSString	*err;
  NSPropertyListMutabilityOptions opt;
  BOOL		key;
  BOOL		old;
} pldata;

/*
 *	Property list parsing - skip whitespace keeping count of lines and
 *	regarding objective-c style comments as whitespace.
 *	Returns YES if there is any non-whitespace text remaining.
 */
static BOOL skipSpace(pldata *pld)
{
  unsigned char	c;

  while (pld->pos < pld->end)
    {
      c = pld->ptr[pld->pos];

      if (GS_IS_WHITESPACE(c) == NO)
	{
	  if (c == '/' && pld->pos < pld->end - 1)
	    {
	      /*
	       * Check for comments beginning '/' followed by '/' or '*'
	       */
	      if (pld->ptr[pld->pos + 1] == '/')
		{
		  pld->pos += 2;
		  while (pld->pos < pld->end)
		    {
		      c = pld->ptr[pld->pos];
		      if (c == '\n')
			{
			  break;
			}
		      pld->pos++;
		    }
		  if (pld->pos >= pld->end)
		    {
		      pld->err = @"reached end of string in comment";
		      return NO;
		    }
		}
	      else if (pld->ptr[pld->pos + 1] == '*')
		{
		  pld->pos += 2;
		  while (pld->pos < pld->end)
		    {
		      c = pld->ptr[pld->pos];
		      if (c == '\n')
			{
			  pld->lin++;
			}
		      else if (c == '*' && pld->pos < pld->end - 1
			&& pld->ptr[pld->pos+1] == '/')
			{
			  pld->pos++; /* Skip past '*'	*/
			  break;
			}
		      pld->pos++;
		    }
		  if (pld->pos >= pld->end)
		    {
		      pld->err = @"reached end of string in comment";
		      return NO;
		    }
		}
	      else
		{
		  return YES;
		}
	    }
	  else
	    {
	      return YES;
	    }
	}
      if (c == '\n')
	{
	  pld->lin++;
	}
      pld->pos++;
    }
  pld->err = @"reached end of string";
  return NO;
}

static inline id parseQuotedString(pldata* pld)
{
  unsigned	start = ++pld->pos;
  unsigned	escaped = 0;
  unsigned	shrink = 0;
  BOOL		hex = NO;
  NSString	*obj;

  while (pld->pos < pld->end)
    {
      unsigned char	c = pld->ptr[pld->pos];

      if (escaped)
	{
	  if (escaped == 1 && c >= '0' && c <= '7')
	    {
	      escaped = 2;
	      hex = NO;
	    }
	  else if (escaped == 1 && (c == 'u' || c == 'U'))
	    {
	      escaped = 2;
	      hex = YES;
	    }
	  else if (escaped > 1)
	    {
	      if (hex && GS_IS_HEXDIGIT(c))
		{
		  shrink++;
		  escaped++;
		  if (escaped == 6)
		    {
		      escaped = 0;
		    }
		}
	      else if (c >= '0' && c <= '7')
		{
		  shrink++;
		  escaped++;
		  if (escaped == 4)
		    {
		      escaped = 0;
		    }
		}
	      else
		{
		  pld->pos--;
		  escaped = 0;
		}
	    }
	  else
	    {
	      escaped = 0;
	    }
	}
      else
	{
	  if (c == '\\')
	    {
	      escaped = 1;
	      shrink++;
	    }
	  else if (c == '"')
	    {
	      break;
	    }
	}
      if (c == '\n')
	pld->lin++;
      pld->pos++;
    }
  if (pld->pos >= pld->end)
    {
      pld->err = @"reached end of string while parsing quoted string";
      return nil;
    }
  if (pld->pos - start - shrink == 0)
    {
      obj = @"";
    }
  else
    {
      unsigned	length = pld->pos - start - shrink;
      unichar	*chars;
      unsigned	j;
      unsigned	k;

      chars = NSZoneMalloc(NSDefaultMallocZone(), sizeof(unichar) * length);
      escaped = 0;
      hex = NO;
      for (j = start, k = 0; j < pld->pos; j++)
	{
	  unsigned char	c = pld->ptr[j];

	  if (escaped)
	    {
	      if (escaped == 1 && c >= '0' && c <= '7')
		{
		  chars[k] = c - '0';
		  hex = NO;
		  escaped++;
		}
	      else if (escaped == 1 && (c == 'u' || c == 'U'))
		{
		  chars[k] = 0;
		  hex = YES;
		  escaped++;
		}
	      else if (escaped > 1)
		{
		  if (hex && GS_IS_HEXDIGIT(c))
		    {
		      chars[k] <<= 4;
		      chars[k] |= char2num(c);
		      escaped++;
		      if (escaped == 6)
			{
			  escaped = 0;
			  k++;
			}
		    }
		  else if (c >= '0' && c <= '7')
		    {
		      chars[k] <<= 3;
		      chars[k] |= (c - '0');
		      escaped++;
		      if (escaped == 4)
			{
			  escaped = 0;
			  k++;
			}
		    }
		  else
		    {
		      escaped = 0;
		      j--;
		      k++;
		    }
		}
	      else
		{
		  escaped = 0;
		  switch (c)
		    {
		      case 'a' : chars[k] = '\a'; break;
		      case 'b' : chars[k] = '\b'; break;
		      case 't' : chars[k] = '\t'; break;
		      case 'r' : chars[k] = '\r'; break;
		      case 'n' : chars[k] = '\n'; break;
		      case 'v' : chars[k] = '\v'; break;
		      case 'f' : chars[k] = '\f'; break;
		      default  : chars[k] = c; break;
		    }
		  k++;
		}
	    }
	  else
	    {
	      chars[k] = c;
	      if (c == '\\')
		{
		  escaped = 1;
		}
	      else
		{
		  k++;
		}
	    }
	}

      if (pld->key ==
	NO && pld->opt == NSPropertyListMutableContainersAndLeaves)
	{
	  obj = [GSMutableString alloc];
	  obj = [obj initWithCharactersNoCopy: chars
				       length: length
				 freeWhenDone: YES];
	}
      else
	{
	  obj = [GSMutableString alloc];
	  obj = [obj initWithCharactersNoCopy: chars
				       length: length
				 freeWhenDone: YES];
	}
    }
  pld->pos++;
  return obj;
}

static inline id parseUnquotedString(pldata *pld)
{
  unsigned	start = pld->pos;
  unsigned	i;
  unsigned	length;
  id		obj;
  unichar	*chars;

  while (pld->pos < pld->end)
    {
      if (GS_IS_QUOTABLE(pld->ptr[pld->pos]) == YES)
	break;
      pld->pos++;
    }

  length = pld->pos - start;
  chars = NSZoneMalloc(NSDefaultMallocZone(), sizeof(unichar) * length);
  for (i = 0; i < length; i++)
    {
      chars[i] = pld->ptr[start + i];
    }

  if (pld->key == NO && pld->opt == NSPropertyListMutableContainersAndLeaves)
    {
      obj = [GSMutableString alloc];
      obj = [obj initWithCharactersNoCopy: chars
				   length: length
			     freeWhenDone: YES];
    }
  else
    {
      obj = [GSMutableString alloc];
      obj = [obj initWithCharactersNoCopy: chars
				   length: length
			     freeWhenDone: YES];
    }
  return obj;
}

static id parsePlItem(pldata* pld)
{
  id	result = nil;
  BOOL	start = (pld->pos == 0 ? YES : NO);

  if (skipSpace(pld) == NO)
    {
      return nil;
    }
  switch (pld->ptr[pld->pos])
    {
      case '{':
	{
	  NSMutableDictionary	*dict;

	  dict = [[plDictionary allocWithZone: NSDefaultMallocZone()]
	    initWithCapacity: 0];
	  pld->pos++;
	  while (skipSpace(pld) == YES && pld->ptr[pld->pos] != '}')
	    {
	      id	key;
	      id	val;

	      pld->key = YES;
	      key = parsePlItem(pld);
	      pld->key = NO;
	      if (key == nil)
		{
		  return nil;
		}
	      if (skipSpace(pld) == NO)
		{
		  RELEASE(key);
		  RELEASE(dict);
		  return nil;
		}
	      if (pld->ptr[pld->pos] != '=')
		{
		  pld->err = @"unexpected character (wanted '=')";
		  RELEASE(key);
		  RELEASE(dict);
		  return nil;
		}
	      pld->pos++;
	      val = parsePlItem(pld);
	      if (val == nil)
		{
		  RELEASE(key);
		  RELEASE(dict);
		  return nil;
		}
	      if (skipSpace(pld) == NO)
		{
		  RELEASE(key);
		  RELEASE(val);
		  RELEASE(dict);
		  return nil;
		}
	      if (pld->ptr[pld->pos] == ';')
		{
		  pld->pos++;
		}
	      else if (pld->ptr[pld->pos] != '}')
		{
		  pld->err = @"unexpected character (wanted ';' or '}')";
		  RELEASE(key);
		  RELEASE(val);
		  RELEASE(dict);
		  return nil;
		}
	      (*plSet)(dict, @selector(setObject:forKey:), val, key);
	      RELEASE(key);
	      RELEASE(val);
	    }
	  if (pld->pos >= pld->end)
	    {
	      pld->err = @"unexpected end of string when parsing dictionary";
	      RELEASE(dict);
	      return nil;
	    }
	  pld->pos++;
	  result = dict;
	  if (pld->opt == NSPropertyListImmutable)
	    {
	      [result makeImmutableCopyOnFail: NO];
	    }
	}
	break;

      case '(':
	{
	  NSMutableArray	*array;

	  array = [[plArray allocWithZone: NSDefaultMallocZone()]
	    initWithCapacity: 0];
	  pld->pos++;
	  while (skipSpace(pld) == YES && pld->ptr[pld->pos] != ')')
	    {
	      id	val;

	      val = parsePlItem(pld);
	      if (val == nil)
		{
		  RELEASE(array);
		  return nil;
		}
	      if (skipSpace(pld) == NO)
		{
		  RELEASE(val);
		  RELEASE(array);
		  return nil;
		}
	      if (pld->ptr[pld->pos] == ',')
		{
		  pld->pos++;
		}
	      else if (pld->ptr[pld->pos] != ')')
		{
		  pld->err = @"unexpected character (wanted ',' or ')')";
		  RELEASE(val);
		  RELEASE(array);
		  return nil;
		}
	      (*plAdd)(array, @selector(addObject:), val);
	      RELEASE(val);
	    }
	  if (pld->pos >= pld->end)
	    {
	      pld->err = @"unexpected end of string when parsing array";
	      RELEASE(array);
	      return nil;
	    }
	  pld->pos++;
	  result = array;
	  if (pld->opt == NSPropertyListImmutable)
	    {
	      [result makeImmutableCopyOnFail: NO];
	    }
	}
	break;

      case '<':
	pld->pos++;
	if (pld->pos < pld->end && pld->ptr[pld->pos] == '*')
	  {
	    const unsigned char	*ptr;
	    unsigned		min;
	    unsigned		len = 0;
	    unsigned		i;

	    pld->old = NO;
	    pld->pos++;
	    min = pld->pos;
	    ptr = &(pld->ptr[min]);
	    while (pld->pos < pld->end && pld->ptr[pld->pos] != '>')
	      {
		pld->pos++;
	      }
	    len = pld->pos - min;
	    if (len > 1)
	      {
		unsigned char	type = *ptr++;

		len--;
		if (type == 'I')
		  {
		    char	buf[len+1];

		    for (i = 0; i < len; i++) buf[i] = (char)ptr[i];
		    buf[len] = '\0';
		    result = [[NSNumber alloc] initWithLong: atol(buf)];
		  }
		else if (type == 'B')
		  {
		    if (ptr[0] == 'Y')
		      {
			result = [[NSNumber alloc] initWithBool: YES];
		      }
		    else if (ptr[0] == 'N')
		      {
			result = [[NSNumber alloc] initWithBool: NO];
		      }
		    else
		      {
			pld->err = @"bad value for bool";
			return nil;
		      }
		  }
		else if (type == 'D')
		  {
		    unichar	buf[len];
		    unsigned	i;
		    NSString	*str;

		    for (i = 0; i < len; i++) buf[i] = ptr[i];
		    str = [[NSString alloc] initWithCharacters: buf
							length: len];
		    result = [[NSCalendarDate alloc] initWithString: str
		      calendarFormat: @"%Y-%m-%d %H:%M:%S %z"];
		    RELEASE(str);
		  }
		else if (type == 'R')
		  {
		    unichar	buf[len];
		    double	d = 0.0;

		    for (i = 0; i < len; i++) buf[i] = ptr[i];
		    GSScanDouble(buf, len, &d);
		    result = [[NSNumber alloc] initWithDouble: d];
		  }
		else
		  {
		    pld->err = @"unrecognized type code after '<*'";
		    return nil;
		  }
	      }
	    else
	      {
		pld->err = @"missing type code after '<*'";
		return nil;
	      }
	    if (pld->pos >= pld->end)
	      {
		pld->err = @"unexpected end of string when parsing data";
		return nil;
	      }
	    if (pld->ptr[pld->pos] != '>')
	      {
		pld->err = @"unexpected character in string";
		return nil;
	      }
	    pld->pos++;
	  }
	else
	  {
	    NSMutableData	*data;
	    unsigned	max = pld->end - 1;
	    unsigned	char	buf[BUFSIZ];
	    unsigned	len = 0;

	    data = [[NSMutableData alloc] initWithCapacity: 0];
	    skipSpace(pld);
	    while (pld->pos < max
	      && GS_IS_HEXDIGIT(pld->ptr[pld->pos])
	      && GS_IS_HEXDIGIT(pld->ptr[pld->pos+1]))
	      {
		unsigned char	byte;

		byte = (char2num(pld->ptr[pld->pos])) << 4;
		pld->pos++;
		byte |= char2num(pld->ptr[pld->pos]);
		pld->pos++;
		buf[len++] = byte;
		if (len == sizeof(buf))
		  {
		    [data appendBytes: buf length: len];
		    len = 0;
		  }
		skipSpace(pld);
	      }
	    if (pld->pos >= pld->end)
	      {
		pld->err = @"unexpected end of string when parsing data";
		RELEASE(data);
		return nil;
	      }
	    if (pld->ptr[pld->pos] != '>')
	      {
		pld->err = @"unexpected character in string";
		RELEASE(data);
		return nil;
	      }
	    if (len > 0)
	      {
		[data appendBytes: buf length: len];
	      }
	    pld->pos++;
	    // FIXME ... should be immutable sometimes.
	    result = data;
	  }
	break;

      case '"':
	result = parseQuotedString(pld);
	break;

      default:
	result = parseUnquotedString(pld);
	break;
    }
  if (start == YES && result != nil)
    {
      if (skipSpace(pld) == YES)
	{
	  pld->err = @"extra data after parsed string";
	  result = nil;		// Not at end of string.
	}
    }
  return result;
}

#ifdef	HAVE_LIBXML
static GSXMLNode*
elementNode(GSXMLNode* node)
{
  while (node != nil)
    {
      if ([node type] == XML_ELEMENT_NODE)
        {
          break;
        }
      node = [node next];
    }
  return node;
}

static id
nodeToObject(GSXMLNode* node, NSPropertyListMutabilityOptions o, NSString **e)
{
  CREATE_AUTORELEASE_POOL(arp);
  id		result = nil;

  node = elementNode(node);
  if (node != nil)
    {
      NSString	*name;
      NSString	*content;
      GSXMLNode	*children;
      BOOL	isKey = NO;

      name = [node name];
      children = [node firstChild];
      content = [children content];
      children = elementNode(children);

      isKey = [name isEqualToString: @"key"];
      if (isKey == YES || [name isEqualToString: @"string"] == YES)
	{
	  if (content == nil)
	    {
	      content = @"";
	    }
	  else
	    {
	      NSRange	r;

	      r = [content rangeOfString: @"\\"];
	      if (r.length == 1)
		{
		  unsigned	len = [content length];
		  unichar	buf[len];
		  unsigned	pos = r.location;

		  [content getCharacters: buf];
		  while (pos < len)
		    {
		      if (++pos < len)
			{
			  if ((buf[pos] == 'u' || buf[pos] == 'U')
			    && (len >= pos + 4))
			    {
			      unichar	val = 0;
			      unsigned	i;
			      BOOL	ok = YES;

			      for (i = 1; i < 5; i++)
				{
				  unichar	c = buf[pos + i];

				  if (c >= '0' && c <= '9')
				    {
				      val = (val << 4) + c - '0';
				    }
				  else if (c >= 'A' && c <= 'F')
				    {
				      val = (val << 4) + c - 'A' + 10;
				    }
				  else if (c >= 'a' && c <= 'f')
				    {
				      val = (val << 4) + c - 'a' + 10;
				    }
				  else
				    {
				      ok = NO;
				    }
				}
			      if (ok == YES)
				{
				  len -= 5;
				  memcpy(&buf[pos], &buf[pos+5],
				    (len - pos) * sizeof(unichar));
				  buf[pos - 1] = val;
				}
			    }
			  while (pos < len && buf[pos] != '\\')
			    {
			      pos++;
			    }
			}
		    }
		  if (isKey == NO
		    && o == NSPropertyListMutableContainersAndLeaves)
		    {
		      content = [NSMutableString stringWithCharacters: buf
							       length: len];
		    }
		  else
		    {
		      content = [NSString stringWithCharacters: buf
							length: len];
		    }
		}
	    }
	  result = content;
	}
      else if ([name isEqualToString: @"true"])
	{
	  result = [NSNumber numberWithBool: YES];
	}
      else if ([name isEqualToString: @"false"])
	{
	  result = [NSNumber numberWithBool: NO];
	}
      else if ([name isEqualToString: @"integer"])
	{
	  if (content == nil)
	    {
	      content = @"0";
	    }
	  result = [NSNumber numberWithInt: [content intValue]];
	}
      else if ([name isEqualToString: @"real"])
	{
	  if (content == nil)
	    {
	      content = @"0.0";
	    }
	  result = [NSNumber numberWithDouble: [content doubleValue]];
	}
      else if ([name isEqualToString: @"date"])
	{
	  if (content == nil)
	    {
	      content = @"";
	    }
	  result = [NSCalendarDate dateWithString: content
				   calendarFormat: @"%Y-%m-%d %H:%M:%S %z"];
	}
      else if ([name isEqualToString: @"data"])
	{
	  result = [GSMimeDocument decodeBase64String: content];
	  if (o == NSPropertyListMutableContainersAndLeaves)
	    {
	      result = AUTORELEASE([result mutableCopy]);
	    }
	}
      // container class
      else if ([name isEqualToString: @"array"])
	{
	  NSMutableArray	*container = [plArray array];

	  while (children != nil)
	    {
	      id	val;

	      val = nodeToObject(children, o, e);
	      [container addObject: val];
	      children = [children nextElement];
	    }
	  result = container;
	  if (o == NSPropertyListImmutable)
	    {
	      [result makeImmutableCopyOnFail: NO];
	    }
	}
      else if ([name isEqualToString: @"dict"])
	{
	  NSMutableDictionary	*container = [plDictionary dictionary];

	  while (children != nil)
	    {
	      NSString	*key;
	      id	val;

	      key = nodeToObject(children, o, e);
	      children = [children nextElement];
	      val = nodeToObject(children, o, e);
	      children = [children nextElement];
	      [container setObject: val forKey: key];
	    }
	  result = container;
	  if (o == NSPropertyListImmutable)
	    {
	      [result makeImmutableCopyOnFail: NO];
	    }
	}
    }
  RETAIN(result);
  RELEASE(arp);
  return AUTORELEASE(result);
}
#endif

static id
GSPropertyListFromStringsFormat(NSString *string)
{
  NSMutableDictionary	*dict;
  pldata		_pld;
  pldata		*pld = &_pld;
  unsigned		length = [string length];
  NSData		*d;

  /*
   * An empty string is a nil property list.
   */
  if (length == 0)
    {
      return nil;
    }

  d = [string dataUsingEncoding: NSUnicodeStringEncoding];
  _pld.ptr = (unsigned char*)[d bytes];
  _pld.pos = 1;
  _pld.end = length + 1;
  _pld.err = nil;
  _pld.lin = 1;
  _pld.opt = NSPropertyListImmutable;
  _pld.key = NO;
  _pld.old = YES;	// OpenStep style
  [NSPropertyListSerialization class];	// initialise

  dict = [[plDictionary allocWithZone: NSDefaultMallocZone()]
    initWithCapacity: 0];
  while (skipSpace(pld) == YES)
    {
      id	key;
      id	val;

      if (pld->ptr[pld->pos] == '"')
	{
	  key = parseQuotedString(pld);
	}
      else
	{
	  key = parseUnquotedString(pld);
	}
      if (key == nil)
	{
	  DESTROY(dict);
	  break;
	}
      if (skipSpace(pld) == NO)
	{
	  pld->err = @"incomplete final entry (no semicolon?)";
	  RELEASE(key);
	  DESTROY(dict);
	  break;
	}
      if (pld->ptr[pld->pos] == ';')
	{
	  pld->pos++;
	  (*plSet)(dict, @selector(setObject:forKey:), @"", key);
	  RELEASE(key);
	}
      else if (pld->ptr[pld->pos] == '=')
	{
	  pld->pos++;
	  if (skipSpace(pld) == NO)
	    {
	      RELEASE(key);
	      DESTROY(dict);
	      break;
	    }
	  if (pld->ptr[pld->pos] == '"')
	    {
	      val = parseQuotedString(pld);
	    }
	  else
	    {
	      val = parseUnquotedString(pld);
	    }
	  if (val == nil)
	    {
	      RELEASE(key);
	      DESTROY(dict);
	      break;
	    }
	  if (skipSpace(pld) == NO)
	    {
	      pld->err = @"missing final semicolon";
	      RELEASE(key);
	      RELEASE(val);
	      DESTROY(dict);
	      break;
	    }
	  (*plSet)(dict, @selector(setObject:forKey:), val, key);
	  RELEASE(key);
	  RELEASE(val);
	  if (pld->ptr[pld->pos] == ';')
	    {
	      pld->pos++;
	    }
	  else
	    {
	      pld->err = @"unexpected character (wanted ';')";
	      DESTROY(dict);
	      break;
	    }
	}
      else
	{
	  pld->err = @"unexpected character (wanted '=' or ';')";
	  RELEASE(key);
	  DESTROY(dict);
	  break;
	}
    }
  if (dict == nil && _pld.err != nil)
    {
      RELEASE(dict);
      [NSException raise: NSGenericException
		  format: @"Parse failed at line %d (char %d) - %@",
	_pld.lin, _pld.pos, _pld.err];
    }
  return AUTORELEASE(dict);
}



#include <math.h>

static char base64[]
  = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static void
encodeBase64(NSData *source, NSMutableData *dest)
{
  int		length = [source length];
  int		enclen = length / 3;
  int		remlen = length - 3 * enclen;
  int		destlen = 4 * ((length + 2) / 3);
  unsigned char *sBuf;
  unsigned char *dBuf;
  int		sIndex = 0;
  int		dIndex = [dest length];

  [dest setLength: dIndex + destlen];

  if (length == 0)
    {
      return;
    }
  sBuf = (unsigned char*)[source bytes];
  dBuf = [dest mutableBytes];

  for (sIndex = 0; sIndex < length - 2; sIndex += 3, dIndex += 4)
    {
      dBuf[dIndex] = base64[sBuf[sIndex] >> 2];
      dBuf[dIndex + 1]
	= base64[((sBuf[sIndex] << 4) | (sBuf[sIndex + 1] >> 4)) & 0x3f];
      dBuf[dIndex + 2]
	= base64[((sBuf[sIndex + 1] << 2) | (sBuf[sIndex + 2] >> 6)) & 0x3f];
      dBuf[dIndex + 3] = base64[sBuf[sIndex + 2] & 0x3f];
    }

  if (remlen == 1)
    {
      dBuf[dIndex] = base64[sBuf[sIndex] >> 2];
      dBuf[dIndex + 1] = (sBuf[sIndex] << 4) & 0x30;
      dBuf[dIndex + 1] = base64[dBuf[dIndex + 1]];
      dBuf[dIndex + 2] = '=';
      dBuf[dIndex + 3] = '=';
    }
  else if (remlen == 2)
    {
      dBuf[dIndex] = base64[sBuf[sIndex] >> 2];
      dBuf[dIndex + 1] = (sBuf[sIndex] << 4) & 0x30;
      dBuf[dIndex + 1] |= sBuf[sIndex + 1] >> 4;
      dBuf[dIndex + 1] = base64[dBuf[dIndex + 1]];
      dBuf[dIndex + 2] = (sBuf[sIndex + 1] << 2) & 0x3c;
      dBuf[dIndex + 2] = base64[dBuf[dIndex + 2]];
      dBuf[dIndex + 3] = '=';
    }
}

static inline void Append(void *bytes, unsigned length, NSMutableData *dst)
{
  [dst appendBytes: bytes length: length];
}

/*
 * Output a string escaped for OpenStep style property lists.
 * The result is ascii data.
 */
static void
PString(NSString *obj, NSMutableData *output)
{
  unsigned	length;

  if ((length = [obj length]) == 0)
    {
      [output appendBytes: "\"\"" length: 2];
    }
  else if ([obj rangeOfCharacterFromSet: oldQuotables].length > 0
    || [obj characterAtIndex: 0] == '/')
    {
      unichar		tmp[length <= 1024 ? length : 0];
      unichar		*ustring;
      unichar		*from;
      unichar		*end;
      unsigned char	*ptr;
      int		len = 0;

      if (length <= 1024)
	{
	  ustring = tmp;
	}
      else
	{
	  ustring = NSZoneMalloc(NSDefaultMallocZone(), length*sizeof(unichar));
	}
      end = &ustring[length];
      [obj getCharacters: ustring];
      for (from = ustring; from < end; from++)
	{
	  switch (*from)
	    {
	      case '\a':
	      case '\b':
	      case '\t':
	      case '\r':
	      case '\n':
	      case '\v':
	      case '\f':
	      case '\\':
	      case '\'' :
	      case '"' :
		len += 2;
		break;

	      default:
		if (*from < 128)
		  {
		    if (isprint(*from) || *from == ' ')
		      {
			len++;
		      }
		    else
		      {
			len += 4;
		      }
		  }
		else
		  {
		    len += 6;
		  }
		break;
	    }
	}

      [output setLength: [output length] + len + 2];
      ptr = [output mutableBytes] + [output length];
      *ptr++ = '"';
      for (from = ustring; from < end; from++)
	{
	  switch (*from)
	    {
	      case '\a': 	*ptr++ = '\\'; *ptr++ = 'a';  break;
	      case '\b': 	*ptr++ = '\\'; *ptr++ = 'b';  break;
	      case '\t': 	*ptr++ = '\\'; *ptr++ = 't';  break;
	      case '\r': 	*ptr++ = '\\'; *ptr++ = 'r';  break;
	      case '\n': 	*ptr++ = '\\'; *ptr++ = 'n';  break;
	      case '\v': 	*ptr++ = '\\'; *ptr++ = 'v';  break;
	      case '\f': 	*ptr++ = '\\'; *ptr++ = 'f';  break;
	      case '\\': 	*ptr++ = '\\'; *ptr++ = '\\'; break;
	      case '\'': 	*ptr++ = '\\'; *ptr++ = '\''; break;
	      case '"' : 	*ptr++ = '\\'; *ptr++ = '"';  break;

	      default:
		if (*from < 128)
		  {
		    if (isprint(*from) || *from == ' ')
		      {
			*ptr++ = *from;
		      }
		    else
		      {
			unichar	c = *from;

			sprintf(ptr, "\\%03o", c);
			ptr = &ptr[4];
		      }
		  }
		else
		  {
		    sprintf(ptr, "\\u%04x", *from);
		    ptr = &ptr[6];
		  }
		break;
	    }
	}
      *ptr++ = '"';

      if (ustring != tmp)
	{
	  NSZoneFree(NSDefaultMallocZone(), ustring);
	}
    }
  else
    {
      NSData	*d = [obj dataUsingEncoding: NSASCIIStringEncoding];

      [output appendData: d];
    }
}

/*
 * Output a string escaped for use in xml.
 * Result is utf8 data.
 */
static void
XString(NSString* obj, NSMutableData *output)
{
  static char	*hexdigits = "0123456789ABCDEF";
  unsigned	end;

  end = [obj length];
  if (end == 0)
    {
      return;
    }

  if ([obj rangeOfCharacterFromSet: xmlQuotables].length > 0)
    {
      unichar	*base;
      unichar	*map;
      unichar	c;
      unsigned	len;
      unsigned	rpos;
      unsigned	wpos;

      base = NSZoneMalloc(NSDefaultMallocZone(), end * sizeof(unichar));
      [obj getCharacters: base];
      for (len = rpos = 0; rpos < end; rpos++)
	{
	  c = base[rpos];
	  switch (c)
	    {
	      case '&': 
		len += 5;
		break;
	      case '<': 
	      case '>': 
		len += 4;
		break;
	      case '\'': 
	      case '"': 
		len += 6;
		break;

	      default: 
		if ((c < 0x20 && (c != 0x09 && c != 0x0A && c != 0x0D))
		  || (c > 0xD7FF && c < 0xE000) || c > 0xFFFD)
		  {
		    len += 6;
		  }
		else
		  {
		    len++;
		  }
		break;
	    }
	}
      map = NSZoneMalloc(NSDefaultMallocZone(), len * sizeof(unichar));
      for (wpos = rpos = 0; rpos < end; rpos++)
	{
	  c = base[rpos];
	  switch (c)
	    {
	      case '&': 
		map[wpos++] = '&';
		map[wpos++] = 'a';
		map[wpos++] = 'm';
		map[wpos++] = 'p';
		map[wpos++] = ';';
		break;
	      case '<': 
		map[wpos++] = '&';
		map[wpos++] = 'l';
		map[wpos++] = 't';
		map[wpos++] = ';';
		break;
	      case '>': 
		map[wpos++] = '&';
		map[wpos++] = 'g';
		map[wpos++] = 't';
		map[wpos++] = ';';
		break;
	      case '\'': 
		map[wpos++] = '&';
		map[wpos++] = 'a';
		map[wpos++] = 'p';
		map[wpos++] = 'o';
		map[wpos++] = 's';
		map[wpos++] = ';';
		break;
	      case '"': 
		map[wpos++] = '&';
		map[wpos++] = 'q';
		map[wpos++] = 'u';
		map[wpos++] = 'o';
		map[wpos++] = 't';
		map[wpos++] = ';';
		break;

	      default: 
		if ((c < 0x20 && (c != 0x09 && c != 0x0A && c != 0x0D))
		  || (c > 0xD7FF && c < 0xE000) || c > 0xFFFD)
		  {
		    map[wpos++] = '\\';
		    map[wpos++] = 'U';
		    map[wpos++] = hexdigits[(c>>12) & 0xf];
		    map[wpos++] = hexdigits[(c>>8) & 0xf];
		    map[wpos++] = hexdigits[(c>>4) & 0xf];
		    map[wpos++] = hexdigits[c & 0xf];
		  }
		else
		  {
		    map[wpos++] = c;
		  }
		break;
	    }
	}
      NSZoneFree(NSDefaultMallocZone(), base);
      obj = [[NSString alloc] initWithCharacters: map length: len];
      [output appendData: [obj dataUsingEncoding: NSUTF8StringEncoding]];
      RELEASE(obj);
    }
  else
    {
      [output appendData: [obj dataUsingEncoding: NSUTF8StringEncoding]];
    }
}


static const char	*indentStrings[] = {
  "",
  "  ",
  "    ",
  "      ",
  "\t",
  "\t  ",
  "\t    ",
  "\t      ",
  "\t\t",
  "\t\t  ",
  "\t\t    ",
  "\t\t      ",
  "\t\t\t",
  "\t\t\t  ",
  "\t\t\t    ",
  "\t\t\t      ",
  "\t\t\t\t",
  "\t\t\t\t  ",
  "\t\t\t\t    ",
  "\t\t\t\t      ",
  "\t\t\t\t\t",
  "\t\t\t\t\t  ",
  "\t\t\t\t\t    ",
  "\t\t\t\t\t      ",
  "\t\t\t\t\t\t"
};

#define	PLNEW	0	// New extended OpenStep property list
#define	PLXML	1	// New MacOS-X XML property list
#define	PLOLD	2	// Old (standard) OpenStep property list
#define	PLDSC	3	// Just a description
/**
 * obj is the object to be written out<br />
 * loc is the locale for formatting (or nil to indicate no formatting)<br />
 * lev is the level of indentation to use<br />
 * step is the indentation step (0 == 0, 1 = 2, 2 = 4, 3 = 8)<br />
 * x is an indicator for xml or old/new openstep property list format<br />
 * dest is the output buffer.
 */
static void
OAppend(id obj, NSDictionary *loc, unsigned lev, unsigned step,
  NSPropertyListFormat x, NSMutableData *dest)
{
  if ([obj isKindOfClass: [NSString class]])
    {
      if (x == NSPropertyListXMLFormat_v1_0)
	{
	  [dest appendBytes: "<string>" length: 8];
	  XString(obj, dest);
	  [dest appendBytes: "</string>\n" length: 10];
	}
      else
	{
	  PString(obj, dest);
	}
    }
  else if ([obj isKindOfClass: [NSNumber class]])
    {
      const char	*t = [obj objCType];

      if (*t ==  'c' || *t == 'C')
	{
	  BOOL	val = [obj boolValue];

	  if (val == YES)
	    {
	      if (x == NSPropertyListXMLFormat_v1_0)
		{
		  [dest appendBytes: "<true/>\n" length: 8];
		}
	      else if (x == NSPropertyListGNUStepFormat)
		{
		  [dest appendBytes: "<*BY>\n" length: 6];
		}
	      else
		{
		  PString([obj description], dest);
		}
	    }
	  else
	    {
	      if (x == NSPropertyListXMLFormat_v1_0)
		{
		  [dest appendBytes: "<false/>\n" length: 9];
		}
	      else if (x == NSPropertyListGNUStepFormat)
		{
		  [dest appendBytes: "<*BN>\n" length: 6];
		}
	      else
		{
		  PString([obj description], dest);
		}
	    }
	}
      else if (strchr("sSiIlLqQ", *t) != 0)
	{
	  if (x == NSPropertyListXMLFormat_v1_0)
	    {
	      [dest appendBytes: "<integer>" length: 8];
	      XString([obj stringValue], dest);
	      [dest appendBytes: "</integer>\n" length: 11];
	    }
	  else if (x == NSPropertyListGNUStepFormat)
	    {
	      [dest appendBytes: "<*I" length: 3];
	      PString([obj stringValue], dest);
	      [dest appendBytes: ">" length: 1];
	    }
	  else
	    {
	      PString([obj description], dest);
	    }
	}
      else
	{
	  if (x == NSPropertyListXMLFormat_v1_0)
	    {
	      [dest appendBytes: "<real>" length: 6];
	      XString([obj stringValue], dest);
	      [dest appendBytes: "</real>" length: 7];
	    }
	  else if (x == NSPropertyListGNUStepFormat)
	    {
	      [dest appendBytes: "<*R" length: 3];
	      PString([obj stringValue], dest);
	      [dest appendBytes: ">" length: 1];
	    }
	  else
	    {
	      PString([obj description], dest);
	    }
	}
    }
  else if ([obj isKindOfClass: [NSData class]])
    {
      if (x == NSPropertyListXMLFormat_v1_0)
	{
	  [dest appendBytes: "<data>\n" length: 7];
	  encodeBase64(obj, dest);
	  [dest appendBytes: "</data>\n" length: 8];
	}
      else
	{
	  const unsigned char	*src;
	  unsigned char		*dst;
	  int		length;
	  int		i;
	  int		j;

	  src = [obj bytes];
	  length = [obj length];
	  #define num2char(num) ((num) < 0xa ? ((num)+'0') : ((num)+0x57))

	  j = [dest length];
	  [dest setLength: j + 2*length+length/4+3]; 
	  dst = [dest mutableBytes];
	  dst[j++] = '<';
	  for (i = 0; i < length; i++, j++)
	    {
	      dst[j++] = num2char((src[i]>>4) & 0x0f);
	      dst[j] = num2char(src[i] & 0x0f);
	      if ((i&0x3) == 3 && i != length-1)
		{
		  /* if we've just finished a 32-bit int, print a space */
		  dst[++j] = ' ';
		}
	    }
	  dst[j++] = '>';
	}
    }
  else if ([obj isKindOfClass: [NSDate class]])
    {
      if (x == NSPropertyListXMLFormat_v1_0)
	{
	  [dest appendBytes: "<date>" length: 6];
	  obj = [obj descriptionWithCalendarFormat: @"%Y-%m-%d %H:%M:%S %z"
	    timeZone: nil locale: nil];
	  obj = [obj dataUsingEncoding: NSASCIIStringEncoding];
	  [dest appendData: obj];
	  [dest appendBytes: "</date>\n" length: 8];
	}
      else if (x == NSPropertyListGNUStepFormat)
	{
	  [dest appendBytes: "<*D" length: 3];
	  obj = [obj descriptionWithCalendarFormat: @"%Y-%m-%d %H:%M:%S %z"
	    timeZone: nil locale: nil];
	  obj = [obj dataUsingEncoding: NSASCIIStringEncoding];
	  [dest appendData: obj];
	  [dest appendBytes: ">" length: 1];
	}
      else
	{
	  obj = [obj descriptionWithCalendarFormat: @"%Y-%m-%d %H:%M:%S %z"
	    timeZone: nil locale: nil];
	  PString(obj, dest);
	}
    }
  else if ([obj isKindOfClass: [NSArray class]])
    {
      const char	*iBaseString;
      const char	*iSizeString;
      unsigned	level = lev;

      if (level*step < sizeof(indentStrings)/sizeof(id))
	{
	  iBaseString = indentStrings[level*step];
	}
      else
	{
	  iBaseString
	    = indentStrings[sizeof(indentStrings)/sizeof(id)-1];
	}
      level++;
      if (level*step < sizeof(indentStrings)/sizeof(id))
	{
	  iSizeString = indentStrings[level*step];
	}
      else
	{
	  iSizeString
	    = indentStrings[sizeof(indentStrings)/sizeof(id)-1];
	}

      if (x == NSPropertyListXMLFormat_v1_0)
	{
	  NSEnumerator	*e;

	  [dest appendBytes: "<array>\n" length: 8];
	  e = [obj objectEnumerator];
	  while ((obj = [e nextObject]))
	    {
	      [dest appendBytes: iSizeString length: strlen(iSizeString)];
	      OAppend(obj, loc, level, step, x, dest);
	    }
	  [dest appendBytes: iBaseString length: strlen(iBaseString)];
	  [dest appendBytes: "</array>\n" length: 9];
	}
      else
	{
	  unsigned		count = [obj count];
	  unsigned		last = count - 1;
	  NSString		*plists[count];
	  unsigned		i;

	  [obj getObjects: plists];

	  if (loc == nil)
	    {
	      [dest appendBytes: "(" length: 1];
	      for (i = 0; i < count; i++)
		{
		  id	item = plists[i];

		  OAppend(item, nil, 0, step, x, dest);
		  if (i != last)
		    {
		      [dest appendBytes: ", " length: 2];
		    }
		}
	      [dest appendBytes: ")" length: 1];
	    }
	  else
	    {
	      [dest appendBytes: "(\n" length: 2];
	      for (i = 0; i < count; i++)
		{
		  id	item = plists[i];

		  [dest appendBytes: iSizeString length: strlen(iSizeString)];
		  OAppend(item, loc, level, step, x, dest);
		  if (i == last)
		    {
		      [dest appendBytes: "\n" length: 1];
		    }
		  else
		    {
		      [dest appendBytes: ",\n" length: 2];
		    }
		}
	      [dest appendBytes: iBaseString length: strlen(iBaseString)];
	      [dest appendBytes: ")" length: 1];
	    }
	}
    }
  else if ([obj isKindOfClass: [NSDictionary class]])
    {
      const char	*iBaseString;
      const char	*iSizeString;
      unsigned	level = lev;

      if (level*step < sizeof(indentStrings)/sizeof(id))
	{
	  iBaseString = indentStrings[level*step];
	}
      else
	{
	  iBaseString
	    = indentStrings[sizeof(indentStrings)/sizeof(id)-1];
	}
      level++;
      if (level*step < sizeof(indentStrings)/sizeof(id))
	{
	  iSizeString = indentStrings[level*step];
	}
      else
	{
	  iSizeString
	    = indentStrings[sizeof(indentStrings)/sizeof(id)-1];
	}

      if (x == NSPropertyListXMLFormat_v1_0)
	{
	  NSEnumerator	*e;
	  id		key;

	  [dest appendBytes: "<dict>\n" length: 7];
	  e = [obj keyEnumerator];
	  while ((key = [e nextObject]))
	    {
	      id	val;

	      val = [obj objectForKey: key];
	      [dest appendBytes: iSizeString length: strlen(iSizeString)];
	      [dest appendBytes: "<key>" length: 5];
	      XString(key, dest);
	      [dest appendBytes: "</key>\n" length: 7];
	      [dest appendBytes: iSizeString length: strlen(iSizeString)];
	      OAppend(val, loc, level, step, x, dest);
	    }
	  [dest appendBytes: iBaseString length: strlen(iBaseString)];
	  [dest appendBytes: "</dict>\n" length: 8];
	}
      else
	{
	  SEL		objSel = @selector(objectForKey:);
	  IMP		myObj = [obj methodForSelector: objSel];
	  unsigned	i;
	  NSArray	*keyArray = [obj allKeys];
	  unsigned	numKeys = [keyArray count];
	  NSString	*plists[numKeys];
	  NSString	*keys[numKeys];
	  BOOL		canCompare = YES;
	  Class		lastClass = 0;

	  [keyArray getObjects: keys];

	  for (i = 0; i < numKeys; i++)
	    {
	      if (GSObjCClass(keys[i]) == lastClass)
		continue;
	      if ([keys[i] respondsToSelector: @selector(compare:)] == NO)
		{
		  canCompare = NO;
		  break;
		}
	      lastClass = GSObjCClass(keys[i]);
	    }

	  if (canCompare == YES)
	    {
	      #define STRIDE_FACTOR 3
	      unsigned	c,d, stride;
	      BOOL		found;
	      NSComparisonResult	(*comp)(id, SEL, id) = 0;
	      unsigned int	count = numKeys;
	      #ifdef	GSWARN
	      BOOL		badComparison = NO;
	      #endif

	      stride = 1;
	      while (stride <= count)
		{
		  stride = stride * STRIDE_FACTOR + 1;
		}
	      lastClass = 0;
	      while (stride > (STRIDE_FACTOR - 1))
		{
		  // loop to sort for each value of stride
		  stride = stride / STRIDE_FACTOR;
		  for (c = stride; c < count; c++)
		    {
		      found = NO;
		      if (stride > c)
			{
			  break;
			}
		      d = c - stride;
		      while (!found)
			{
			  id			a = keys[d + stride];
			  id			b = keys[d];
			  Class			x;
			  NSComparisonResult	r;

			  x = GSObjCClass(a);
			  if (x != lastClass)
			    {
			      lastClass = x;
			      comp = (NSComparisonResult (*)(id, SEL, id))
				[a methodForSelector: @selector(compare:)];
			    }
			  r = (*comp)(a, @selector(compare:), b);
			  if (r < 0)
			    {
			      #ifdef	GSWARN
			      if (r != NSOrderedAscending)
				{
				  badComparison = YES;
				}
			      #endif
			      keys[d + stride] = b;
			      keys[d] = a;
			      if (stride > d)
				{
				  break;
				}
			      d -= stride;
			    }
			  else
			    {
			      #ifdef	GSWARN
			      if (r != NSOrderedDescending
				&& r != NSOrderedSame)
				{
				  badComparison = YES;
				}
			      #endif
			      found = YES;
			    }
			}
		    }
		}
	      #ifdef	GSWARN
	      if (badComparison == YES)
		{
		  NSWarnFLog(@"Detected bad return value from comparison");
		}
	      #endif
	    }

	  for (i = 0; i < numKeys; i++)
	    {
	      plists[i] = (*myObj)(obj, objSel, keys[i]);
	    }

	  if (loc == nil)
	    {
	      [dest appendBytes: "{" length: 1];
	      for (i = 0; i < numKeys; i++)
		{
		  OAppend(keys[i], nil, 0, step, x, dest);
		  [dest appendBytes: " = " length: 3];
		  OAppend(plists[i], nil, 0, step, x, dest);
		  [dest appendBytes: "; " length: 2];
		}
	      [dest appendBytes: "}" length: 1];
	    }
	  else
	    {
	      [dest appendBytes: "{\n" length: 2];
	      for (i = 0; i < numKeys; i++)
		{
		  [dest appendBytes: iSizeString length: strlen(iSizeString)];
		  OAppend(keys[i], loc, level, step, x, dest);
		  [dest appendBytes: " = " length: 3];
		  OAppend(plists[i], loc, level, step, x, dest);
		  [dest appendBytes: ";\n" length: 2];
		}
	      [dest appendBytes: iBaseString length: strlen(iBaseString)];
	      [dest appendBytes: "}" length: 1];
	    }
	}
    }
  else
    {
      if (x == NSPropertyListXMLFormat_v1_0)
	{
	  NSDebugLog(@"Non-property-list class (%@) encoded as string",
	    NSStringFromClass([obj class]));
	  [dest appendBytes: "<string>" length: 8];
	  XString([obj description], dest);
	  [dest appendBytes: "</string>" length: 9];
	}
      else
	{
	  NSDebugLog(@"Non-property-list class (%@) encoded as string",
	    NSStringFromClass([obj class]));
	  PString([obj description], dest);
	}
    }
}




@implementation	NSPropertyListSerialization

+ (void) initialize
{
  static BOOL	beenHere = NO;

  if (beenHere == NO)
    {
      beenHere = YES;

#ifdef	HAVE_LIBXML
      /*
       * Cache XML node information.
       */
      XML_ELEMENT_NODE = [GSXMLNode typeFromDescription: @"XML_ELEMENT_NODE"];
#endif

      NSStringClass = [NSString class];
      NSMutableStringClass = [NSMutableString class];
      NSDataClass = [NSData class];
      GSStringClass = [GSString class];
      GSMutableStringClass = [GSMutableString class];

      plArray = [GSMutableArray class];
      plAdd = (id (*)(id, SEL, id))
	[plArray instanceMethodForSelector: @selector(addObject:)];

      plDictionary = [GSMutableDictionary class];
      plSet = (id (*)(id, SEL, id, id))
	[plDictionary instanceMethodForSelector: @selector(setObject:forKey:)];

      setupHexdigits();
      setupQuotables();
      setupWhitespace();

    }
}

+ (NSData*) dataFromPropertyList: (id)aPropertyList
			  format: (NSPropertyListFormat)aFormat
		errorDescription: (NSString**)anErrorString
{
  NSMutableData	*dest;
  NSDictionary	*loc;
  int		step = 2;

  loc = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
  dest = [NSMutableData dataWithCapacity: 1024];
  
  if (aFormat == NSPropertyListXMLFormat_v1_0)
    {
      const char	*prefix =
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist "
	"PUBLIC \"-//GNUstep//DTD plist 0.9//EN\" "
	"\"http://www.gnustep.org/plist-0_9.xml\">\n"
	"<plist version=\"0.9\">\n";

      [dest appendBytes: prefix length: strlen(prefix)];
      OAppend(aPropertyList, loc, 0, step > 3 ? 3 : step, aFormat, dest);
      [dest appendBytes: "</plist>" length: 8];
    }
  else if (aFormat == NSPropertyListGNUstepBinaryFormat)
    {
      [NSSerializer serializePropertyList: aPropertyList intoData: dest];
    }
  else
    { 
      OAppend(aPropertyList, loc, 0, step > 3 ? 3 : step, aFormat, dest);
    }
  return dest;
}

+ (BOOL) propertyList: (id)aPropertyList
     isValidForFormat: (NSPropertyListFormat)aFormat
{
// FIXME ... need to check properly.
  switch (aFormat)
    {
      case NSPropertyListGNUStepFormat:
	return YES;

      case NSPropertyListGNUstepBinaryFormat:
	return YES;

      case NSPropertyListOpenStepFormat:
	return YES;

      case NSPropertyListXMLFormat_v1_0:
	return YES;
	
      case NSPropertyListBinaryFormat_v1_0:
      default:
	[NSException raise: NSInvalidArgumentException
		    format: @"[%@ +%@]: unsupported format",
	  NSStringFromClass(self), NSStringFromSelector(_cmd)];
	return NO;
    }
}

+ (id) propertyListFromData: (NSData*)data
	   mutabilityOption: (NSPropertyListMutabilityOptions)anOption
		     format: (NSPropertyListFormat*)aFormat
	   errorDescription: (NSString**)anErrorString
{
  NSPropertyListFormat	format;
  NSString		*error = nil;
  id			result = nil;
  const unsigned char	*bytes = 0;
  unsigned int		length = 0;

  if (data == nil)
    {
      error = @"nil data argument passed to method";
    }
  else if ([data isKindOfClass: [NSData class]] == NO)
    {
      error = @"non-NSData data argument passed to method";
    }
  else if ([data length] == 0)
    {
      error = @"empty data argument passed to method";
    }
  else
    {
      bytes = [data bytes];
      length = [data length];
      if (bytes[0] == 0 || bytes[0] == 1)
	{
	  format = NSPropertyListGNUstepBinaryFormat;
	}
      else
	{
	  unsigned int		index = 0;
 
	  // Skip any leading white space.
	  while (index < length && GS_IS_WHITESPACE(bytes[index]) == YES)
	    {
	      index++;
	    }

	  if (length - index > 2
	    && bytes[index] == '<' && bytes[index+1] == '?')
	    {
#ifdef	HAVE_LIBXML
	      // It begins with '<?' so it is xml
	      format = NSPropertyListXMLFormat_v1_0;
#else
	      error = @"XML format not supported ... XML support notn present.";
#endif
	    }
	  else
	    {
	      // Assume openstep format unless we find otherwise.
	      format = NSPropertyListOpenStepFormat;
	    }
	}
    }

  if (error == nil)
    {
      switch (format)
	{
	  case NSPropertyListXMLFormat_v1_0:
	    {
	      GSXMLParser	*parser;
	      GSXMLNode		*node;

	      parser = [GSXMLParser parser];
	      [parser substituteEntities: YES];
	      [parser doValidityChecking: YES];
	      if ([parser parse: data] == NO || [parser parse: nil] == NO)
		{
		  error = @"failed to parse as valid XML matching DTD";
		}
	      node = [[parser document] root];
	      if (error == nil && [[node name] isEqualToString: @"plist"] == NO)
		{
		  error = @"failed to parse as XML property list";
		}
	      if (error == nil)
		{
		  result = nodeToObject([node firstChild], anOption, &error);
		}
	    }
	    break;

	  case NSPropertyListOpenStepFormat:
	    {
	      pldata	_pld;

	      _pld.ptr = bytes;
	      _pld.pos = 1;
	      _pld.end = length + 1;
	      _pld.err = nil;
	      _pld.lin = 1;
	      _pld.opt = anOption;
	      _pld.key = NO;
	      _pld.old = YES;	// OpenStep style

	      result = AUTORELEASE(parsePlItem(&_pld));
	      if (_pld.old == NO)
		{
		  // Found some modern GNUstep extension in data.
		  format = NSPropertyListGNUstepBinaryFormat;
		}
	      if (_pld.err != nil)
		{
		  error = [NSString stringWithFormat:
		    @"Parse failed at line %d (char %d) - %@",
		    _pld.lin, _pld.pos, _pld.err];
		}
	    }
	    break;

	  case NSPropertyListGNUstepBinaryFormat:
	    if (anOption == NSPropertyListImmutable)
	      {
		result = [NSDeserializer deserializePropertyListFromData: data
						       mutableContainers: NO];
	      }
	    else
	      {
		result = [NSDeserializer deserializePropertyListFromData: data
						       mutableContainers: YES];
	      }
	    break;

	  default:
	    error = @"format not supported";
	    break;
	}
    }

  /*
   * Done ... return all values.
   */
  if (anErrorString != 0)
    {
      *anErrorString = error;
    }
  if (aFormat != 0)
    {
      *aFormat = format;
    }
  return result;
}

@end
