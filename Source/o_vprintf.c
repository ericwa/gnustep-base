/* Implementation of o_vprintf for GNUstep Base Library
   
   Reworked by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Date: July 1994
   
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
   Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
   */ 

/* Copyright (C) 1991, 1992, 1993, 1994 Free Software Foundation, Inc.
This file is part of the GNU C Library.

The GNU C Library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public License as
published by the Free Software Foundation; either version 2 of the
License, or (at your option) any later version.

The GNU C Library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.

You should have received a copy of the GNU Library General Public
License along with the GNU C Library; see the file COPYING.LIB.  If
not, write to the Free Software Foundation, Inc., 675 Mass Ave,
Cambridge, MA 02139, USA.  */

/* Reworked from glibc by Andrew McCallum:
   Use function pointer argument to put next character.

   This is a solution for MemoryStream.  It's not ideal.
   It is a temporary fix.
   On GNU systems we could just use GNU stdio stream functions, but
   on non-GNU systems, using this is easier than installing glibc. */

/* #include <ansidecl.h> */
/* #include <localeinfo.h> */
#include <ctype.h>
#include <errno.h>
#include <float.h>
#include <limits.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* #include <printf.h> */
#include <assert.h>
#include "_itoa.h"


/* If it's an unbuffered stream that we provided
   temporary buffering for, remove that buffering.  */
#define	RETURN(x)							      \
  do									      \
    {									      \
      done = (x);							      \
      goto do_return;							      \
    } while (0)

#define	outchar(x)							      \
  do									      \
    {									      \
      char outc = (x);				 			      \
      if ((*write_func)(stream, &outc, 1) == EOF)			      \
	RETURN(-1);							      \
      else								      \
	++done;								      \
    } while (0)

/* Cast the next arg, of type ARGTYPE, into CASTTYPE, and put it in VAR.  */
#define	castarg(var, argtype, casttype) \
  var = (casttype) va_arg(args, argtype)
/* Get the next arg, of type TYPE, and put it in VAR.  */
#define	nextarg(var, type)	castarg(var, type, type)

#ifdef	__GNUC__
#define	HAVE_LONGLONG
#define	LONGLONG	long long
#else
#define	LONGLONG	long
#endif


int
o_vprintf(void *stream,
		int (*write_func)(void*, char*, int len), 
		const char *format, va_list args)
{
  /* Pointer into the format string.  */
  register const char *f;

  /* Number of characters written.  */
  register size_t done = 0;

  /* Reset multibyte characters to their initial state.  */
  (void) mblen((char *) NULL, 0);

  f = format;
  while (*f != '\0')
    {
      /* Type modifiers.  */
      char is_short, is_long, is_long_double;
#ifdef	HAVE_LONGLONG
      /* We use the `L' modifier for `long long int'.  */
#define	is_longlong	is_long_double
#else
#define	is_longlong	0
#endif
      /* Format spec modifiers.  */
      char space, showsign, left, alt;

      /* Padding character: ' ' or '0'.  */
      char pad;
      /* Width of a field.  */
      register int width;
      /* Precision of a field.  */
      int prec;

      /* Decimal integer is negative.  */
      char is_neg;

      /* Current character of the format.  */
      char fc;

      /* Base of a number to be written.  */
      int base;
      /* Integral values to be written.  */
      unsigned LONGLONG int num;
      LONGLONG int signed_num;

      /* String to be written.  */
      const char *str;
      char unknown_error[256];	/* Buffer sometimes used by %m.  */

      if (!isascii(*f))
	{
	  /* Non-ASCII, may be a multibyte.  */
	  int len = mblen(f, strlen(f));
	  if (len > 0)
	    {
	      while (len-- > 0)
		outchar(*f++);
	      continue;
	    }
	}

      if (*f != '%')
	{
	  /* This isn't a format spec, so write
	     everything out until the next one.  */
	  const char *next = strchr(f + 1, '%');
	  if (next == NULL)
	    next = strchr(f + 1, '\0');
	  if (next - f > 20)
	    {
	      size_t written = (*write_func)(stream, (void*)f, next - f);
	      done += written;
	      if (written != next - f)
		break;
	      f += written;
	    }
	  else
	    while (f < next)
	      outchar(*f++);
	  continue;
	}

      ++f;

      /* Check for "%%".  Note that although the ANSI standard lists
	 '%' as a conversion specifier, it says "The complete format
	 specification shall be `%%'," so we can avoid all the width
	 and precision processing.  */
      if (*f == '%')
	{
	  ++f;
	  outchar('%');
	  continue;
	}

      /* Check for spec modifiers.  */
      space = showsign = left = alt = 0;
      pad = ' ';
      while (*f == ' ' || *f == '+' || *f == '-' || *f == '#' || *f == '0')
	switch (*f++)
	  {
	  case ' ':
	    /* Output a space in place of a sign, when there is no sign.  */
	    space = 1;
	    break;
	  case '+':
	    /* Always output + or - for numbers.  */
	    showsign = 1;
	    break;
	  case '-':
	    /* Left-justify things.  */
	    left = 1;
	    break;
	  case '#':
	    /* Use the "alternate form":
	       Hex has 0x or 0X, FP always has a decimal point.  */
	    alt = 1;
	    break;
	  case '0':
	    /* Pad with 0s.  */
	    pad = '0';
	    break;
	  }
      if (left)
	pad = ' ';

      /* Get the field width.  */
      width = 0;
      if (*f == '*')
	{
	  /* The field width is given in an argument.
	     A negative field width indicates left justification.  */
	  nextarg(width, int);
	  if (width < 0)
	    {
	      width = - width;
	      left = 1;
	    }
	  ++f;
	}
      else
	while (isdigit(*f))
	  {
	    width *= 10;
	    width += *f++ - '0';
	  }

      /* Get the precision.  */
      /* -1 means none given; 0 means explicit 0.  */
      prec = -1;
      if (*f == '.')
	{
	  ++f;
	  if (*f == '*')
	    {
	      /* The precision is given in an argument.  */
	      nextarg(prec, int);
	      /* Avoid idiocy.  */
	      if (prec < 0)
		prec = -1;
	      ++f;
	    }
	  else if (isdigit(*f))
	    {
	      prec = 0;
	      while (*f != '\0' && isdigit(*f))
		{
		  prec *= 10;
		  prec += *f++ - '0';
		}
	    }
	}

      /* Check for type modifiers.  */
      is_short = is_long = is_long_double = 0;
      while (*f == 'h' || *f == 'l' || *f == 'L')
	switch (*f++)
	  {
	  case 'h':
	    /* int's are short int's.  */
	    is_short = 1;
	    break;
	  case 'l':
#ifdef	HAVE_LONGLONG
	    if (is_long)
	      /* A double `l' is equivalent to an `L'.  */
	      is_longlong = 1;
	    else
#endif
	      /* int's are long int's.  */
	      is_long = 1;
	    break;
	  case 'L':
	    /* double's are long double's, and int's are long long int's.  */
	    is_long_double = 1;
	    break;

	  case 'Z':
	    /* int's are size_t's.  */
#ifdef	HAVE_LONGLONG
	    assert (sizeof(size_t) <= sizeof(unsigned long long int));
	    is_longlong = sizeof(size_t) > sizeof(unsigned long int);
#endif
	    is_long = sizeof(size_t) > sizeof(unsigned int);
	    break;
	  }

      /* Format specification.  */
      fc = *f++;
      if (1)
	switch (fc)
	  {
	  case 'i':
	  case 'd':
	    /* Decimal integer.  */
	    base = 10;
	    if (is_longlong)
	      nextarg(signed_num, LONGLONG int);
	    else if (is_long)
	      nextarg(signed_num, long int);
	    else if (!is_short)
	      castarg(signed_num, int, long int);
	    else
	      castarg(signed_num, int, short int);

	    is_neg = signed_num < 0;
	    num = is_neg ? (- signed_num) : signed_num;
	    goto number;

	  case 'u':
	    /* Decimal unsigned integer.  */
	    base = 10;
	    goto unsigned_number;

	  case 'o':
	    /* Octal unsigned integer.  */
	    base = 8;
	    goto unsigned_number;

	  case 'X':
	    /* Hexadecimal unsigned integer.  */
	  case 'x':
	    /* Hex with lower-case digits.  */

	    base = 16;

	  unsigned_number:
	    /* Unsigned number of base BASE.  */

	    if (is_longlong)
	      castarg(num, LONGLONG int, unsigned LONGLONG int);
	    else if (is_long)
	      castarg(num, long int, unsigned long int);
	    else if (!is_short)
	      castarg(num, int, unsigned int);
	    else
	      castarg(num, int, unsigned short int);

	    /* ANSI only specifies the `+' and
	       ` ' flags for signed conversions.  */
	    is_neg = showsign = space = 0;

	  number:
	    /* Number of base BASE.  */
	    {
	      char work[BUFSIZ];
	      char *const workend = &work[sizeof(work) - 1];
	      register char *w;

	      /* Supply a default precision if none was given.  */
	      if (prec == -1)
		prec = 1;

	      /* Put the number in WORK.  */
	      w = _itoa (num, workend + 1, base, fc == 'X') - 1;
	      width -= workend - w;
	      prec -= workend - w;

	      if (alt && base == 8 && prec <= 0)
		{
		  *w-- = '0';
		  --width;
		}

	      if (prec > 0)
		{
		  width -= prec;
		  while (prec-- > 0)
		    *w-- = '0';
		}

	      if (alt && base == 16)
		width -= 2;

	      if (is_neg || showsign || space)
		--width;

	      if (!left && pad == ' ')
		while (width-- > 0)
		  outchar(' ');

	      if (is_neg)
		outchar('-');
	      else if (showsign)
		outchar('+');
	      else if (space)
		outchar(' ');

	      if (alt && base == 16)
		{
		  outchar ('0');
		  outchar (fc);
		}

	      if (!left && pad == '0')
		while (width-- > 0)
		  outchar('0');

	      /* Write the number.  */
	      while (++w <= workend)
		outchar(*w);

	      if (left)
		while (width-- > 0)
		  outchar(' ');
	    }
	    break;

	  case 'e':
	  case 'E':
	  case 'f':
	  case 'g':
	  case 'G':
	    {
	      /* Floating-point number.  */
	      extern printf_function __printf_fp;
	      function = __printf_fp;
	      goto use_function;
	    }

	  case 'c':
	    /* Character.  */
	    nextarg(num, int);
	    if (!left)
	      while (--width > 0)
		outchar(' ');
	    outchar((unsigned char) num);
	    if (left)
	      while (--width > 0)
		outchar(' ');
	    break;

	  case 's':
	    {
	      static CONST char null[] = "(null)";
	      size_t len;

	      nextarg(str, CONST char *);

	    string:

	      if (str == NULL)
		/* Write "(null)" if there's space.  */
		if (prec == -1 || prec >= (int) sizeof(null) - 1)
		  {
		    str = null;
		    len = sizeof(null) - 1;
		  }
		else
		  {
		    str = "";
		    len = 0;
		  }
	      else
		len = strlen(str);

	      if (prec != -1 && (size_t) prec < len)
		len = prec;
	      width -= len;

	      if (!left)
		while (width-- > 0)
		  outchar(' ');
	      if (len < 20)
		while (len-- > 0)
		  outchar(*str++);
	      else
		if ((*write_func)(stream, str, len) != len)
		  RETURN(-1);
		else
		  done += len;
	      if (left)
		while (width-- > 0)
		  outchar(' ');
	    }
	    break;

	  case 'p':
	    /* Generic pointer.  */
	    {
	      CONST PTR ptr;
	      nextarg(ptr, const void*);
	      if (ptr != NULL)
		{
		  /* If the pointer is not NULL, write it as a %#x spec.  */
		  base = 16;
		  fc = 'x';
		  alt = 1;
		  num = (unsigned LONGLONG int) (unsigned long int) ptr;
		  is_neg = 0;
		  goto number;
		}
	      else
		{
		  /* Write "(nil)" for a nil pointer.  */
		  static const char nil[] = "(nil)";
		  register const char *p;

		  width -= sizeof (nil) - 1;
		  if (!left)
		    while (width-- > 0)
		      outchar (' ');
		  for (p = nil; *p != '\0'; ++p)
		    outchar (*p);
		  if (left)
		    while (width-- > 0)
		      outchar (' ');
		}
	    }
	    break;

	  case 'n':
	    /* Answer the count of characters written.  */
	    if (is_longlong)
	      {
		LONGLONG int *p;
		nextarg(p, LONGLONG int *);
		*p = done;
	      }
	    else if (is_long)
	      {
		long int *p;
		nextarg(p, long int *);
		*p = done;
	      }
	    else if (!is_short)
	      {
		int *p;
		nextarg(p, int *);
		*p = done;
	      }
	    else
	      {
		short int *p;
		nextarg(p, short int *);
		*p = done;
	      }
	    break;

	  case 'm':
#ifndef HAVE_GNU_LD
#define _sys_errlist sys_errlist
#define _sys_nerr sys_nerr
#endif

	    if (errno < 0 || errno > _sys_nerr)
	      {
		sprintf (unknown_error, "Unknown error %d", errno);
		str = unknown_error;
	      }
	    else
	      str = _sys_errlist[errno];
	    goto string;

	  default:
	    /* Unrecognized format specifier.  */
	    sprintf (unknown_error, "Unknown format specifier %c", fc);
	    str = unknown_error;
	    goto string;
	  }
    }

 do_return:;
  return done;
}

