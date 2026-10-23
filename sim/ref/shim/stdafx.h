//
// stdafx.h
//
// What UKNCBTL's emubase takes from Windows and Qt, for a headless build.
//
#pragma once
#include <string.h>
#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdarg.h>
typedef char TCHAR;
typedef char * LPTSTR;
typedef const char * LPCTSTR;
#define _T(x) x
#define _tfopen fopen
#define _tcslen strlen
#define _tcscpy strcpy
#define _sntprintf snprintf
inline void _tcscpy_s(char* d, size_t n, const char* s) { snprintf(d, n, "%s", s); }
inline void _tcsncpy_s(char* d, size_t n, const char* s, size_t c) { size_t l = strnlen(s, c); if (l >= n) l = n - 1; memcpy(d, s, l); d[l] = 0; }
#define MAKELONG(a, b) ((uint32_t)(((uint16_t)(a)) | ((uint32_t)((uint16_t)(b))) << 16))
#define MAKEWORD(a, b) ((uint16_t)(((uint8_t)(a)) | ((uint16_t)((uint8_t)(b))) << 8))
#define CALLBACK
typedef void *HANDLE;
#define ASSERT(f) ((void)0)
#define VERIFY(f) ((void)(f))
inline void DebugLog(const char*) {}
inline void DebugLogFormat(const char*, ...) {}
inline void DebugPrint(const char*) {}
inline void DebugPrintFormat(const char*, ...) {}
#include <strings.h>
#define _tcsrchr strrchr
#define _tcsicmp strcasecmp
#define _tcscmp strcmp
#define _tcstod strtod
#define _TRUNCATE ((size_t)-1)
const LPCTSTR REGISTER_NAME[] = { "R0", "R1", "R2", "R3", "R4", "R5", "SP", "PC" };
