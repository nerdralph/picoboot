/*
 * avrdude - A Downloader/Uploader for AVR device programmers
 * Copyright (C) 2014 Ralph Doncaster
 * Copyright (C) 2009 Lars Immisch
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

/* $Id: picoboot.h 1107 2012-11-20 14:03:50Z joerg_wunsch $ */

#ifndef picoboot_h__
#define picoboot_h__

extern const char picoboot_desc[];
void picoboot_initpgm (PROGRAMMER * pgm);

#endif


