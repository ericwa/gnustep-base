/**

   <title>AGSOutput ... a class to output gsdoc source</title>
   Copyright (C) <copy>2001 Free Software Foundation, Inc.</copy>

   <author name="Richard Frith-Macdonald"></author><richard@brainstorm.co.uk>
   Created: October 2001

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

#include "AGSOutput.h"

@implementation	AGSOutput

- (void) dealloc
{
  DESTROY(identifier);
  DESTROY(identStart);
  DESTROY(spaces);
  DESTROY(spacenl);
  [super dealloc];
}

- (id) init
{
  NSMutableCharacterSet	*m;

  m = [[NSCharacterSet controlCharacterSet] mutableCopy];
  [m addCharactersInString: @" "];
  spacenl = [m copy];
  [m removeCharactersInString: @"\n"];
  spaces = [m copy];
  RELEASE(m);
  identifier = RETAIN([NSCharacterSet characterSetWithCharactersInString:
    @"_0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"]);
  identStart = RETAIN([NSCharacterSet characterSetWithCharactersInString:
    @"_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"]);

  return self;
}

- (BOOL) output: (NSDictionary*)d file: (NSString*)name
{
  NSMutableString	*str = [NSMutableString stringWithCapacity: 10240];
  NSDictionary		*classes;
  NSDictionary		*categories;
  NSDictionary		*protocols;
  NSArray		*authors;
  NSString		*tmp;

  info = d;

  classes = [info objectForKey: @"Classes"];
  categories = [info objectForKey: @"Categories"];
  protocols = [info objectForKey: @"Protocols"];

  [str appendString: @"<?xml version=\"1.0\"?>\n"];
  [str appendString: @"<!DOCTYPE gsdoc PUBLIC "];
  [str appendString: @"\"-//GNUstep//DTD gsdoc 0.6.5//EN\" "];
  [str appendString: @"\"http://www.gnustep.org/gsdoc-0_6_5.xml\">\n"];
  [str appendFormat: @"<gsdoc"];

  tmp = [info objectForKey: @"Base"];
  if (tmp != nil)
    {
      [str appendString: @" base=\""];
      [str appendString: tmp];
    }

  tmp = [info objectForKey: @"Next"];
  if (tmp != nil)
    {
      [str appendString: @" next=\""];
      [str appendString: tmp];
    }

  tmp = [info objectForKey: @"Prev"];
  if (tmp != nil)
    {
      [str appendString: @" prev=\""];
      [str appendString: tmp];
    }

  tmp = [info objectForKey: @"Up"];
  if (tmp != nil)
    {
      [str appendString: @" up=\""];
      [str appendString: tmp];
    }

  [str appendString: @">\n"];
  [str appendString: @"  <head>\n"];

  /*
   * A title is mandatory in the head element ... obtain it
   * from the info dictionary.  Guess at a title if necessary.
   */
  tmp = [info objectForKey: @"title"];
  if (tmp != nil)
    {
      [self reformat: tmp withIndent: 4 to: str];
    }
  else
    {
      [str appendString: @"    <title>"];
      if ([classes count] == 1)
	{
	  [str appendString: [[classes allKeys] lastObject]];
	  [str appendString: @" class documentation"];
	}
      else
	{
	  [str appendString: @"Automatically generated documentation"];
	}
      [str appendString: @"</title>\n"];
    }

  /*
   * The author element is compulsory ... fill in.
   */
  authors = [info objectForKey: @"authors"];
  if (authors == nil)
    {
      tmp = [NSString stringWithFormat: @"Generated by %@", NSUserName()];
      [str appendString: @"    <author name=\""];
      [str appendString: tmp];
      [str appendString: @"\"></author>\n"];
    }
  else
    {
      unsigned	i;

      for (i = 0; i < [authors count]; i++)
	{
	  NSString	*author = [authors objectAtIndex: i];

	  [self reformat: author withIndent: 4 to: str];
	}
    }
  
  /*
   * The version element is optional ... fill in if available.
   */
  tmp = [info objectForKey: @"version"];
  if (tmp != nil)
    {
      [self reformat: tmp withIndent: 4 to: str];
    }
  
  /*
   * The date element is optional ... fill in if available.
   */
  tmp = [info objectForKey: @"date"];
  if (tmp != nil)
    {
      [self reformat: tmp withIndent: 4 to: str];
    }
  
  /*
   * The abstract element is optional ... fill in if available.
   */
  tmp = [info objectForKey: @"abstract"];
  if (tmp != nil)
    {
      [self reformat: tmp withIndent: 4 to: str];
    }
  
  /*
   * The copy element is optional ... fill in if available.
   */
  tmp = [info objectForKey: @"copy"];
  if (tmp != nil)
    {
      [self reformat: tmp withIndent: 4 to: str];
    }
  
  [str appendString: @"  </head>\n"];
  [str appendString: @"  <body>\n"];

  // Output document forward if available.
  tmp = [info objectForKey: @"front"];
  if (tmp != nil)
    {
      [self reformat: tmp withIndent: 4 to: str];
    }

  // Output document main chapter if available
  tmp = [info objectForKey: @"chapter"];
  if (tmp != nil)
    {
      [self reformat: tmp withIndent: 4 to: str];
    }

  if ([classes count] > 0)
    {
      NSArray	*names;
      unsigned	i;

      names = [classes allKeys];
      names = [names sortedArrayUsingSelector: @selector(compare:)];
      for (i = 0; i < [names count]; i++)
	{
	  NSString	*name = [names objectAtIndex: i];
	  NSDictionary	*d = [classes objectForKey: name];

	  [self outputUnit: d to: str];
	}
    }

  if ([categories count] > 0)
    {
      NSArray	*names;
      unsigned	i;

      names = [categories allKeys];
      names = [names sortedArrayUsingSelector: @selector(compare:)];
      for (i = 0; i < [names count]; i++)
	{
	  NSString	*name = [names objectAtIndex: i];
	  NSDictionary	*d = [categories objectForKey: name];

	  [self outputUnit: d to: str];
	}
    }

  if ([protocols count] > 0)
    {
      NSArray	*names;
      unsigned	i;

      names = [protocols allKeys];
      names = [names sortedArrayUsingSelector: @selector(compare:)];
      for (i = 0; i < [names count]; i++)
	{
	  NSString	*name = [names objectAtIndex: i];
	  NSDictionary	*d = [protocols objectForKey: name];

	  [self outputUnit: d to: str];
	}
    }

  // Output document appendix if available.
  tmp = [info objectForKey: @"back"];
  if (tmp != nil)
    {
      [self reformat: tmp withIndent: 4 to: str];
    }

  [str appendString: @"  </body>\n"];
  [str appendString: @"</gsdoc>\n"];

  return [str writeToFile: name atomically: YES];
}

- (void) outputMethod: (NSDictionary*)d to: (NSMutableString*)str
{
  NSArray	*args = [d objectForKey: @"Args"];
  NSArray	*sels = [d objectForKey: @"Sels"];
  NSArray	*types = [d objectForKey: @"Types"];
  NSString	*name = [d objectForKey: @"Name"];
  NSString	*tmp;
  unsigned	i;
  BOOL		isInitialiser = NO;
  NSString	*override = nil;
  NSString	*standards = nil;

  tmp = [d objectForKey: @"Comment"];

  /**
   * Check special markup which should be removed from the text
   * actually placed in the gsdoc method documentation ... the
   * special markup is included in the gsdoc markup differently.
   */ 
  if (tmp != nil)
    {
      NSMutableString	*m = nil;
      NSRange		r;

      do
	{
	  r = [tmp rangeOfString: @"<init>"];
	  if (r.length > 0)
	    {
	      if (m == nil)
		{
		  m = [tmp mutableCopy];
		}
	      [m deleteCharactersInRange: r];
	      tmp = m;
	      isInitialiser = YES;
	    }
	} while (r.length > 0);
      do
	{
	  r = [tmp rangeOfString: @"<override-subclass>"];
	  if (r.length > 0)
	    {
	      if (m == nil)
		{
		  m = [tmp mutableCopy];
		}
	      [m deleteCharactersInRange: r];
	      tmp = m;
	      override = @"subclass";
	    }
	} while (r.length > 0);
      do
	{
	  r = [tmp rangeOfString: @"<override-never>"];
	  if (r.length > 0)
	    {
	      if (m == nil)
		{
		  m = [tmp mutableCopy];
		}
	      [m deleteCharactersInRange: r];
	      tmp = m;
	      override = @"never";
	    }
	} while (r.length > 0);
      r = [tmp rangeOfString: @"<standards>"];
      if (r.length > 0)
	{
	  unsigned  i = r.location;

	  r = NSMakeRange(i, [tmp length] - i);
	  r = [tmp rangeOfString: @"</standards>"
			 options: NSLiteralSearch
			   range: r];
	  if (r.length > 0)
	    {
	      r = NSMakeRange(i, NSMaxRange(r) - i);
	      standards = [tmp substringWithRange: r];
	      if (m == nil)
		{
		  m = [tmp mutableCopy];
		}
	      [m deleteCharactersInRange: r];
	      tmp = m;
	    }
	  else
	    {
	      NSLog(@"unterminated <standards> in comment for %@", name);
	    }
	}
      if (m != nil)
	{
	  RELEASE(m);
	}
    }

  [str appendString: @"        <method type=\""];
  [str appendString: [d objectForKey: @"ReturnType"]];
  if ([name hasPrefix: @"+"] == YES)
    {
      [str appendString: @"\" factory=\"yes"];
    }
  if (isInitialiser == YES)
    {
      [str appendString: @"\" init=\"yes"];
    }
  if (override != nil)
    {
      [str appendString: @"\" override=\""];
      [str appendString: override];
    }
  [str appendString: @"\">\n"];

  for (i = 0; i < [sels count]; i++)
    {
      [str appendString: @"          <sel>"];
      [str appendString: [sels objectAtIndex: i]];
      [str appendString: @"</sel>\n"];
      if (i < [args count])
	{
	  [str appendString: @"          <arg type=\""];
	  [str appendString: [types objectAtIndex: i]];
	  [str appendString: @"\">"];
	  [str appendString: [args objectAtIndex: i]];
	  [str appendString: @"</arg>\n"];
	}
    }

  [str appendString: @"          <desc>\n"];
  tmp = [d objectForKey: @"Comment"];
  if (tmp != nil)
    {
      [self reformat: tmp withIndent: 12 to: str];
    }
  [str appendString: @"          </desc>\n"];
  if (standards != nil)
    {
      [self reformat: standards withIndent: 10 to: str];
    }
  [str appendString: @"        </method>\n"];
}

- (void) outputUnit: (NSDictionary*)d to: (NSMutableString*)str
{
  NSString	*name = [d objectForKey: @"Name"];
  NSString	*type = [d objectForKey: @"Type"];
  NSDictionary	*methods = [d objectForKey: @"Methods"];
  NSArray	*names;
  NSArray	*protocols;
  NSString	*tmp;
  unsigned	i;

  [str appendString: @"    <chapter>\n"];

  [str appendString: @"      <heading>"];
  [str appendString: @"Software documentation for the "];
  [str appendString: name];
  [str appendString: @" "];
  [str appendString: type];
  [str appendString: @"</heading>\n"];

  [str appendString: @"      <"];
  [str appendString: type];
  [str appendString: @" name=\""];
  if ([type isEqual: @"category"] == YES)
    {
      [str appendString: [d objectForKey: @"Category"]];
    }
  else
    {
      [str appendString: name];
    }
  tmp = [d objectForKey: @"BaseClass"];
  if (tmp != nil)
    {
      if ([type isEqual: @"class"] == YES)
	{
	  [str appendString: @"\" super=\""];
	}
      else if ([type isEqual: @"category"] == YES)
	{
	  [str appendString: @"\" class=\""];
	}
      [str appendString: tmp];
    }
  [str appendString: @"\">\n"];

  [str appendString: @"        <declared>"];
  [str appendString: [d objectForKey: @"Declared"]];
  [str appendString: @"</declared>\n"];

  protocols = [d objectForKey: @"Protocols"];
  if ([protocols count] > 0)
    {
      for (i = 0; i < [protocols count]; i++)
	{
	  [str appendString: @"        <conform>"];
	  [str appendString: [protocols objectAtIndex: i]];
	  [str appendString: @"</conform>\n"];
	}
    }

  [str appendString: @"        <desc>\n"];
  tmp = [d objectForKey: @"Comment"];
  if (tmp != nil)
    {
      [self reformat: tmp withIndent: 10 to: str];
    }
  [str appendString: @"        </desc>\n"];
  
  names = [[methods allKeys] sortedArrayUsingSelector: @selector(compare:)];
  for (i = 0; i < [names count]; i++)
    {
      NSString	*mName = [names objectAtIndex: i];

      [self outputMethod: [methods objectForKey: mName] to: str];
    }

  [str appendString: @"      </"];
  [str appendString: type];
  [str appendString: @">\n"];
  [str appendString: @"    </chapter>\n"];
}

- (void) reformat: (NSString*)str
       withIndent: (unsigned)ind
	       to: (NSMutableString*)buf
{
  CREATE_AUTORELEASE_POOL(arp);
  unsigned	l = [str length];
  NSRange	r = NSMakeRange(0, l);
  unsigned	i = 0;
  NSArray	*a;

  /*
   * Split out <example>...</example> sequences and output them literally.
   * All other text has reformatting applied as necessary.
   */
  r = [str rangeOfString: @"<example"];
  while (r.length > 0)
    {
      NSString	*tmp;

      if (r.location > i)
	{
	  /*
	   * There was some text before the example - call this method
	   * recursively to format and output it.
	   */
	  tmp = [str substringWithRange: NSMakeRange(i, r.location - i)];
	  [self reformat: str withIndent: ind to: buf];
	  i = r.location;
	}
      /*
       * Now find the end of the exmple, and output the whole example
       * literally as it appeared in the comment.
       */
      r = [str rangeOfString: @"</example>"
		     options: NSLiteralSearch
		       range: NSMakeRange(i, l - i)];
      if (r.length == 0)
	{
	  NSLog(@"unterminated <example>");
	  return;
	}
      tmp = [str substringWithRange: NSMakeRange(i, NSMaxRange(r) - i)];
      [buf appendString: tmp];
      [buf appendString: @"\n"];
      /*
       * Set up the start location and search for another example so
       * we will loop round again if necessary.
       */
      i = NSMaxRange(r);
      r = [str rangeOfString: @"<example"
		     options: NSLiteralSearch
		       range: NSMakeRange(i, l - i)];
    }

  /*
   * If part of the string has already been consumed, just use
   * the remaining substring.
   */
  if (i > 0)
    {
      str = [str substringWithRange: NSMakeRange(i, l - i)];
    }

  /*
   * Split the string up into parts separated by newlines.
   */
  a = [self split: str];
  for (i = 0; i < [a count]; i++)
    {
      int	j;

      str = [a objectAtIndex: i];

      if ([str hasPrefix: @"</"] == YES)
	{
	  if (ind > 2)
	    {
	      /*
	       * decrement indentation after the end of an element.
	       */
	      ind -= 2;
	    }
	  for (j = 0; j < ind; j++)
	    {
	      [buf appendString: @" "];
	    }
	  [buf appendString: str];
	  [buf appendString: @"\n"];
	}
      else if ([str hasPrefix: @"<"] == YES && [str hasSuffix: @"/>"] == NO)
	{
	  unsigned	size = ind + [str length];
	  unsigned	nest = 0;
	  BOOL		addSpace;

	  for (j = 0; j < ind; j++)
	    {
	      [buf appendString: @" "];
	    }
	  [buf appendString: str];
	  addSpace = ([str hasPrefix: @"<"] == YES) ? NO : YES;
	  for (j = i + 1; size <= 70 && j < [a count]; j++)
	    {
	      NSString	*t = [a objectAtIndex: j];

	      size += [t length];
	      if ([t hasPrefix: @"</"] == YES)
		{
		  if (nest == 0)
		    {
		      break;	// End of element reached.
		    }
		  nest--;
		}
	      else if ([t hasPrefix: @"<"] == YES)
		{
		  addSpace = NO;
		  if ([t hasSuffix: @"/>"] == NO)
		    {
		      nest++;
		    }
		}
	      else
		{
		  if (addSpace == YES)
		    {
		      size++;
		    }
		  addSpace = YES;
		}
	    }
	  if (size > 70)
	    {
	      ind += 2;
	    }
	  else
	    {
	      addSpace = ([str hasPrefix: @"<"] == YES) ? NO : YES;
	      for (j = i + 1; j < [a count]; j++)
		{
		  NSString	*t = [a objectAtIndex: j];

		  if ([t hasPrefix: @"</"] == YES)
		    {
		      [buf appendString: t];
		      if (nest == 0)
			{
			  break;	// End of element reached.
			}
		      nest--;
		    }
		  else if ([t hasPrefix: @"<"] == YES)
		    {
		      [buf appendString: t];
		      addSpace = NO;
		      if ([t hasSuffix: @"/>"] == NO)
			{
			  nest++;
			}
		    }
		  else
		    {
		      if (addSpace == YES)
			{
			  [buf appendString: @" "];
			}
		      [buf appendString: t];
		      addSpace = YES;
		    }
		}
	      i = j;
	    }
	  [buf appendString: @"\n"];
	}
      else
	{
	  unsigned	size = ind + [str length];
	  unsigned	nest = 0;
	  unsigned	lastOk = i;
	  BOOL		addSpace;

	  for (j = 0; j < ind; j++)
	    {
	      [buf appendString: @" "];
	    }
	  [buf appendString: str];
	  addSpace = ([str hasPrefix: @"<"] == YES) ? NO : YES;
	  for (j = i + 1; size <= 70 && j < [a count]; j++)
	    {
	      NSString	*t = [a objectAtIndex: j];

	      size += [t length];
	      if ([t hasPrefix: @"</"] == YES)
		{
		  if (nest == 0)
		    {
		      break;	// End of element reached.
		    }
		  nest--;
		}
	      else if ([t hasPrefix: @"<"] == YES)
		{
		  addSpace = NO;
		  if ([t hasSuffix: @"/>"] == NO)
		    {
		      nest++;
		    }
		}
	      else
		{
		  if (addSpace == YES)
		    {
		      size++;
		    }
		  addSpace = YES;
		}
	      if (nest == 0 && size <= 70)
		{
		  lastOk = j;
		}
	    }
	  if (lastOk > i)
	    {
	      addSpace = ([str hasPrefix: @"<"] == YES) ? NO : YES;
	      for (j = i + 1; j <= lastOk; j++)
		{
		  NSString	*t = [a objectAtIndex: j];

		  if ([t hasPrefix: @"</"] == YES)
		    {
		      [buf appendString: t];
		    }
		  else if ([t hasPrefix: @"<"] == YES)
		    {
		      [buf appendString: t];
		      addSpace = NO;
		    }
		  else
		    {
		      if (addSpace == YES)
			{
			  [buf appendString: @" "];
			}
		      [buf appendString: t];
		      addSpace = YES;
		    }
		}
	      i = lastOk;
	    }
	  [buf appendString: @"\n"];
	}
    }
  RELEASE(arp);
}

- (NSArray*) split: (NSString*)str
{
  NSMutableArray	*a = [NSMutableArray arrayWithCapacity: 128];
  unsigned		l = [str length];
  NSMutableData		*data;
  unichar		*ptr;
  unichar		*end;
  unichar		*buf;
  
  data = [[NSMutableData alloc] initWithLength: l * sizeof(unichar)];
  ptr = buf = [data mutableBytes];
  [str getCharacters: buf];
  end = buf + l;
  while (ptr < end)
    {
      if ([spacenl characterIsMember: *ptr] == YES)
	{
	  if (ptr != buf)
	    {
	      NSString	*tmp;

	      tmp = [NSString stringWithCharacters: buf length: ptr - buf];
	      [a addObject: tmp];
	      buf = ptr;
	    }
	  ptr++;
	  buf++;
	}
      else if (*ptr == '<')
	{
	  BOOL		elideSpace = YES;
	  unichar	*optr = ptr;

	  if (ptr != buf)
	    {
	      NSString	*tmp;

	      tmp = [NSString stringWithCharacters: buf length: ptr - buf];
	      [a addObject: tmp];
	      buf = ptr;
	    }
	  while (ptr < end && *ptr != '>')
	    {
	      /*
	       * We convert whitespace sequences inside element markup
	       * to single space characters unless protected by quotes.
	       */
	      if ([spacenl characterIsMember: *ptr] == YES)
		{
		  if (elideSpace == NO)
		    {
		      *optr++ = ' ';
		      elideSpace = YES;
		    }
		  ptr++;
		}
	      else if (*ptr == '"')
		{
		  while (ptr < end && *ptr != '"')
		    {
		      *optr++ = *ptr++;
		    }
		  if (ptr < end)
		    {
		      *optr++ = *ptr++;
		    }
		  elideSpace = NO;
		}
	      else
		{
		  *optr++ = *ptr++;
		  elideSpace = NO;
		}
	    }
	  if (*ptr == '>')
	    {
	      *optr++ = *ptr++;
	    }
	  if (optr != buf)
	    {
	      NSString	*tmp;

	      tmp = [NSString stringWithCharacters: buf length: ptr - buf];
	      [a addObject: tmp];
	    }
	  buf = ptr;
	}
      else
	{
	  ptr++;
	}
    }
  if (ptr != buf)
    {
      NSString	*tmp;

      tmp = [NSString stringWithCharacters: buf length: ptr - buf];
      [a addObject: tmp];
    }
  return a;
}

@end


