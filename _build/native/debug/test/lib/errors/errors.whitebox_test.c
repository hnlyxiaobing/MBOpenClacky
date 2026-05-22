#ifdef __cplusplus
extern "C" {
#endif

#include "moonbit.h"

#ifdef _MSC_VER
#define _Noreturn __declspec(noreturn)
#endif

#if defined(__clang__)
#pragma clang diagnostic ignored "-Wshift-op-parentheses"
#pragma clang diagnostic ignored "-Wtautological-compare"
#endif

MOONBIT_EXPORT _Noreturn void moonbit_panic(void);
MOONBIT_EXPORT void *moonbit_malloc_array(enum moonbit_block_kind kind,
                                          int elem_size_shift, int32_t len);
MOONBIT_EXPORT int moonbit_val_array_equal(const void *lhs, const void *rhs);
MOONBIT_EXPORT moonbit_string_t moonbit_add_string(moonbit_string_t s1,
                                                   moonbit_string_t s2);
MOONBIT_EXPORT void moonbit_unsafe_bytes_blit(moonbit_bytes_t dst,
                                              int32_t dst_start,
                                              moonbit_bytes_t src,
                                              int32_t src_offset, int32_t len);
MOONBIT_EXPORT moonbit_string_t moonbit_unsafe_bytes_sub_string(
    moonbit_bytes_t bytes, int32_t start, int32_t len);
MOONBIT_EXPORT void moonbit_println(moonbit_string_t str);
MOONBIT_EXPORT moonbit_bytes_t *moonbit_get_cli_args(void);
MOONBIT_EXPORT void moonbit_runtime_init(int argc, char **argv);
MOONBIT_EXPORT void moonbit_drop_object(void *);

#define Moonbit_make_regular_object_header(ptr_field_offset, ptr_field_count,  \
                                           tag)                                \
  (((uint32_t)moonbit_BLOCK_KIND_REGULAR << 30) |                              \
   (((uint32_t)(ptr_field_offset) & (((uint32_t)1 << 11) - 1)) << 19) |        \
   (((uint32_t)(ptr_field_count) & (((uint32_t)1 << 11) - 1)) << 8) |          \
   ((tag) & 0xFF))

// header manipulation macros
#define Moonbit_object_ptr_field_offset(obj)                                   \
  ((Moonbit_object_header(obj)->meta >> 19) & (((uint32_t)1 << 11) - 1))

#define Moonbit_object_ptr_field_count(obj)                                    \
  ((Moonbit_object_header(obj)->meta >> 8) & (((uint32_t)1 << 11) - 1))

#if !defined(_WIN64) && !defined(_WIN32)
void *malloc(size_t size);
void free(void *ptr);
#define libc_malloc malloc
#define libc_free free
#endif

// several important runtime functions are inlined
static void *moonbit_malloc_inlined(size_t size) {
  struct moonbit_object *ptr = (struct moonbit_object *)libc_malloc(
      sizeof(struct moonbit_object) + size);
  ptr->rc = 1;
  return ptr + 1;
}

#define moonbit_malloc(obj) moonbit_malloc_inlined(obj)
#define moonbit_free(obj) libc_free(Moonbit_object_header(obj))

static void moonbit_incref_inlined(void *ptr) {
  struct moonbit_object *header = Moonbit_object_header(ptr);
  int32_t const count = header->rc;
  if (count > 0) {
    header->rc = count + 1;
  }
}

#define moonbit_incref moonbit_incref_inlined

static void moonbit_decref_inlined(void *ptr) {
  struct moonbit_object *header = Moonbit_object_header(ptr);
  int32_t const count = header->rc;
  if (count > 1) {
    header->rc = count - 1;
  } else if (count == 1) {
    moonbit_drop_object(ptr);
  }
}

#define moonbit_decref moonbit_decref_inlined

#define moonbit_unsafe_make_string moonbit_make_string

// detect whether compiler builtins exist for advanced bitwise operations
#ifdef __has_builtin

#if __has_builtin(__builtin_clz)
#define HAS_BUILTIN_CLZ
#endif

#if __has_builtin(__builtin_ctz)
#define HAS_BUILTIN_CTZ
#endif

#if __has_builtin(__builtin_popcount)
#define HAS_BUILTIN_POPCNT
#endif

#if __has_builtin(__builtin_sqrt)
#define HAS_BUILTIN_SQRT
#endif

#if __has_builtin(__builtin_sqrtf)
#define HAS_BUILTIN_SQRTF
#endif

#if __has_builtin(__builtin_fabs)
#define HAS_BUILTIN_FABS
#endif

#if __has_builtin(__builtin_fabsf)
#define HAS_BUILTIN_FABSF
#endif

#endif

// if there is no builtin operators, use software implementation
#ifdef HAS_BUILTIN_CLZ
static inline int32_t moonbit_clz32(int32_t x) {
  return x == 0 ? 32 : __builtin_clz(x);
}

static inline int32_t moonbit_clz64(int64_t x) {
  return x == 0 ? 64 : __builtin_clzll(x);
}

#undef HAS_BUILTIN_CLZ
#else
// table for [clz] value of 4bit integer.
static const uint8_t moonbit_clz4[] = {4, 3, 2, 2, 1, 1, 1, 1,
                                       0, 0, 0, 0, 0, 0, 0, 0};

int32_t moonbit_clz32(uint32_t x) {
  /* The ideas is to:

     1. narrow down the 4bit block where the most signficant "1" bit lies,
        using binary search
     2. find the number of leading zeros in that 4bit block via table lookup

     Different time/space tradeoff can be made here by enlarging the table
     and do less binary search.
     One benefit of the 4bit lookup table is that it can fit into a single cache
     line.
  */
  int32_t result = 0;
  if (x > 0xffff) {
    x >>= 16;
  } else {
    result += 16;
  }
  if (x > 0xff) {
    x >>= 8;
  } else {
    result += 8;
  }
  if (x > 0xf) {
    x >>= 4;
  } else {
    result += 4;
  }
  return result + moonbit_clz4[x];
}

int32_t moonbit_clz64(uint64_t x) {
  int32_t result = 0;
  if (x > 0xffffffff) {
    x >>= 32;
  } else {
    result += 32;
  }
  return result + moonbit_clz32((uint32_t)x);
}
#endif

#ifdef HAS_BUILTIN_CTZ
static inline int32_t moonbit_ctz32(int32_t x) {
  return x == 0 ? 32 : __builtin_ctz(x);
}

static inline int32_t moonbit_ctz64(int64_t x) {
  return x == 0 ? 64 : __builtin_ctzll(x);
}

#undef HAS_BUILTIN_CTZ
#else
int32_t moonbit_ctz32(int32_t x) {
  /* The algorithm comes from:

       Leiserson, Charles E. et al. “Using de Bruijn Sequences to Index a 1 in a
     Computer Word.” (1998).

     The ideas is:

     1. leave only the least significant "1" bit in the input,
        set all other bits to "0". This is achieved via [x & -x]
     2. now we have [x * n == n << ctz(x)], if [n] is a de bruijn sequence
        (every 5bit pattern occurn exactly once when you cycle through the bit
     string), we can find [ctz(x)] from the most significant 5 bits of [x * n]
 */
  static const uint32_t de_bruijn_32 = 0x077CB531;
  static const uint8_t index32[] = {0,  1,  28, 2,  29, 14, 24, 3,  30, 22, 20,
                                    15, 25, 17, 4,  8,  31, 27, 13, 23, 21, 19,
                                    16, 7,  26, 12, 18, 6,  11, 5,  10, 9};
  return (x == 0) * 32 + index32[(de_bruijn_32 * (x & -x)) >> 27];
}

int32_t moonbit_ctz64(int64_t x) {
  static const uint64_t de_bruijn_64 = 0x0218A392CD3D5DBF;
  static const uint8_t index64[] = {
      0,  1,  2,  7,  3,  13, 8,  19, 4,  25, 14, 28, 9,  34, 20, 40,
      5,  17, 26, 38, 15, 46, 29, 48, 10, 31, 35, 54, 21, 50, 41, 57,
      63, 6,  12, 18, 24, 27, 33, 39, 16, 37, 45, 47, 30, 53, 49, 56,
      62, 11, 23, 32, 36, 44, 52, 55, 61, 22, 43, 51, 60, 42, 59, 58};
  return (x == 0) * 64 + index64[(de_bruijn_64 * (x & -x)) >> 58];
}
#endif

#ifdef HAS_BUILTIN_POPCNT

#define moonbit_popcnt32 __builtin_popcount
#define moonbit_popcnt64 __builtin_popcountll
#undef HAS_BUILTIN_POPCNT

#else
int32_t moonbit_popcnt32(uint32_t x) {
  /* The classic SIMD Within A Register algorithm.
     ref: [https://nimrod.blog/posts/algorithms-behind-popcount/]
 */
  x = x - ((x >> 1) & 0x55555555);
  x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
  x = (x + (x >> 4)) & 0x0F0F0F0F;
  return (x * 0x01010101) >> 24;
}

int32_t moonbit_popcnt64(uint64_t x) {
  x = x - ((x >> 1) & 0x5555555555555555);
  x = (x & 0x3333333333333333) + ((x >> 2) & 0x3333333333333333);
  x = (x + (x >> 4)) & 0x0F0F0F0F0F0F0F0F;
  return (x * 0x0101010101010101) >> 56;
}
#endif

/* The following sqrt implementation comes from
   [musl](https://git.musl-libc.org/cgit/musl),
   with some helpers inlined to make it zero dependency.
 */
#ifdef MOONBIT_NATIVE_NO_SYS_HEADER
const uint16_t __rsqrt_tab[128] = {
    0xb451, 0xb2f0, 0xb196, 0xb044, 0xaef9, 0xadb6, 0xac79, 0xab43, 0xaa14,
    0xa8eb, 0xa7c8, 0xa6aa, 0xa592, 0xa480, 0xa373, 0xa26b, 0xa168, 0xa06a,
    0x9f70, 0x9e7b, 0x9d8a, 0x9c9d, 0x9bb5, 0x9ad1, 0x99f0, 0x9913, 0x983a,
    0x9765, 0x9693, 0x95c4, 0x94f8, 0x9430, 0x936b, 0x92a9, 0x91ea, 0x912e,
    0x9075, 0x8fbe, 0x8f0a, 0x8e59, 0x8daa, 0x8cfe, 0x8c54, 0x8bac, 0x8b07,
    0x8a64, 0x89c4, 0x8925, 0x8889, 0x87ee, 0x8756, 0x86c0, 0x862b, 0x8599,
    0x8508, 0x8479, 0x83ec, 0x8361, 0x82d8, 0x8250, 0x81c9, 0x8145, 0x80c2,
    0x8040, 0xff02, 0xfd0e, 0xfb25, 0xf947, 0xf773, 0xf5aa, 0xf3ea, 0xf234,
    0xf087, 0xeee3, 0xed47, 0xebb3, 0xea27, 0xe8a3, 0xe727, 0xe5b2, 0xe443,
    0xe2dc, 0xe17a, 0xe020, 0xdecb, 0xdd7d, 0xdc34, 0xdaf1, 0xd9b3, 0xd87b,
    0xd748, 0xd61a, 0xd4f1, 0xd3cd, 0xd2ad, 0xd192, 0xd07b, 0xcf69, 0xce5b,
    0xcd51, 0xcc4a, 0xcb48, 0xca4a, 0xc94f, 0xc858, 0xc764, 0xc674, 0xc587,
    0xc49d, 0xc3b7, 0xc2d4, 0xc1f4, 0xc116, 0xc03c, 0xbf65, 0xbe90, 0xbdbe,
    0xbcef, 0xbc23, 0xbb59, 0xba91, 0xb9cc, 0xb90a, 0xb84a, 0xb78c, 0xb6d0,
    0xb617, 0xb560,
};

/* returns a*b*2^-32 - e, with error 0 <= e < 1.  */
static inline uint32_t mul32(uint32_t a, uint32_t b) {
  return (uint64_t)a * b >> 32;
}
#endif

#ifdef MOONBIT_NATIVE_NO_SYS_HEADER
float sqrtf(float x) {
  uint32_t ix, m, m1, m0, even, ey;

  ix = *(uint32_t *)&x;
  if (ix - 0x00800000 >= 0x7f800000 - 0x00800000) {
    /* x < 0x1p-126 or inf or nan.  */
    if (ix * 2 == 0)
      return x;
    if (ix == 0x7f800000)
      return x;
    if (ix > 0x7f800000)
      return (x - x) / (x - x);
    /* x is subnormal, normalize it.  */
    x *= 0x1p23f;
    ix = *(uint32_t *)&x;
    ix -= 23 << 23;
  }

  /* x = 4^e m; with int e and m in [1, 4).  */
  even = ix & 0x00800000;
  m1 = (ix << 8) | 0x80000000;
  m0 = (ix << 7) & 0x7fffffff;
  m = even ? m0 : m1;

  /* 2^e is the exponent part of the return value.  */
  ey = ix >> 1;
  ey += 0x3f800000 >> 1;
  ey &= 0x7f800000;

  /* compute r ~ 1/sqrt(m), s ~ sqrt(m) with 2 goldschmidt iterations.  */
  static const uint32_t three = 0xc0000000;
  uint32_t r, s, d, u, i;
  i = (ix >> 17) % 128;
  r = (uint32_t)__rsqrt_tab[i] << 16;
  /* |r*sqrt(m) - 1| < 0x1p-8 */
  s = mul32(m, r);
  /* |s/sqrt(m) - 1| < 0x1p-8 */
  d = mul32(s, r);
  u = three - d;
  r = mul32(r, u) << 1;
  /* |r*sqrt(m) - 1| < 0x1.7bp-16 */
  s = mul32(s, u) << 1;
  /* |s/sqrt(m) - 1| < 0x1.7bp-16 */
  d = mul32(s, r);
  u = three - d;
  s = mul32(s, u);
  /* -0x1.03p-28 < s/sqrt(m) - 1 < 0x1.fp-31 */
  s = (s - 1) >> 6;
  /* s < sqrt(m) < s + 0x1.08p-23 */

  /* compute nearest rounded result.  */
  uint32_t d0, d1, d2;
  float y, t;
  d0 = (m << 16) - s * s;
  d1 = s - d0;
  d2 = d1 + s + 1;
  s += d1 >> 31;
  s &= 0x007fffff;
  s |= ey;
  y = *(float *)&s;
  /* handle rounding and inexact exception. */
  uint32_t tiny = d2 == 0 ? 0 : 0x01000000;
  tiny |= (d1 ^ d2) & 0x80000000;
  t = *(float *)&tiny;
  y = y + t;
  return y;
}
#endif

#ifdef MOONBIT_NATIVE_NO_SYS_HEADER
/* returns a*b*2^-64 - e, with error 0 <= e < 3.  */
static inline uint64_t mul64(uint64_t a, uint64_t b) {
  uint64_t ahi = a >> 32;
  uint64_t alo = a & 0xffffffff;
  uint64_t bhi = b >> 32;
  uint64_t blo = b & 0xffffffff;
  return ahi * bhi + (ahi * blo >> 32) + (alo * bhi >> 32);
}

double sqrt(double x) {
  uint64_t ix, top, m;

  /* special case handling.  */
  ix = *(uint64_t *)&x;
  top = ix >> 52;
  if (top - 0x001 >= 0x7ff - 0x001) {
    /* x < 0x1p-1022 or inf or nan.  */
    if (ix * 2 == 0)
      return x;
    if (ix == 0x7ff0000000000000)
      return x;
    if (ix > 0x7ff0000000000000)
      return (x - x) / (x - x);
    /* x is subnormal, normalize it.  */
    x *= 0x1p52;
    ix = *(uint64_t *)&x;
    top = ix >> 52;
    top -= 52;
  }

  /* argument reduction:
     x = 4^e m; with integer e, and m in [1, 4)
     m: fixed point representation [2.62]
     2^e is the exponent part of the result.  */
  int even = top & 1;
  m = (ix << 11) | 0x8000000000000000;
  if (even)
    m >>= 1;
  top = (top + 0x3ff) >> 1;

  /* approximate r ~ 1/sqrt(m) and s ~ sqrt(m) when m in [1,4)

     initial estimate:
     7bit table lookup (1bit exponent and 6bit significand).

     iterative approximation:
     using 2 goldschmidt iterations with 32bit int arithmetics
     and a final iteration with 64bit int arithmetics.

     details:

     the relative error (e = r0 sqrt(m)-1) of a linear estimate
     (r0 = a m + b) is |e| < 0.085955 ~ 0x1.6p-4 at best,
     a table lookup is faster and needs one less iteration
     6 bit lookup table (128b) gives |e| < 0x1.f9p-8
     7 bit lookup table (256b) gives |e| < 0x1.fdp-9
     for single and double prec 6bit is enough but for quad
     prec 7bit is needed (or modified iterations). to avoid
     one more iteration >=13bit table would be needed (16k).

     a newton-raphson iteration for r is
       w = r*r
       u = 3 - m*w
       r = r*u/2
     can use a goldschmidt iteration for s at the end or
       s = m*r

     first goldschmidt iteration is
       s = m*r
       u = 3 - s*r
       r = r*u/2
       s = s*u/2
     next goldschmidt iteration is
       u = 3 - s*r
       r = r*u/2
       s = s*u/2
     and at the end r is not computed only s.

     they use the same amount of operations and converge at the
     same quadratic rate, i.e. if
       r1 sqrt(m) - 1 = e, then
       r2 sqrt(m) - 1 = -3/2 e^2 - 1/2 e^3
     the advantage of goldschmidt is that the mul for s and r
     are independent (computed in parallel), however it is not
     "self synchronizing": it only uses the input m in the
     first iteration so rounding errors accumulate. at the end
     or when switching to larger precision arithmetics rounding
     errors dominate so the first iteration should be used.

     the fixed point representations are
       m: 2.30 r: 0.32, s: 2.30, d: 2.30, u: 2.30, three: 2.30
     and after switching to 64 bit
       m: 2.62 r: 0.64, s: 2.62, d: 2.62, u: 2.62, three: 2.62  */

  static const uint64_t three = 0xc0000000;
  uint64_t r, s, d, u, i;

  i = (ix >> 46) % 128;
  r = (uint32_t)__rsqrt_tab[i] << 16;
  /* |r sqrt(m) - 1| < 0x1.fdp-9 */
  s = mul32(m >> 32, r);
  /* |s/sqrt(m) - 1| < 0x1.fdp-9 */
  d = mul32(s, r);
  u = three - d;
  r = mul32(r, u) << 1;
  /* |r sqrt(m) - 1| < 0x1.7bp-16 */
  s = mul32(s, u) << 1;
  /* |s/sqrt(m) - 1| < 0x1.7bp-16 */
  d = mul32(s, r);
  u = three - d;
  r = mul32(r, u) << 1;
  /* |r sqrt(m) - 1| < 0x1.3704p-29 (measured worst-case) */
  r = r << 32;
  s = mul64(m, r);
  d = mul64(s, r);
  u = (three << 32) - d;
  s = mul64(s, u); /* repr: 3.61 */
  /* -0x1p-57 < s - sqrt(m) < 0x1.8001p-61 */
  s = (s - 2) >> 9; /* repr: 12.52 */
  /* -0x1.09p-52 < s - sqrt(m) < -0x1.fffcp-63 */

  /* s < sqrt(m) < s + 0x1.09p-52,
     compute nearest rounded result:
     the nearest result to 52 bits is either s or s+0x1p-52,
     we can decide by comparing (2^52 s + 0.5)^2 to 2^104 m.  */
  uint64_t d0, d1, d2;
  double y, t;
  d0 = (m << 42) - s * s;
  d1 = s - d0;
  d2 = d1 + s + 1;
  s += d1 >> 63;
  s &= 0x000fffffffffffff;
  s |= top << 52;
  y = *(double *)&s;
  return y;
}
#endif

#ifdef MOONBIT_NATIVE_NO_SYS_HEADER
double fabs(double x) {
  union {
    double f;
    uint64_t i;
  } u = {x};
  u.i &= 0x7fffffffffffffffULL;
  return u.f;
}
#endif

#ifdef MOONBIT_NATIVE_NO_SYS_HEADER
float fabsf(float x) {
  union {
    float f;
    uint32_t i;
  } u = {x};
  u.i &= 0x7fffffff;
  return u.f;
}
#endif

#ifdef _MSC_VER
/* MSVC treats syntactic division by zero as fatal error,
   even for float point numbers,
   so we have to use a constant variable to work around this */
static const int MOONBIT_ZERO = 0;
#else
#define MOONBIT_ZERO 0
#endif

#ifdef __cplusplus
}
#endif
struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE;

struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure;

struct _M0DTPC15error5Error58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectError;

struct _M0TWssbEu;

struct _M0TUsiE;

struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE;

struct _M0TPB13StringBuilder;

struct _M0TPB5ArrayGORPB9SourceLocE;

struct _M0DTPC15error5Error74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallError;

struct _M0TWWuEuWRPC15error5ErrorEuEOuQRPC15error5Error;

struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE;

struct _M0TPB5ArrayGUsiEE;

struct _M0TWRPC15error5ErrorEs;

struct _M0BTPB6Logger;

struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1825__l431__;

struct _M0TPB6Logger;

struct _M0DTPC15error5Error114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest;

struct _M0TWEuQRPC15error5Error;

struct _M0TURPB6LoggerRPC16string10StringViewE;

struct _M0DTPC15error5Error76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableError;

struct _M0DTPC15error5Error60moonbitlang_2fcore_2fbuiltin_2eSnapshotError_2eSnapshotError;

struct _M0DTPC15error5Error68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentError;

struct _M0DTPC16result6ResultGbRP412hnlyxiaobing12MBOpenClacky3lib6errors33MoonBitTestDriverInternalSkipTestE3Err;

struct _M0TUsRPB3MapGiUWEuQRPC15error5ErrorNsEEE;

struct _M0DTPC16result6ResultGbRP412hnlyxiaobing12MBOpenClacky3lib6errors33MoonBitTestDriverInternalSkipTestE2Ok;

struct _M0TPB8MutLocalGiE;

struct _M0DTPC15error5Error80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterrupted;

struct _M0DTPC16result6ResultGuRPB12InspectErrorE2Ok;

struct _M0TWEOs;

struct _M0DTPC15error5Error96hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBrowserNotReachableError_2eBrowserNotReachableError;

struct _M0DTPC16result6ResultGuRPC15error5ErrorE2Ok;

struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1829__l430__;

struct _M0DTPC16result6ResultGOuRPC15error5ErrorE3Err;

struct _M0TPB4Show;

struct _M0TPB9ArrayViewGUiUWEuQRPC15error5ErrorNsEEE;

struct _M0TPB13SourceLocRepr;

struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE;

struct _M0TWRPC15error5ErrorEu;

struct _M0TPB6Hasher;

struct _M0DTPC16result6ResultGuRPB12InspectErrorE3Err;

struct _M0TUiUWEuQRPC15error5ErrorNsEE;

struct _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok;

struct _M0DTPC15error5Error112hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalJsError_2eMoonBitTestDriverInternalJsError;

struct _M0DTPC16result6ResultGuRPC15error5ErrorE3Err;

struct _M0BTPB4Show;

struct _M0DTPC15error5Error92hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eUpstreamTruncatedError_2eUpstreamTruncatedError;

struct _M0TWuEu;

struct _M0TPC16string10StringView;

struct _M0R59ArrayView_3a_3aiter_7c_5bString_5d_7c_2eanon__u1411__l674__;

struct _M0KTPB4ShowS6String;

struct _M0KTPB6LoggerTPB13StringBuilder;

struct _M0DTPC15error5Error78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestError;

struct _M0TPB9ArrayViewGUsRPB3MapGiUWEuQRPC15error5ErrorNsEEEE;

struct _M0TPB5ArrayGsE;

struct _M0R115_24hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c787;

struct _M0DTPC16result6ResultGuRPB7FailureE3Err;

struct _M0TWEu;

struct _M0TPB9ArrayViewGsE;

struct _M0DTPC16result6ResultGuRPB7FailureE2Ok;

struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE;

struct _M0TUWEuQRPC15error5ErrorNsE;

struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE {
  int32_t $0;
  int32_t $2;
  int32_t $3;
  int32_t $4;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* $1;
  struct _M0TUWEuQRPC15error5ErrorNsE* $5;
  
};

struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure {
  moonbit_string_t $0;
  
};

struct _M0DTPC15error5Error58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectError {
  moonbit_string_t $0;
  
};

struct _M0TWssbEu {
  int32_t(* code)(
    struct _M0TWssbEu*,
    moonbit_string_t,
    moonbit_string_t,
    int32_t
  );
  
};

struct _M0TUsiE {
  int32_t $1;
  moonbit_string_t $0;
  
};

struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE {
  int32_t $1;
  int32_t $2;
  int32_t $3;
  int32_t $4;
  int32_t $6;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE** $0;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* $5;
  
};

struct _M0TPB13StringBuilder {
  int32_t $1;
  uint16_t* $0;
  
};

struct _M0TPB5ArrayGORPB9SourceLocE {
  int32_t $1;
  moonbit_string_t* $0;
  
};

struct _M0DTPC15error5Error74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallError {
  moonbit_string_t $0;
  moonbit_string_t $1;
  
};

struct _M0TWWuEuWRPC15error5ErrorEuEOuQRPC15error5Error {
  struct moonbit_result_0(* code)(
    struct _M0TWWuEuWRPC15error5ErrorEuEOuQRPC15error5Error*,
    struct _M0TWuEu*,
    struct _M0TWRPC15error5ErrorEu*
  );
  
};

struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE {
  int32_t $0;
  int32_t $2;
  int32_t $3;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* $1;
  moonbit_string_t $4;
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* $5;
  
};

struct _M0TPB5ArrayGUsiEE {
  int32_t $1;
  struct _M0TUsiE** $0;
  
};

struct _M0TWRPC15error5ErrorEs {
  moonbit_string_t(* code)(struct _M0TWRPC15error5ErrorEs*, void*);
  
};

struct _M0BTPB6Logger {
  int32_t(* $method_0)(void*, moonbit_string_t);
  int32_t(* $method_1)(void*, moonbit_string_t, int32_t, int32_t);
  int32_t(* $method_2)(void*, struct _M0TPC16string10StringView);
  int32_t(* $method_3)(void*, int32_t);
  
};

struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1825__l431__ {
  int32_t(* code)(struct _M0TWRPC15error5ErrorEu*, void*);
  struct _M0TWRPC15error5ErrorEs* $0;
  struct _M0TWssbEu* $1;
  moonbit_string_t $2;
  
};

struct _M0TPB6Logger {
  struct _M0BTPB6Logger* $0;
  void* $1;
  
};

struct _M0DTPC15error5Error114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest {
  moonbit_string_t $0;
  
};

struct _M0TWEuQRPC15error5Error {
  struct moonbit_result_0(* code)(struct _M0TWEuQRPC15error5Error*);
  
};

struct _M0TURPB6LoggerRPC16string10StringViewE {
  int32_t $1_1;
  int32_t $1_2;
  struct _M0BTPB6Logger* $0_0;
  void* $0_1;
  moonbit_string_t $1_0;
  
};

struct _M0DTPC15error5Error76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableError {
  moonbit_string_t $0;
  
};

struct _M0DTPC15error5Error60moonbitlang_2fcore_2fbuiltin_2eSnapshotError_2eSnapshotError {
  moonbit_string_t $0;
  
};

struct _M0DTPC15error5Error68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentError {
  moonbit_string_t $0;
  
};

struct _M0DTPC16result6ResultGbRP412hnlyxiaobing12MBOpenClacky3lib6errors33MoonBitTestDriverInternalSkipTestE3Err {
  void* $0;
  
};

struct _M0TUsRPB3MapGiUWEuQRPC15error5ErrorNsEEE {
  moonbit_string_t $0;
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* $1;
  
};

struct _M0DTPC16result6ResultGbRP412hnlyxiaobing12MBOpenClacky3lib6errors33MoonBitTestDriverInternalSkipTestE2Ok {
  int32_t $0;
  
};

struct _M0TPB8MutLocalGiE {
  int32_t $0;
  
};

struct _M0DTPC15error5Error80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterrupted {
  moonbit_string_t $0;
  
};

struct _M0DTPC16result6ResultGuRPB12InspectErrorE2Ok {
  int32_t $0;
  
};

struct _M0TWEOs {
  moonbit_string_t(* code)(struct _M0TWEOs*);
  
};

struct _M0DTPC15error5Error96hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBrowserNotReachableError_2eBrowserNotReachableError {
  moonbit_string_t $0;
  
};

struct _M0DTPC16result6ResultGuRPC15error5ErrorE2Ok {
  int32_t $0;
  
};

struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1829__l430__ {
  int32_t(* code)(struct _M0TWEu*);
  struct _M0TWssbEu* $0;
  moonbit_string_t $1;
  
};

struct _M0DTPC16result6ResultGOuRPC15error5ErrorE3Err {
  void* $0;
  
};

struct _M0TPB4Show {
  struct _M0BTPB4Show* $0;
  void* $1;
  
};

struct _M0TPB9ArrayViewGUiUWEuQRPC15error5ErrorNsEEE {
  int32_t $1;
  int32_t $2;
  struct _M0TUiUWEuQRPC15error5ErrorNsEE** $0;
  
};

struct _M0TPB13SourceLocRepr {
  int32_t $0_1;
  int32_t $0_2;
  int32_t $1_1;
  int32_t $1_2;
  int32_t $2_1;
  int32_t $2_2;
  int32_t $3_1;
  int32_t $3_2;
  int32_t $4_1;
  int32_t $4_2;
  moonbit_string_t $0_0;
  moonbit_string_t $1_0;
  moonbit_string_t $2_0;
  moonbit_string_t $3_0;
  moonbit_string_t $4_0;
  
};

struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE {
  int32_t $1;
  int32_t $2;
  int32_t $3;
  int32_t $4;
  int32_t $6;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE** $0;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* $5;
  
};

struct _M0TWRPC15error5ErrorEu {
  int32_t(* code)(struct _M0TWRPC15error5ErrorEu*, void*);
  
};

struct _M0TPB6Hasher {
  uint32_t $0;
  
};

struct _M0DTPC16result6ResultGuRPB12InspectErrorE3Err {
  void* $0;
  
};

struct _M0TUiUWEuQRPC15error5ErrorNsEE {
  int32_t $0;
  struct _M0TUWEuQRPC15error5ErrorNsE* $1;
  
};

struct _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok {
  int32_t $0;
  
};

struct _M0DTPC15error5Error112hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalJsError_2eMoonBitTestDriverInternalJsError {
  moonbit_string_t $0;
  
};

struct _M0DTPC16result6ResultGuRPC15error5ErrorE3Err {
  void* $0;
  
};

struct _M0BTPB4Show {
  int32_t(* $method_0)(void*, struct _M0TPB6Logger);
  moonbit_string_t(* $method_1)(void*);
  
};

struct _M0DTPC15error5Error92hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eUpstreamTruncatedError_2eUpstreamTruncatedError {
  moonbit_string_t $0;
  
};

struct _M0TWuEu {
  int32_t(* code)(struct _M0TWuEu*, int32_t);
  
};

struct _M0TPC16string10StringView {
  int32_t $1;
  int32_t $2;
  moonbit_string_t $0;
  
};

struct _M0R59ArrayView_3a_3aiter_7c_5bString_5d_7c_2eanon__u1411__l674__ {
  moonbit_string_t(* code)(struct _M0TWEOs*);
  int32_t $0_1;
  int32_t $0_2;
  moonbit_string_t* $0_0;
  struct _M0TPB8MutLocalGiE* $1;
  
};

struct _M0KTPB4ShowS6String {
  struct _M0BTPB4Show* $0;
  void* $1;
  
};

struct _M0KTPB6LoggerTPB13StringBuilder {
  struct _M0BTPB6Logger* $0;
  void* $1;
  
};

struct _M0DTPC15error5Error78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestError {
  int32_t $0;
  moonbit_string_t $1;
  
};

struct _M0TPB9ArrayViewGUsRPB3MapGiUWEuQRPC15error5ErrorNsEEEE {
  int32_t $1;
  int32_t $2;
  struct _M0TUsRPB3MapGiUWEuQRPC15error5ErrorNsEEE** $0;
  
};

struct _M0TPB5ArrayGsE {
  int32_t $1;
  moonbit_string_t* $0;
  
};

struct _M0R115_24hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c787 {
  int32_t(* code)(
    struct _M0TWssbEu*,
    moonbit_string_t,
    moonbit_string_t,
    int32_t
  );
  int32_t $0;
  moonbit_string_t $1;
  
};

struct _M0DTPC16result6ResultGuRPB7FailureE3Err {
  void* $0;
  
};

struct _M0TWEu {
  int32_t(* code)(struct _M0TWEu*);
  
};

struct _M0TPB9ArrayViewGsE {
  int32_t $1;
  int32_t $2;
  moonbit_string_t* $0;
  
};

struct _M0DTPC16result6ResultGuRPB7FailureE2Ok {
  int32_t $0;
  
};

struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE {
  int32_t $1;
  struct _M0TWWuEuWRPC15error5ErrorEuEOuQRPC15error5Error** $0;
  
};

struct _M0TUWEuQRPC15error5ErrorNsE {
  struct _M0TWEuQRPC15error5Error* $0;
  moonbit_string_t* $1;
  
};

struct moonbit_result_0 {
  int tag;
  union { int32_t ok; void* err;  } data;
  
};

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__2_2edyncall(
  struct _M0TWEuQRPC15error5Error*
);

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__3_2edyncall(
  struct _M0TWEuQRPC15error5Error*
);

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__0_2edyncall(
  struct _M0TWEuQRPC15error5Error*
);

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__4_2edyncall(
  struct _M0TWEuQRPC15error5Error*
);

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__1_2edyncall(
  struct _M0TWEuQRPC15error5Error*
);

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__5_2edyncall(
  struct _M0TWEuQRPC15error5Error*
);

int32_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors44moonbit__test__driver__internal__do__execute(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*,
  moonbit_string_t,
  int32_t
);

moonbit_string_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors44moonbit__test__driver__internal__do__executeN17error__to__stringS796(
  struct _M0TWRPC15error5ErrorEs*,
  void*
);

int32_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors44moonbit__test__driver__internal__do__executeN14handle__resultS787(
  struct _M0TWssbEu*,
  moonbit_string_t,
  moonbit_string_t,
  int32_t
);

struct moonbit_result_0 _M0IP412hnlyxiaobing12MBOpenClacky3lib6errors41MoonBit__Test__Driver__Internal__No__ArgsP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__test(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*,
  moonbit_string_t,
  int32_t,
  struct _M0TWssbEu*,
  struct _M0TWRPC15error5ErrorEs*
);

int32_t _M0IP412hnlyxiaobing12MBOpenClacky3lib6errors41MoonBit__Test__Driver__Internal__No__ArgsP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testC1829l430(
  struct _M0TWEu*
);

int32_t _M0IP412hnlyxiaobing12MBOpenClacky3lib6errors41MoonBit__Test__Driver__Internal__No__ArgsP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testC1825l431(
  struct _M0TWRPC15error5ErrorEu*,
  void*
);

int32_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors45moonbit__test__driver__internal__catch__error(
  struct _M0TWEuQRPC15error5Error*,
  struct _M0TWEu*,
  struct _M0TWRPC15error5ErrorEu*
);

struct _M0TPB5ArrayGUsiEE* _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__args(
  
);

struct _M0TPB5ArrayGsE* _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN51moonbit__test__driver__internal__split__mbt__stringS721(
  int32_t,
  moonbit_string_t,
  int32_t
);

struct _M0TPB5ArrayGsE* _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN57moonbit__test__driver__internal__get__cli__args__internalS716(
  int32_t
);

moonbit_string_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS709(
  int32_t,
  moonbit_bytes_t
);

int32_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN45moonbit__test__driver__internal__parse__int__S703(
  int32_t,
  moonbit_string_t
);

#define _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__get__cli__args__ffi moonbit_get_cli_args

struct moonbit_result_0 _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testGRP412hnlyxiaobing12MBOpenClacky3lib6errors43MoonBit__Test__Driver__Internal__With__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*,
  moonbit_string_t,
  int32_t,
  struct _M0TWssbEu*,
  struct _M0TWRPC15error5ErrorEs*
);

struct moonbit_result_0 _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testGRP412hnlyxiaobing12MBOpenClacky3lib6errors48MoonBit__Test__Driver__Internal__Async__No__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*,
  moonbit_string_t,
  int32_t,
  struct _M0TWssbEu*,
  struct _M0TWRPC15error5ErrorEs*
);

struct moonbit_result_0 _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testGRP412hnlyxiaobing12MBOpenClacky3lib6errors50MoonBit__Test__Driver__Internal__Async__With__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*,
  moonbit_string_t,
  int32_t,
  struct _M0TWssbEu*,
  struct _M0TWRPC15error5ErrorEs*
);

struct moonbit_result_0 _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testGRP412hnlyxiaobing12MBOpenClacky3lib6errors50MoonBit__Test__Driver__Internal__With__Bench__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*,
  moonbit_string_t,
  int32_t,
  struct _M0TWssbEu*,
  struct _M0TWRPC15error5ErrorEs*
);

int32_t _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors28MoonBit__Async__Test__Driver17run__async__testsGRP412hnlyxiaobing12MBOpenClacky3lib6errors34MoonBit__Async__Test__Driver__ImplE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*
);

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__5(
  
);

int32_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors20is__retryable__error(
  void*
);

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__4(
  
);

int32_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors16is__agent__error(
  void*
);

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__3(
  
);

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__2(
  
);

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__1(
  
);

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__0(
  
);

moonbit_string_t _M0MPC15array5Array2atGsE(struct _M0TPB5ArrayGsE*, int32_t);

moonbit_string_t _M0IPB9SourceLocPB4Show10to__string(moonbit_string_t);

int32_t _M0FPB7printlnGsE(moonbit_string_t);

struct moonbit_result_0 _M0FPB12assert__true(
  int32_t,
  moonbit_string_t,
  moonbit_string_t
);

struct moonbit_result_0 _M0FPB13assert__false(
  int32_t,
  moonbit_string_t,
  moonbit_string_t
);

int32_t _M0IPC13int3IntPB4Hash13hash__combine(int32_t, struct _M0TPB6Hasher*);

int32_t _M0IPC16string6StringPB4Hash13hash__combine(
  moonbit_string_t,
  struct _M0TPB6Hasher*
);

int32_t _M0MPB6Hasher15combine__string(
  struct _M0TPB6Hasher*,
  moonbit_string_t
);

int32_t _M0MPC16string6String20unsafe__charcode__at(
  moonbit_string_t,
  int32_t
);

struct _M0TUWEuQRPC15error5ErrorNsE* _M0MPB3Map3getGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE*,
  int32_t
);

struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0MPB3Map3getGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*,
  moonbit_string_t
);

struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0MPB3Map11from__arrayGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB9ArrayViewGUsRPB3MapGiUWEuQRPC15error5ErrorNsEEEE
);

struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0MPB3Map11from__arrayGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB9ArrayViewGUiUWEuQRPC15error5ErrorNsEEE
);

int32_t _M0MPB3Map3setGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*,
  moonbit_string_t,
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE*
);

int32_t _M0MPB3Map3setGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE*,
  int32_t,
  struct _M0TUWEuQRPC15error5ErrorNsE*
);

int32_t _M0MPB3Map4growGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*
);

int32_t _M0MPB3Map4growGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE*
);

int32_t _M0MPB3Map15set__with__hashGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*,
  moonbit_string_t,
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE*,
  int32_t
);

int32_t _M0MPB3Map15set__with__hashGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE*,
  int32_t,
  struct _M0TUWEuQRPC15error5ErrorNsE*,
  int32_t
);

int32_t _M0MPB3Map10push__awayGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*,
  int32_t,
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*
);

int32_t _M0MPB3Map10push__awayGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE*,
  int32_t,
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE*
);

int32_t _M0MPB3Map10set__entryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*,
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*,
  int32_t
);

int32_t _M0MPB3Map10set__entryGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE*,
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE*,
  int32_t
);

int32_t _M0MPB3Map20add__entry__to__tailGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*,
  int32_t,
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*
);

int32_t _M0MPB3Map20add__entry__to__tailGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE*,
  int32_t,
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE*
);

struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0MPB3Map11new_2einnerGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  int32_t
);

struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0MPB3Map11new_2einnerGiUWEuQRPC15error5ErrorNsEE(
  int32_t
);

int32_t _M0MPC13int3Int20next__power__of__two(int32_t);

int32_t _M0FPB21calc__grow__threshold(int32_t);

struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0MPC16option6Option6unwrapGRPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEEE(
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*
);

struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0MPC16option6Option6unwrapGRPB5EntryGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE*
);

struct _M0TWEOs* _M0MPC15array13ReadOnlyArray4iterGsE(moonbit_string_t*);

struct _M0TWEOs* _M0MPC15array10FixedArray4iterGsE(moonbit_string_t*);

struct _M0TWEOs* _M0MPC15array9ArrayView4iterGsE(struct _M0TPB9ArrayViewGsE);

moonbit_string_t _M0MPC15array9ArrayView4iterGsEC1411l674(struct _M0TWEOs*);

int32_t _M0IPC16string6StringPB4Show6output(
  moonbit_string_t,
  struct _M0TPB6Logger
);

moonbit_string_t _M0IPC13int3IntPB4Show10to__string(int32_t);

int32_t _M0IPC13int3IntPB4Show6output(int32_t, struct _M0TPB6Logger);

moonbit_string_t _M0IPC14bool4BoolPB4Show10to__string(int32_t);

int32_t _M0MPC15array5Array4pushGsE(
  struct _M0TPB5ArrayGsE*,
  moonbit_string_t
);

int32_t _M0MPC15array5Array4pushGUsiEE(
  struct _M0TPB5ArrayGUsiEE*,
  struct _M0TUsiE*
);

int32_t _M0MPC15array5Array7reallocGsE(struct _M0TPB5ArrayGsE*);

int32_t _M0MPC15array5Array7reallocGUsiEE(struct _M0TPB5ArrayGUsiEE*);

int32_t _M0MPC15array5Array14resize__bufferGsE(
  struct _M0TPB5ArrayGsE*,
  int32_t
);

int32_t _M0MPC15array5Array14resize__bufferGUsiEE(
  struct _M0TPB5ArrayGUsiEE*,
  int32_t
);

moonbit_string_t* _M0MPC15array5Array6bufferGsE(struct _M0TPB5ArrayGsE*);

struct _M0TUsiE** _M0MPC15array5Array6bufferGUsiEE(
  struct _M0TPB5ArrayGUsiEE*
);

struct _M0TPB5ArrayGsE* _M0MPC15array5Array11new_2einnerGsE(int32_t);

moonbit_string_t _M0IPC16string6StringPB4Show10to__string(moonbit_string_t);

int32_t _M0IPB13StringBuilderPB6Logger11write__view(
  struct _M0TPB13StringBuilder*,
  struct _M0TPC16string10StringView
);

int32_t _M0MPC16string6String24char__length__ge_2einner(
  moonbit_string_t,
  int32_t,
  int32_t,
  int64_t
);

int32_t _M0MPC15array9ArrayView6lengthGUsRPB3MapGiUWEuQRPC15error5ErrorNsEEEE(
  struct _M0TPB9ArrayViewGUsRPB3MapGiUWEuQRPC15error5ErrorNsEEEE
);

int32_t _M0MPC15array9ArrayView6lengthGUiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB9ArrayViewGUiUWEuQRPC15error5ErrorNsEEE
);

int32_t _M0MPC15array9ArrayView6lengthGsE(struct _M0TPB9ArrayViewGsE);

struct _M0TPC16string10StringView _M0MPC16string6String4view(
  moonbit_string_t,
  int64_t,
  int64_t
);

struct _M0TPC16string10StringView _M0MPC16string6String12view_2einner(
  moonbit_string_t,
  int32_t,
  int64_t
);

moonbit_string_t _M0IPC16string10StringViewPB4Show10to__string(
  struct _M0TPC16string10StringView
);

moonbit_string_t _M0MPC16string6String17unsafe__substring(
  moonbit_string_t,
  int32_t,
  int32_t
);

int32_t _M0IPC14byte4BytePB7Default7default();

moonbit_string_t _M0MPC15bytes5Bytes29to__unchecked__string_2einner(
  moonbit_bytes_t,
  int32_t,
  int64_t
);

#define _M0FPB19unsafe__sub__string moonbit_unsafe_bytes_sub_string

int32_t _M0MPC15array10FixedArray18blit__from__string(
  moonbit_bytes_t,
  int32_t,
  moonbit_string_t,
  int32_t,
  int32_t
);

int32_t _M0MPC14uint4UInt8to__byte(uint32_t);

int32_t _M0IPC16string10StringViewPB4Show6output(
  struct _M0TPC16string10StringView,
  struct _M0TPB6Logger
);

struct _M0TWEOs* _M0MPB4Iter3newGsE(struct _M0TWEOs*);

struct moonbit_result_0 _M0FPB10assert__eqGiE(
  int32_t,
  int32_t,
  moonbit_string_t,
  moonbit_string_t
);

struct moonbit_result_0 _M0FPB4failGuE(moonbit_string_t, moonbit_string_t);

moonbit_string_t _M0FPB13debug__stringGiE(int32_t);

moonbit_string_t _M0MPC13int3Int18to__string_2einner(int32_t, int32_t);

int32_t _M0FPB14radix__count32(uint32_t, int32_t);

int32_t _M0FPB12hex__count32(uint32_t);

int32_t _M0FPB12dec__count32(uint32_t);

int32_t _M0FPB20int__to__string__dec(uint16_t*, uint32_t, int32_t, int32_t);

int32_t _M0FPB24int__to__string__generic(
  uint16_t*,
  uint32_t,
  int32_t,
  int32_t,
  int32_t
);

int32_t _M0FPB20int__to__string__hex(uint16_t*, uint32_t, int32_t, int32_t);

moonbit_string_t _M0MPB4Iter4nextGsE(struct _M0TWEOs*);

moonbit_string_t _M0IP016_24default__implPB4Show10to__stringGRPB7FailureE(
  void*
);

int32_t _M0MPC16string10StringView13start__offset(
  struct _M0TPC16string10StringView
);

moonbit_string_t _M0MPC16string10StringView4data(
  struct _M0TPC16string10StringView
);

int32_t _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE(
  struct _M0TPB13StringBuilder*,
  moonbit_string_t,
  int32_t,
  int32_t
);

struct _M0TPC16string10StringView _M0MPC16string6String11sub_2einner(
  moonbit_string_t,
  int32_t,
  int64_t
);

int32_t _M0IP016_24default__implPB4Hash4hashGiE(int32_t);

int32_t _M0IP016_24default__implPB4Hash4hashGsE(moonbit_string_t);

struct _M0TPB6Hasher* _M0MPB6Hasher3new(int64_t);

struct _M0TPB6Hasher* _M0MPB6Hasher11new_2einner(int32_t);

int32_t _M0MPB6Hasher8finalize(struct _M0TPB6Hasher*);

uint32_t _M0MPB6Hasher9avalanche(struct _M0TPB6Hasher*);

int32_t _M0IP016_24default__implPB2Eq10not__equalGsE(
  moonbit_string_t,
  moonbit_string_t
);

int32_t _M0MPB6Hasher7combineGiE(struct _M0TPB6Hasher*, int32_t);

int32_t _M0MPB6Hasher7combineGsE(struct _M0TPB6Hasher*, moonbit_string_t);

int32_t _M0MPB6Hasher12combine__int(struct _M0TPB6Hasher*, int32_t);

struct moonbit_result_0 _M0FPB15inspect_2einner(
  struct _M0TPB4Show,
  moonbit_string_t,
  moonbit_string_t,
  struct _M0TPB5ArrayGORPB9SourceLocE*
);

moonbit_string_t _M0MPB7ArgsLoc8to__json(
  struct _M0TPB5ArrayGORPB9SourceLocE*
);

moonbit_string_t _M0MPB9SourceLoc16to__json__string(moonbit_string_t);

moonbit_string_t _M0MPB13SourceLocRepr16to__json__string(
  struct _M0TPB13SourceLocRepr*
);

int32_t _M0IPB13StringBuilderPB6Logger13write__string(
  struct _M0TPB13StringBuilder*,
  moonbit_string_t
);

int32_t _M0MPC15array10FixedArray26unsafe__blit__from__string(
  uint16_t*,
  int32_t,
  moonbit_string_t,
  int32_t,
  int32_t
);

int32_t _M0MPB13StringBuilder13write__objectGRPC16string10StringViewE(
  struct _M0TPB13StringBuilder*,
  struct _M0TPC16string10StringView
);

struct _M0TPB13SourceLocRepr* _M0MPB13SourceLocRepr5parse(moonbit_string_t);

moonbit_string_t _M0MPC16string6String14escape_2einner(
  moonbit_string_t,
  int32_t
);

int32_t _M0MPC16string10StringView18escape__to_2einner(
  struct _M0TPC16string10StringView,
  struct _M0TPB6Logger,
  int32_t
);

int32_t _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(
  struct _M0TURPB6LoggerRPC16string10StringViewE*,
  int32_t,
  int32_t
);

int32_t _M0MPC16string10StringView11unsafe__get(
  struct _M0TPC16string10StringView,
  int32_t
);

struct _M0TPC16string10StringView _M0MPC16string10StringView11sub_2einner(
  struct _M0TPC16string10StringView,
  int32_t,
  int64_t
);

int32_t _M0MPC16string10StringView6length(struct _M0TPC16string10StringView);

moonbit_string_t _M0MPC14byte4Byte7to__hex(int32_t);

int32_t _M0MPC14byte4Byte7to__hexN14to__hex__digitS3630(int32_t);

int32_t _M0IPC14byte4BytePB3Sub3sub(int32_t, int32_t);

int32_t _M0IPC14byte4BytePB3Mod3mod(int32_t, int32_t);

int32_t _M0IPC14byte4BytePB3Div3div(int32_t, int32_t);

int32_t _M0IPC14byte4BytePB3Add3add(int32_t, int32_t);

moonbit_string_t _M0FPB33base64__encode__string__codepoint(moonbit_string_t);

int32_t _M0MPC16string6String16unsafe__char__at(moonbit_string_t, int32_t);

int32_t _M0MPC16uint166UInt1616unsafe__to__char(int32_t);

int32_t _M0FPB32code__point__of__surrogate__pair(int32_t, int32_t);

int32_t _M0MPC16string6String20char__length_2einner(
  moonbit_string_t,
  int32_t,
  int64_t
);

int32_t _M0MPC16uint166UInt1623is__trailing__surrogate(int32_t);

int32_t _M0MPC16uint166UInt1622is__leading__surrogate(int32_t);

moonbit_string_t _M0FPB14base64__encode(moonbit_bytes_t);

int32_t _M0IPB13StringBuilderPB6Logger11write__char(
  struct _M0TPB13StringBuilder*,
  int32_t
);

int32_t _M0MPB13StringBuilder19grow__if__necessary(
  struct _M0TPB13StringBuilder*,
  int32_t
);

int32_t _M0MPC14uint4UInt10to__uint16(uint32_t);

uint32_t _M0MPC14char4Char8to__uint(int32_t);

moonbit_string_t _M0MPB13StringBuilder10to__string(
  struct _M0TPB13StringBuilder*
);

int32_t _M0IPC16uint166UInt16PB7Default7default();

struct _M0TPB13StringBuilder* _M0MPB13StringBuilder11new_2einner(int32_t);

int32_t _M0MPC14byte4Byte8to__char(int32_t);

int32_t _M0MPB18UninitializedArray12unsafe__blitGsE(
  moonbit_string_t*,
  int32_t,
  moonbit_string_t*,
  int32_t,
  int32_t
);

int32_t _M0MPB18UninitializedArray12unsafe__blitGUsiEE(
  struct _M0TUsiE**,
  int32_t,
  struct _M0TUsiE**,
  int32_t,
  int32_t
);

int32_t _M0MPC15array10FixedArray12unsafe__blitGkE(
  uint16_t*,
  int32_t,
  uint16_t*,
  int32_t,
  int32_t
);

int32_t _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGsEE(
  moonbit_string_t*,
  int32_t,
  moonbit_string_t*,
  int32_t,
  int32_t
);

int32_t _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGUsiEEE(
  struct _M0TUsiE**,
  int32_t,
  struct _M0TUsiE**,
  int32_t,
  int32_t
);

int32_t _M0MPB6Hasher13combine__uint(struct _M0TPB6Hasher*, uint32_t);

int32_t _M0MPB6Hasher8consume4(struct _M0TPB6Hasher*, uint32_t);

uint32_t _M0FPB4rotl(uint32_t, int32_t);

int32_t _M0IPB7FailurePB4Show6output(void*, struct _M0TPB6Logger);

int32_t _M0MPB6Logger13write__objectGsE(
  struct _M0TPB6Logger,
  moonbit_string_t
);

int32_t _M0FPC15abort5abortGuE(moonbit_string_t);

int32_t _M0FPC15abort5abortGiE(moonbit_string_t);

struct _M0TPC16string10StringView _M0FPC15abort5abortGRPC16string10StringViewE(
  moonbit_string_t
);

moonbit_string_t _M0FP15Error10to__string(void*);

moonbit_string_t _M0IPC16string6StringPB4Show64to__string_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eShow(
  void*
);

int32_t _M0IPC16string6StringPB4Show60output_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eShow(
  void*,
  struct _M0TPB6Logger
);

int32_t _M0IPB13StringBuilderPB6Logger67write__char_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void*,
  int32_t
);

int32_t _M0IPB13StringBuilderPB6Logger67write__view_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void*,
  struct _M0TPC16string10StringView
);

int32_t _M0IP016_24default__implPB6Logger72write__substring_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLoggerGRPB13StringBuilderE(
  void*,
  moonbit_string_t,
  int32_t,
  int32_t
);

int32_t _M0IPB13StringBuilderPB6Logger69write__string_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void*,
  moonbit_string_t
);

struct { int32_t rc; uint32_t meta; uint16_t const data[65]; 
} const moonbit_string_literal_76 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 64), 
    104, 110, 108, 121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 
    66, 79, 112, 101, 110, 67, 108, 97, 99, 107, 121, 47, 108, 105, 98, 
    47, 101, 114, 114, 111, 114, 115, 46, 84, 111, 111, 108, 67, 97, 
    108, 108, 69, 114, 114, 111, 114, 46, 84, 111, 111, 108, 67, 97, 
    108, 108, 69, 114, 114, 111, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[65]; 
} const moonbit_string_literal_3 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 64), 
    123, 34, 112, 97, 99, 107, 97, 103, 101, 34, 58, 32, 34, 104, 110, 
    108, 121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 
    101, 110, 67, 108, 97, 99, 107, 121, 47, 108, 105, 98, 47, 101, 114, 
    114, 111, 114, 115, 34, 44, 32, 34, 102, 105, 108, 101, 110, 97, 
    109, 101, 34, 58, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[13]; 
} const moonbit_string_literal_1 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 12), 
    115, 107, 105, 112, 112, 101, 100, 32, 116, 101, 115, 116, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[1]; 
} const moonbit_string_literal_0 =
  { -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 0), 0};

struct { int32_t rc; uint32_t meta; uint16_t const data[30]; 
} const moonbit_string_literal_87 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 29), 
    97, 103, 101, 110, 116, 95, 105, 110, 116, 101, 114, 114, 117, 112, 
    116, 101, 100, 95, 114, 97, 105, 115, 101, 95, 99, 97, 116, 99, 104, 
    0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[3]; 
} const moonbit_string_literal_60 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 2), 
    44, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[83]; 
} const moonbit_string_literal_77 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 82), 
    104, 110, 108, 121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 
    66, 79, 112, 101, 110, 67, 108, 97, 99, 107, 121, 47, 108, 105, 98, 
    47, 101, 114, 114, 111, 114, 115, 46, 85, 112, 115, 116, 114, 101, 
    97, 109, 84, 114, 117, 110, 99, 97, 116, 101, 100, 69, 114, 114, 
    111, 114, 46, 85, 112, 115, 116, 114, 101, 97, 109, 84, 114, 117, 
    110, 99, 97, 116, 101, 100, 69, 114, 114, 111, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[24]; 
} const moonbit_string_literal_88 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 23), 
    97, 103, 101, 110, 116, 95, 101, 114, 114, 111, 114, 95, 114, 97, 
    105, 115, 101, 95, 99, 97, 116, 99, 104, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[66]; 
} const moonbit_string_literal_32 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 65), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 50, 53, 58, 55, 45, 50, 53, 58, 52, 54, 64, 104, 110, 108, 121, 
    120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 
    67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[66]; 
} const moonbit_string_literal_12 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 65), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 53, 53, 58, 51, 45, 53, 53, 58, 53, 53, 64, 104, 110, 108, 121, 
    120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 
    67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[66]; 
} const moonbit_string_literal_10 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 65), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 53, 51, 58, 51, 45, 53, 51, 58, 53, 56, 64, 104, 110, 108, 121, 
    120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 
    67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[23]; 
} const moonbit_string_literal_46 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 22), 
    105, 110, 118, 97, 108, 105, 100, 32, 115, 117, 114, 114, 111, 103, 
    97, 116, 101, 32, 112, 97, 105, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[53]; 
} const moonbit_string_literal_79 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 52), 
    109, 111, 111, 110, 98, 105, 116, 108, 97, 110, 103, 47, 99, 111, 
    114, 101, 47, 98, 117, 105, 108, 116, 105, 110, 46, 83, 110, 97, 
    112, 115, 104, 111, 116, 69, 114, 114, 111, 114, 46, 83, 110, 97, 
    112, 115, 104, 111, 116, 69, 114, 114, 111, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[103]; 
} const moonbit_string_literal_80 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 102), 
    104, 110, 108, 121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 
    66, 79, 112, 101, 110, 67, 108, 97, 99, 107, 121, 47, 108, 105, 98, 
    47, 101, 114, 114, 111, 114, 115, 46, 77, 111, 111, 110, 66, 105, 
    116, 84, 101, 115, 116, 68, 114, 105, 118, 101, 114, 73, 110, 116, 
    101, 114, 110, 97, 108, 74, 115, 69, 114, 114, 111, 114, 46, 77, 
    111, 111, 110, 66, 105, 116, 84, 101, 115, 116, 68, 114, 105, 118, 
    101, 114, 73, 110, 116, 101, 114, 110, 97, 108, 74, 115, 69, 114, 
    114, 111, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[3]; 
} const moonbit_string_literal_67 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 2), 
    92, 110, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[12]; 
} const moonbit_string_literal_20 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 11), 
    102, 105, 108, 101, 95, 114, 101, 97, 100, 101, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[13]; 
} const moonbit_string_literal_65 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 12), 
    44, 34, 101, 110, 100, 95, 108, 105, 110, 101, 34, 58, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[31]; 
} const moonbit_string_literal_50 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 30), 
    114, 97, 100, 105, 120, 32, 109, 117, 115, 116, 32, 98, 101, 32, 
    98, 101, 116, 119, 101, 101, 110, 32, 50, 32, 97, 110, 100, 32, 51, 
    54, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[20]; 
} const moonbit_string_literal_58 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 19), 
    44, 32, 34, 101, 120, 112, 101, 99, 116, 95, 98, 97, 115, 101, 54, 
    52, 34, 58, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[10]; 
} const moonbit_string_literal_49 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 9), 
    32, 70, 65, 73, 76, 69, 68, 58, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[66]; 
} const moonbit_string_literal_11 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 65), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 53, 52, 58, 51, 45, 53, 52, 58, 54, 54, 64, 104, 110, 108, 121, 
    120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 
    67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[2]; 
} const moonbit_string_literal_51 =
  { -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 1), 48, 0};

struct { int32_t rc; uint32_t meta; uint16_t const data[6]; 
} const moonbit_string_literal_45 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 5), 
    102, 97, 108, 115, 101, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[13]; 
} const moonbit_string_literal_62 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 12), 
    123, 34, 102, 105, 108, 101, 110, 97, 109, 101, 34, 58, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[24]; 
} const moonbit_string_literal_54 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 23), 
    64, 69, 88, 80, 69, 67, 84, 95, 70, 65, 73, 76, 69, 68, 32, 123, 
    34, 108, 111, 99, 34, 58, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[66]; 
} const moonbit_string_literal_13 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 65), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 52, 52, 58, 51, 45, 52, 52, 58, 53, 48, 64, 104, 110, 108, 121, 
    120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 
    67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[56]; 
} const moonbit_string_literal_72 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 55), 
    105, 110, 118, 97, 108, 105, 100, 32, 115, 116, 97, 114, 116, 32, 
    111, 114, 32, 101, 110, 100, 32, 105, 110, 100, 101, 120, 32, 102, 
    111, 114, 32, 83, 116, 114, 105, 110, 103, 58, 58, 99, 111, 100, 
    101, 112, 111, 105, 110, 116, 95, 108, 101, 110, 103, 116, 104, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[66]; 
} const moonbit_string_literal_14 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 65), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 52, 53, 58, 51, 45, 52, 53, 58, 54, 48, 64, 104, 110, 108, 121, 
    120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 
    67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[13]; 
} const moonbit_string_literal_57 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 12), 
    44, 32, 34, 97, 99, 116, 117, 97, 108, 34, 58, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[5]; 
} const moonbit_string_literal_61 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 4), 
    110, 117, 108, 108, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[13]; 
} const moonbit_string_literal_4 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 12), 
    44, 32, 34, 105, 110, 100, 101, 120, 34, 58, 32, 34, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[2]; 
} const moonbit_string_literal_75 =
  { -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 1), 41, 0};

struct { int32_t rc; uint32_t meta; uint16_t const data[66]; 
} const moonbit_string_literal_29 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 65), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 50, 52, 58, 55, 45, 50, 52, 58, 50, 57, 64, 104, 110, 108, 121, 
    120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 
    67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[5]; 
} const moonbit_string_literal_9 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 4), 
    116, 101, 115, 116, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[37]; 
} const moonbit_string_literal_52 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 36), 
    48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102, 
    103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 
    116, 117, 118, 119, 120, 121, 122, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[15]; 
} const moonbit_string_literal_21 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 14), 
    102, 105, 108, 101, 32, 110, 111, 116, 32, 102, 111, 117, 110, 100, 
    0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[67]; 
} const moonbit_string_literal_25 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 66), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 51, 55, 58, 49, 53, 45, 51, 55, 58, 49, 56, 64, 104, 110, 108, 
    121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 
    110, 67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[51]; 
} const moonbit_string_literal_82 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 50), 
    109, 111, 111, 110, 98, 105, 116, 108, 97, 110, 103, 47, 99, 111, 
    114, 101, 47, 98, 117, 105, 108, 116, 105, 110, 46, 73, 110, 115, 
    112, 101, 99, 116, 69, 114, 114, 111, 114, 46, 73, 110, 115, 112, 
    101, 99, 116, 69, 114, 114, 111, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[66]; 
} const moonbit_string_literal_24 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 65), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 51, 54, 58, 55, 45, 51, 54, 58, 52, 56, 64, 104, 110, 108, 121, 
    120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 
    67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[87]; 
} const moonbit_string_literal_83 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 86), 
    104, 110, 108, 121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 
    66, 79, 112, 101, 110, 67, 108, 97, 99, 107, 121, 47, 108, 105, 98, 
    47, 101, 114, 114, 111, 114, 115, 46, 66, 114, 111, 119, 115, 101, 
    114, 78, 111, 116, 82, 101, 97, 99, 104, 97, 98, 108, 101, 69, 114, 
    114, 111, 114, 46, 66, 114, 111, 119, 115, 101, 114, 78, 111, 116, 
    82, 101, 97, 99, 104, 97, 98, 108, 101, 69, 114, 114, 111, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[33]; 
} const moonbit_string_literal_8 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 32), 
    45, 45, 45, 45, 45, 32, 69, 78, 68, 32, 77, 79, 79, 78, 32, 84, 69, 
    83, 84, 32, 82, 69, 83, 85, 76, 84, 32, 45, 45, 45, 45, 45, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[15]; 
} const moonbit_string_literal_63 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 14), 
    44, 34, 115, 116, 97, 114, 116, 95, 108, 105, 110, 101, 34, 58, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[65]; 
} const moonbit_string_literal_39 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 64), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 53, 58, 53, 49, 45, 53, 58, 54, 55, 64, 104, 110, 108, 121, 120, 
    105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 67, 
    108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[67]; 
} const moonbit_string_literal_26 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 66), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 51, 55, 58, 50, 56, 45, 51, 55, 58, 52, 52, 64, 104, 110, 108, 
    121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 
    110, 67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[19]; 
} const moonbit_string_literal_92 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 18), 
    105, 115, 95, 114, 101, 116, 114, 121, 97, 98, 108, 101, 95, 101, 
    114, 114, 111, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[9]; 
} const moonbit_string_literal_74 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 8), 
    70, 97, 105, 108, 117, 114, 101, 40, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[17]; 
} const moonbit_string_literal_64 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 16), 
    44, 34, 115, 116, 97, 114, 116, 95, 99, 111, 108, 117, 109, 110, 
    34, 58, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[17]; 
} const moonbit_string_literal_5 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 16), 
    34, 44, 32, 34, 116, 101, 115, 116, 95, 110, 97, 109, 101, 34, 58, 
    32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[67]; 
} const moonbit_string_literal_31 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 66), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 50, 53, 58, 50, 56, 45, 50, 53, 58, 52, 53, 64, 104, 110, 108, 
    121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 
    110, 67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[2]; 
} const moonbit_string_literal_7 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 1), 125, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[14]; 
} const moonbit_string_literal_6 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 13), 
    44, 32, 34, 109, 101, 115, 115, 97, 103, 101, 34, 58, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[66]; 
} const moonbit_string_literal_27 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 65), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 51, 55, 58, 55, 45, 51, 55, 58, 52, 53, 64, 104, 110, 108, 121, 
    120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 
    67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[15]; 
} const moonbit_string_literal_55 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 14), 
    44, 32, 34, 97, 114, 103, 115, 95, 108, 111, 99, 34, 58, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[15]; 
} const moonbit_string_literal_43 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 14), 
    96, 32, 105, 115, 32, 110, 111, 116, 32, 102, 97, 108, 115, 101, 
    0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[35]; 
} const moonbit_string_literal_2 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 34), 
    45, 45, 45, 45, 45, 32, 66, 69, 71, 73, 78, 32, 77, 79, 79, 78, 32, 
    84, 69, 83, 84, 32, 82, 69, 83, 85, 76, 84, 32, 45, 45, 45, 45, 45, 
    0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[3]; 
} const moonbit_string_literal_70 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 2), 
    92, 116, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[3]; 
} const moonbit_string_literal_68 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 2), 
    92, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[14]; 
} const moonbit_string_literal_42 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 13), 
    96, 32, 105, 115, 32, 110, 111, 116, 32, 116, 114, 117, 101, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[15]; 
} const moonbit_string_literal_37 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 14), 
    117, 115, 101, 114, 32, 99, 97, 110, 99, 101, 108, 108, 101, 100, 
    0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[19]; 
} const moonbit_string_literal_73 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 18), 
    105, 110, 118, 97, 108, 105, 100, 32, 99, 111, 100, 101, 32, 112, 
    111, 105, 110, 116, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[59]; 
} const moonbit_string_literal_78 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 58), 
    104, 110, 108, 121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 
    66, 79, 112, 101, 110, 67, 108, 97, 99, 107, 121, 47, 108, 105, 98, 
    47, 101, 114, 114, 111, 114, 115, 46, 65, 103, 101, 110, 116, 69, 
    114, 114, 111, 114, 46, 65, 103, 101, 110, 116, 69, 114, 114, 111, 
    114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[13]; 
} const moonbit_string_literal_56 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 12), 
    44, 32, 34, 101, 120, 112, 101, 99, 116, 34, 58, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[66]; 
} const moonbit_string_literal_19 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 65), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 52, 57, 58, 51, 45, 52, 57, 58, 53, 55, 64, 104, 110, 108, 121, 
    120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 
    67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[67]; 
} const moonbit_string_literal_35 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 66), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 49, 52, 58, 52, 53, 45, 49, 52, 58, 54, 55, 64, 104, 110, 108, 
    121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 
    110, 67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[65]; 
} const moonbit_string_literal_38 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 64), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 53, 58, 51, 56, 45, 53, 58, 52, 49, 64, 104, 110, 108, 121, 120, 
    105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 67, 
    108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[5]; 
} const moonbit_string_literal_15 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 4), 
    116, 111, 111, 108, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[23]; 
} const moonbit_string_literal_47 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 22), 
    73, 110, 118, 97, 108, 105, 100, 32, 105, 110, 100, 101, 120, 32, 
    102, 111, 114, 32, 86, 105, 101, 119, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[105]; 
} const moonbit_string_literal_81 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 104), 
    104, 110, 108, 121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 
    66, 79, 112, 101, 110, 67, 108, 97, 99, 107, 121, 47, 108, 105, 98, 
    47, 101, 114, 114, 111, 114, 115, 46, 77, 111, 111, 110, 66, 105, 
    116, 84, 101, 115, 116, 68, 114, 105, 118, 101, 114, 73, 110, 116, 
    101, 114, 110, 97, 108, 83, 107, 105, 112, 84, 101, 115, 116, 46, 
    77, 111, 111, 110, 66, 105, 116, 84, 101, 115, 116, 68, 114, 105, 
    118, 101, 114, 73, 110, 116, 101, 114, 110, 97, 108, 83, 107, 105, 
    112, 84, 101, 115, 116, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[2]; 
} const moonbit_string_literal_41 =
  { -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 1), 96, 0};

struct { int32_t rc; uint32_t meta; uint16_t const data[16]; 
} const moonbit_string_literal_28 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 15), 
    105, 110, 118, 97, 108, 105, 100, 32, 114, 101, 113, 117, 101, 115, 
    116, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[18]; 
} const moonbit_string_literal_93 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 17), 
    101, 114, 114, 111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 
    109, 98, 116, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[4]; 
} const moonbit_string_literal_71 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 3), 
    92, 117, 123, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[28]; 
} const moonbit_string_literal_90 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 27), 
    116, 111, 111, 108, 95, 99, 97, 108, 108, 95, 101, 114, 114, 111, 
    114, 95, 114, 97, 105, 115, 101, 95, 99, 97, 116, 99, 104, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[15]; 
} const moonbit_string_literal_91 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 14), 
    105, 115, 95, 97, 103, 101, 110, 116, 95, 101, 114, 114, 111, 114, 
    0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[65]; 
} const moonbit_string_literal_40 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 64), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 53, 58, 51, 48, 45, 53, 58, 54, 56, 64, 104, 110, 108, 121, 120, 
    105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 67, 
    108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[5]; 
} const moonbit_string_literal_44 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 4), 
    116, 114, 117, 101, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[66]; 
} const moonbit_string_literal_18 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 65), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 52, 56, 58, 51, 45, 52, 56, 58, 53, 53, 64, 104, 110, 108, 121, 
    120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 
    67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[3]; 
} const moonbit_string_literal_69 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 2), 
    92, 98, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[20]; 
} const moonbit_string_literal_59 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 19), 
    44, 32, 34, 97, 99, 116, 117, 97, 108, 95, 98, 97, 115, 101, 54, 
    52, 34, 58, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[2]; 
} const moonbit_string_literal_53 =
  { -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 1), 34, 0};

struct { int32_t rc; uint32_t meta; uint16_t const data[66]; 
} const moonbit_string_literal_17 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 65), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 52, 55, 58, 51, 45, 52, 55, 58, 54, 52, 64, 104, 110, 108, 121, 
    120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 
    67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[30]; 
} const moonbit_string_literal_89 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 29), 
    98, 97, 100, 95, 114, 101, 113, 117, 101, 115, 116, 95, 101, 114, 
    114, 111, 114, 95, 114, 97, 105, 115, 101, 95, 99, 97, 116, 99, 104, 
    0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[15]; 
} const moonbit_string_literal_66 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 14), 
    44, 34, 101, 110, 100, 95, 99, 111, 108, 117, 109, 110, 34, 58, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[67]; 
} const moonbit_string_literal_34 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 66), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 49, 52, 58, 51, 50, 45, 49, 52, 58, 51, 53, 64, 104, 110, 108, 
    121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 
    110, 67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[67]; 
} const moonbit_string_literal_23 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 66), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 51, 54, 58, 51, 52, 45, 51, 54, 58, 52, 55, 64, 104, 110, 108, 
    121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 
    110, 67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[67]; 
} const moonbit_string_literal_36 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 66), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 49, 52, 58, 50, 52, 45, 49, 52, 58, 54, 56, 64, 104, 110, 108, 
    121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 
    110, 67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[67]; 
} const moonbit_string_literal_22 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 66), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 51, 54, 58, 49, 53, 45, 51, 54, 58, 50, 52, 64, 104, 110, 108, 
    121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 
    110, 67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[69]; 
} const moonbit_string_literal_84 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 68), 
    104, 110, 108, 121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 
    66, 79, 112, 101, 110, 67, 108, 97, 99, 107, 121, 47, 108, 105, 98, 
    47, 101, 114, 114, 111, 114, 115, 46, 66, 97, 100, 82, 101, 113, 
    117, 101, 115, 116, 69, 114, 114, 111, 114, 46, 66, 97, 100, 82, 
    101, 113, 117, 101, 115, 116, 69, 114, 114, 111, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[5]; 
} const moonbit_string_literal_48 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 4), 
    32, 33, 61, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[71]; 
} const moonbit_string_literal_86 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 70), 
    104, 110, 108, 121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 
    66, 79, 112, 101, 110, 67, 108, 97, 99, 107, 121, 47, 108, 105, 98, 
    47, 101, 114, 114, 111, 114, 115, 46, 65, 103, 101, 110, 116, 73, 
    110, 116, 101, 114, 114, 117, 112, 116, 101, 100, 46, 65, 103, 101, 
    110, 116, 73, 110, 116, 101, 114, 114, 117, 112, 116, 101, 100, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[67]; 
} const moonbit_string_literal_85 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 66), 
    104, 110, 108, 121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 
    66, 79, 112, 101, 110, 67, 108, 97, 99, 107, 121, 47, 108, 105, 98, 
    47, 101, 114, 114, 111, 114, 115, 46, 82, 101, 116, 114, 121, 97, 
    98, 108, 101, 69, 114, 114, 111, 114, 46, 82, 101, 116, 114, 121, 
    97, 98, 108, 101, 69, 114, 114, 111, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[21]; 
} const moonbit_string_literal_33 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 20), 
    115, 111, 109, 101, 116, 104, 105, 110, 103, 32, 119, 101, 110, 116, 
    32, 119, 114, 111, 110, 103, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[67]; 
} const moonbit_string_literal_30 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 66), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 50, 53, 58, 49, 53, 45, 50, 53, 58, 49, 56, 64, 104, 110, 108, 
    121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 
    110, 67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[66]; 
} const moonbit_string_literal_16 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 65), 
    108, 105, 98, 47, 101, 114, 114, 111, 114, 115, 47, 101, 114, 114, 
    111, 114, 115, 95, 119, 98, 116, 101, 115, 116, 46, 109, 98, 116, 
    58, 52, 54, 58, 51, 45, 52, 54, 58, 54, 49, 64, 104, 110, 108, 121, 
    120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 101, 110, 
    67, 108, 97, 99, 107, 121, 0
  };

struct { int32_t rc; uint32_t meta; uint8_t const data[65]; 
} const moonbit_bytes_literal_0 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 0, 64), 
    65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 
    82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 
    104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 
    117, 118, 119, 120, 121, 122, 48, 49, 50, 51, 52, 53, 54, 55, 56, 
    57, 43, 47, 0
  };

struct { int32_t rc; uint32_t meta; struct _M0TWRPC15error5ErrorEs data; 
} const _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors44moonbit__test__driver__internal__do__executeN17error__to__stringS796$closure =
  {
    -1, Moonbit_make_regular_object_header(2, 0, 0),
    _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors44moonbit__test__driver__internal__do__executeN17error__to__stringS796
  };

struct { int32_t rc; uint32_t meta; struct _M0TWEuQRPC15error5Error data; 
} const _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__4_2edyncall$closure =
  {
    -1, Moonbit_make_regular_object_header(2, 0, 0),
    _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__4_2edyncall
  };

struct { int32_t rc; uint32_t meta; struct _M0TWEuQRPC15error5Error data; 
} const _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__1_2edyncall$closure =
  {
    -1, Moonbit_make_regular_object_header(2, 0, 0),
    _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__1_2edyncall
  };

struct { int32_t rc; uint32_t meta; struct _M0TWEuQRPC15error5Error data; 
} const _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__3_2edyncall$closure =
  {
    -1, Moonbit_make_regular_object_header(2, 0, 0),
    _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__3_2edyncall
  };

struct { int32_t rc; uint32_t meta; struct _M0TWEuQRPC15error5Error data; 
} const _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__5_2edyncall$closure =
  {
    -1, Moonbit_make_regular_object_header(2, 0, 0),
    _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__5_2edyncall
  };

struct { int32_t rc; uint32_t meta; struct _M0TWEuQRPC15error5Error data; 
} const _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__2_2edyncall$closure =
  {
    -1, Moonbit_make_regular_object_header(2, 0, 0),
    _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__2_2edyncall
  };

struct { int32_t rc; uint32_t meta; struct _M0TWEuQRPC15error5Error data; 
} const _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__0_2edyncall$closure =
  {
    -1, Moonbit_make_regular_object_header(2, 0, 0),
    _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__0_2edyncall
  };

struct _M0TWEuQRPC15error5Error* _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__5_2eclo =
  (struct _M0TWEuQRPC15error5Error*)&_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__5_2edyncall$closure.data;

struct _M0TWEuQRPC15error5Error* _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__1_2eclo =
  (struct _M0TWEuQRPC15error5Error*)&_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__1_2edyncall$closure.data;

struct _M0TWEuQRPC15error5Error* _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__4_2eclo =
  (struct _M0TWEuQRPC15error5Error*)&_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__4_2edyncall$closure.data;

struct _M0TWEuQRPC15error5Error* _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__0_2eclo =
  (struct _M0TWEuQRPC15error5Error*)&_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__0_2edyncall$closure.data;

struct _M0TWEuQRPC15error5Error* _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__3_2eclo =
  (struct _M0TWEuQRPC15error5Error*)&_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__3_2edyncall$closure.data;

struct _M0TWEuQRPC15error5Error* _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__2_2eclo =
  (struct _M0TWEuQRPC15error5Error*)&_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__2_2edyncall$closure.data;

struct { int32_t rc; uint32_t meta; struct _M0BTPB6Logger data; 
} _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id$object =
  {
    -1,
    Moonbit_make_regular_object_header(sizeof(struct _M0BTPB6Logger) >> 2, 0, 0),
    {.$method_0 = _M0IPB13StringBuilderPB6Logger69write__string_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger,
       .$method_1 = _M0IP016_24default__implPB6Logger72write__substring_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLoggerGRPB13StringBuilderE,
       .$method_2 = _M0IPB13StringBuilderPB6Logger67write__view_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger,
       .$method_3 = _M0IPB13StringBuilderPB6Logger67write__char_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger}
  };

struct _M0BTPB6Logger* _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id =
  &_M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id$object.data;

struct { int32_t rc; uint32_t meta; struct _M0BTPB4Show data; 
} _M0FP079String_2eas___40moonbitlang_2fcore_2fbuiltin_2eShow_2estatic__method__table__id$object =
  {
    -1,
    Moonbit_make_regular_object_header(sizeof(struct _M0BTPB4Show) >> 2, 0, 0),
    {.$method_0 = _M0IPC16string6StringPB4Show60output_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eShow,
       .$method_1 = _M0IPC16string6StringPB4Show64to__string_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eShow}
  };

struct _M0BTPB4Show* _M0FP079String_2eas___40moonbitlang_2fcore_2fbuiltin_2eShow_2estatic__method__table__id =
  &_M0FP079String_2eas___40moonbitlang_2fcore_2fbuiltin_2eShow_2estatic__method__table__id$object.data;

moonbit_bytes_t _M0FPB14base64__encodeN6base64S1741 =
  (moonbit_bytes_t)moonbit_bytes_literal_0.data;

struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors48moonbit__test__driver__internal__no__args__tests;

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__2_2edyncall(
  struct _M0TWEuQRPC15error5Error* _M0L6_2aenvS1865
) {
  return _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__2();
}

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__3_2edyncall(
  struct _M0TWEuQRPC15error5Error* _M0L6_2aenvS1864
) {
  return _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__3();
}

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__0_2edyncall(
  struct _M0TWEuQRPC15error5Error* _M0L6_2aenvS1863
) {
  return _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__0();
}

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__4_2edyncall(
  struct _M0TWEuQRPC15error5Error* _M0L6_2aenvS1862
) {
  return _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__4();
}

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__1_2edyncall(
  struct _M0TWEuQRPC15error5Error* _M0L6_2aenvS1861
) {
  return _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__1();
}

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors57____test__6572726f72735f7762746573742e6d6274__5_2edyncall(
  struct _M0TWEuQRPC15error5Error* _M0L6_2aenvS1860
) {
  return _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__5();
}

int32_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors44moonbit__test__driver__internal__do__execute(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12async__testsS817,
  moonbit_string_t _M0L8filenameS792,
  int32_t _M0L5indexS795
) {
  struct _M0R115_24hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c787* _closure_2061;
  struct _M0TWssbEu* _M0L14handle__resultS787;
  struct _M0TWRPC15error5ErrorEs* _M0L17error__to__stringS796;
  void* _M0L11_2atry__errS811;
  struct moonbit_result_0 _tmp_2063;
  int32_t _handle__error__result_2064;
  int32_t _M0L6_2atmpS1848;
  void* _M0L3errS812;
  moonbit_string_t _M0L4nameS814;
  struct _M0DTPC15error5Error114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest* _M0L36_2aMoonBitTestDriverInternalSkipTestS815;
  moonbit_string_t _M0L8_2afieldS1866;
  int32_t _M0L6_2acntS1997;
  moonbit_string_t _M0L7_2anameS816;
  #line 529 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  moonbit_incref(_M0L8filenameS792);
  _closure_2061
  = (struct _M0R115_24hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c787*)moonbit_malloc(sizeof(struct _M0R115_24hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c787));
  Moonbit_object_header(_closure_2061)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0R115_24hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c787, $1) >> 2, 1, 0);
  _closure_2061->code
  = &_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors44moonbit__test__driver__internal__do__executeN14handle__resultS787;
  _closure_2061->$0 = _M0L5indexS795;
  _closure_2061->$1 = _M0L8filenameS792;
  _M0L14handle__resultS787 = (struct _M0TWssbEu*)_closure_2061;
  _M0L17error__to__stringS796
  = (struct _M0TWRPC15error5ErrorEs*)&_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors44moonbit__test__driver__internal__do__executeN17error__to__stringS796$closure.data;
  moonbit_incref(_M0L12async__testsS817);
  moonbit_incref(_M0L17error__to__stringS796);
  moonbit_incref(_M0L8filenameS792);
  moonbit_incref(_M0L14handle__resultS787);
  #line 563 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _tmp_2063
  = _M0IP412hnlyxiaobing12MBOpenClacky3lib6errors41MoonBit__Test__Driver__Internal__No__ArgsP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__test(_M0L12async__testsS817, _M0L8filenameS792, _M0L5indexS795, _M0L14handle__resultS787, _M0L17error__to__stringS796);
  if (_tmp_2063.tag) {
    int32_t const _M0L5_2aokS1857 = _tmp_2063.data.ok;
    _handle__error__result_2064 = _M0L5_2aokS1857;
  } else {
    void* const _M0L6_2aerrS1858 = _tmp_2063.data.err;
    moonbit_decref(_M0L12async__testsS817);
    moonbit_decref(_M0L17error__to__stringS796);
    moonbit_decref(_M0L8filenameS792);
    _M0L11_2atry__errS811 = _M0L6_2aerrS1858;
    goto join_810;
  }
  if (_handle__error__result_2064) {
    moonbit_decref(_M0L12async__testsS817);
    moonbit_decref(_M0L17error__to__stringS796);
    moonbit_decref(_M0L8filenameS792);
    _M0L6_2atmpS1848 = 1;
  } else {
    struct moonbit_result_0 _tmp_2065;
    int32_t _handle__error__result_2066;
    moonbit_incref(_M0L12async__testsS817);
    moonbit_incref(_M0L17error__to__stringS796);
    moonbit_incref(_M0L8filenameS792);
    moonbit_incref(_M0L14handle__resultS787);
    #line 566 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
    _tmp_2065
    = _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testGRP412hnlyxiaobing12MBOpenClacky3lib6errors43MoonBit__Test__Driver__Internal__With__ArgsE(_M0L12async__testsS817, _M0L8filenameS792, _M0L5indexS795, _M0L14handle__resultS787, _M0L17error__to__stringS796);
    if (_tmp_2065.tag) {
      int32_t const _M0L5_2aokS1855 = _tmp_2065.data.ok;
      _handle__error__result_2066 = _M0L5_2aokS1855;
    } else {
      void* const _M0L6_2aerrS1856 = _tmp_2065.data.err;
      moonbit_decref(_M0L12async__testsS817);
      moonbit_decref(_M0L17error__to__stringS796);
      moonbit_decref(_M0L8filenameS792);
      _M0L11_2atry__errS811 = _M0L6_2aerrS1856;
      goto join_810;
    }
    if (_handle__error__result_2066) {
      moonbit_decref(_M0L12async__testsS817);
      moonbit_decref(_M0L17error__to__stringS796);
      moonbit_decref(_M0L8filenameS792);
      _M0L6_2atmpS1848 = 1;
    } else {
      struct moonbit_result_0 _tmp_2067;
      int32_t _handle__error__result_2068;
      moonbit_incref(_M0L12async__testsS817);
      moonbit_incref(_M0L17error__to__stringS796);
      moonbit_incref(_M0L8filenameS792);
      moonbit_incref(_M0L14handle__resultS787);
      #line 569 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
      _tmp_2067
      = _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testGRP412hnlyxiaobing12MBOpenClacky3lib6errors48MoonBit__Test__Driver__Internal__Async__No__ArgsE(_M0L12async__testsS817, _M0L8filenameS792, _M0L5indexS795, _M0L14handle__resultS787, _M0L17error__to__stringS796);
      if (_tmp_2067.tag) {
        int32_t const _M0L5_2aokS1853 = _tmp_2067.data.ok;
        _handle__error__result_2068 = _M0L5_2aokS1853;
      } else {
        void* const _M0L6_2aerrS1854 = _tmp_2067.data.err;
        moonbit_decref(_M0L12async__testsS817);
        moonbit_decref(_M0L17error__to__stringS796);
        moonbit_decref(_M0L8filenameS792);
        _M0L11_2atry__errS811 = _M0L6_2aerrS1854;
        goto join_810;
      }
      if (_handle__error__result_2068) {
        moonbit_decref(_M0L12async__testsS817);
        moonbit_decref(_M0L17error__to__stringS796);
        moonbit_decref(_M0L8filenameS792);
        _M0L6_2atmpS1848 = 1;
      } else {
        struct moonbit_result_0 _tmp_2069;
        int32_t _handle__error__result_2070;
        moonbit_incref(_M0L12async__testsS817);
        moonbit_incref(_M0L17error__to__stringS796);
        moonbit_incref(_M0L8filenameS792);
        moonbit_incref(_M0L14handle__resultS787);
        #line 572 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
        _tmp_2069
        = _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testGRP412hnlyxiaobing12MBOpenClacky3lib6errors50MoonBit__Test__Driver__Internal__Async__With__ArgsE(_M0L12async__testsS817, _M0L8filenameS792, _M0L5indexS795, _M0L14handle__resultS787, _M0L17error__to__stringS796);
        if (_tmp_2069.tag) {
          int32_t const _M0L5_2aokS1851 = _tmp_2069.data.ok;
          _handle__error__result_2070 = _M0L5_2aokS1851;
        } else {
          void* const _M0L6_2aerrS1852 = _tmp_2069.data.err;
          moonbit_decref(_M0L12async__testsS817);
          moonbit_decref(_M0L17error__to__stringS796);
          moonbit_decref(_M0L8filenameS792);
          _M0L11_2atry__errS811 = _M0L6_2aerrS1852;
          goto join_810;
        }
        if (_handle__error__result_2070) {
          moonbit_decref(_M0L12async__testsS817);
          moonbit_decref(_M0L17error__to__stringS796);
          moonbit_decref(_M0L8filenameS792);
          _M0L6_2atmpS1848 = 1;
        } else {
          struct moonbit_result_0 _tmp_2071;
          moonbit_incref(_M0L14handle__resultS787);
          #line 575 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
          _tmp_2071
          = _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testGRP412hnlyxiaobing12MBOpenClacky3lib6errors50MoonBit__Test__Driver__Internal__With__Bench__ArgsE(_M0L12async__testsS817, _M0L8filenameS792, _M0L5indexS795, _M0L14handle__resultS787, _M0L17error__to__stringS796);
          if (_tmp_2071.tag) {
            int32_t const _M0L5_2aokS1849 = _tmp_2071.data.ok;
            _M0L6_2atmpS1848 = _M0L5_2aokS1849;
          } else {
            void* const _M0L6_2aerrS1850 = _tmp_2071.data.err;
            _M0L11_2atry__errS811 = _M0L6_2aerrS1850;
            goto join_810;
          }
        }
      }
    }
  }
  if (!_M0L6_2atmpS1848) {
    void* _M0L114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTestS1859 =
      (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest));
    Moonbit_object_header(_M0L114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTestS1859)->meta
    = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest, $0) >> 2, 1, 9);
    ((struct _M0DTPC15error5Error114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest*)_M0L114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTestS1859)->$0
    = (moonbit_string_t)moonbit_string_literal_0.data;
    _M0L11_2atry__errS811
    = _M0L114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTestS1859;
    goto join_810;
  } else {
    moonbit_decref(_M0L14handle__resultS787);
  }
  goto joinlet_2062;
  join_810:;
  _M0L3errS812 = _M0L11_2atry__errS811;
  _M0L36_2aMoonBitTestDriverInternalSkipTestS815
  = (struct _M0DTPC15error5Error114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest*)_M0L3errS812;
  _M0L8_2afieldS1866 = _M0L36_2aMoonBitTestDriverInternalSkipTestS815->$0;
  _M0L6_2acntS1997
  = Moonbit_object_header(_M0L36_2aMoonBitTestDriverInternalSkipTestS815)->rc;
  if (_M0L6_2acntS1997 > 1) {
    int32_t _M0L11_2anew__cntS1998 = _M0L6_2acntS1997 - 1;
    Moonbit_object_header(_M0L36_2aMoonBitTestDriverInternalSkipTestS815)->rc
    = _M0L11_2anew__cntS1998;
    moonbit_incref(_M0L8_2afieldS1866);
  } else if (_M0L6_2acntS1997 == 1) {
    #line 582 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
    moonbit_free(_M0L36_2aMoonBitTestDriverInternalSkipTestS815);
  }
  _M0L7_2anameS816 = _M0L8_2afieldS1866;
  _M0L4nameS814 = _M0L7_2anameS816;
  goto join_813;
  goto joinlet_2072;
  join_813:;
  #line 583 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors44moonbit__test__driver__internal__do__executeN14handle__resultS787(_M0L14handle__resultS787, _M0L4nameS814, (moonbit_string_t)moonbit_string_literal_1.data, 1);
  joinlet_2072:;
  joinlet_2062:;
  return 0;
}

moonbit_string_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors44moonbit__test__driver__internal__do__executeN17error__to__stringS796(
  struct _M0TWRPC15error5ErrorEs* _M0L6_2aenvS1847,
  void* _M0L3errS797
) {
  void* _M0L1eS799;
  moonbit_string_t _M0L1eS801;
  #line 552 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  moonbit_decref(_M0L6_2aenvS1847);
  switch (Moonbit_object_tag(_M0L3errS797)) {
    case 0: {
      struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure* _M0L10_2aFailureS802 =
        (struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure*)_M0L3errS797;
      moonbit_string_t _M0L8_2afieldS1867 = _M0L10_2aFailureS802->$0;
      int32_t _M0L6_2acntS1999 =
        Moonbit_object_header(_M0L10_2aFailureS802)->rc;
      moonbit_string_t _M0L4_2aeS803;
      if (_M0L6_2acntS1999 > 1) {
        int32_t _M0L11_2anew__cntS2000 = _M0L6_2acntS1999 - 1;
        Moonbit_object_header(_M0L10_2aFailureS802)->rc
        = _M0L11_2anew__cntS2000;
        moonbit_incref(_M0L8_2afieldS1867);
      } else if (_M0L6_2acntS1999 == 1) {
        #line 553 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
        moonbit_free(_M0L10_2aFailureS802);
      }
      _M0L4_2aeS803 = _M0L8_2afieldS1867;
      _M0L1eS801 = _M0L4_2aeS803;
      goto join_800;
      break;
    }
    
    case 1: {
      struct _M0DTPC15error5Error58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectError* _M0L15_2aInspectErrorS804 =
        (struct _M0DTPC15error5Error58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectError*)_M0L3errS797;
      moonbit_string_t _M0L8_2afieldS1868 = _M0L15_2aInspectErrorS804->$0;
      int32_t _M0L6_2acntS2001 =
        Moonbit_object_header(_M0L15_2aInspectErrorS804)->rc;
      moonbit_string_t _M0L4_2aeS805;
      if (_M0L6_2acntS2001 > 1) {
        int32_t _M0L11_2anew__cntS2002 = _M0L6_2acntS2001 - 1;
        Moonbit_object_header(_M0L15_2aInspectErrorS804)->rc
        = _M0L11_2anew__cntS2002;
        moonbit_incref(_M0L8_2afieldS1868);
      } else if (_M0L6_2acntS2001 == 1) {
        #line 553 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
        moonbit_free(_M0L15_2aInspectErrorS804);
      }
      _M0L4_2aeS805 = _M0L8_2afieldS1868;
      _M0L1eS801 = _M0L4_2aeS805;
      goto join_800;
      break;
    }
    
    case 10: {
      struct _M0DTPC15error5Error60moonbitlang_2fcore_2fbuiltin_2eSnapshotError_2eSnapshotError* _M0L16_2aSnapshotErrorS806 =
        (struct _M0DTPC15error5Error60moonbitlang_2fcore_2fbuiltin_2eSnapshotError_2eSnapshotError*)_M0L3errS797;
      moonbit_string_t _M0L8_2afieldS1869 = _M0L16_2aSnapshotErrorS806->$0;
      int32_t _M0L6_2acntS2003 =
        Moonbit_object_header(_M0L16_2aSnapshotErrorS806)->rc;
      moonbit_string_t _M0L4_2aeS807;
      if (_M0L6_2acntS2003 > 1) {
        int32_t _M0L11_2anew__cntS2004 = _M0L6_2acntS2003 - 1;
        Moonbit_object_header(_M0L16_2aSnapshotErrorS806)->rc
        = _M0L11_2anew__cntS2004;
        moonbit_incref(_M0L8_2afieldS1869);
      } else if (_M0L6_2acntS2003 == 1) {
        #line 553 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
        moonbit_free(_M0L16_2aSnapshotErrorS806);
      }
      _M0L4_2aeS807 = _M0L8_2afieldS1869;
      _M0L1eS801 = _M0L4_2aeS807;
      goto join_800;
      break;
    }
    
    case 11: {
      struct _M0DTPC15error5Error112hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalJsError_2eMoonBitTestDriverInternalJsError* _M0L35_2aMoonBitTestDriverInternalJsErrorS808 =
        (struct _M0DTPC15error5Error112hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalJsError_2eMoonBitTestDriverInternalJsError*)_M0L3errS797;
      moonbit_string_t _M0L8_2afieldS1870 =
        _M0L35_2aMoonBitTestDriverInternalJsErrorS808->$0;
      int32_t _M0L6_2acntS2005 =
        Moonbit_object_header(_M0L35_2aMoonBitTestDriverInternalJsErrorS808)->rc;
      moonbit_string_t _M0L4_2aeS809;
      if (_M0L6_2acntS2005 > 1) {
        int32_t _M0L11_2anew__cntS2006 = _M0L6_2acntS2005 - 1;
        Moonbit_object_header(_M0L35_2aMoonBitTestDriverInternalJsErrorS808)->rc
        = _M0L11_2anew__cntS2006;
        moonbit_incref(_M0L8_2afieldS1870);
      } else if (_M0L6_2acntS2005 == 1) {
        #line 553 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
        moonbit_free(_M0L35_2aMoonBitTestDriverInternalJsErrorS808);
      }
      _M0L4_2aeS809 = _M0L8_2afieldS1870;
      _M0L1eS801 = _M0L4_2aeS809;
      goto join_800;
      break;
    }
    default: {
      _M0L1eS799 = _M0L3errS797;
      goto join_798;
      break;
    }
  }
  join_800:;
  return _M0L1eS801;
  join_798:;
  #line 558 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  return _M0FP15Error10to__string(_M0L1eS799);
}

int32_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors44moonbit__test__driver__internal__do__executeN14handle__resultS787(
  struct _M0TWssbEu* _M0L6_2aenvS1833,
  moonbit_string_t _M0L8testnameS788,
  moonbit_string_t _M0L7messageS789,
  int32_t _M0L7skippedS790
) {
  struct _M0R115_24hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c787* _M0L14_2acasted__envS1834;
  moonbit_string_t _M0L8filenameS792;
  int32_t _M0L5indexS795;
  int32_t _M0L6_2acntS2007;
  int32_t _if__result_2075;
  moonbit_string_t _M0L10file__nameS791;
  moonbit_string_t _M0L10test__nameS793;
  moonbit_string_t _M0L7messageS794;
  moonbit_string_t _M0L6_2atmpS1846;
  moonbit_string_t _M0L6_2atmpS1845;
  moonbit_string_t _M0L6_2atmpS1843;
  moonbit_string_t _M0L6_2atmpS1844;
  moonbit_string_t _M0L6_2atmpS1842;
  moonbit_string_t _M0L6_2atmpS1840;
  moonbit_string_t _M0L6_2atmpS1841;
  moonbit_string_t _M0L6_2atmpS1839;
  moonbit_string_t _M0L6_2atmpS1837;
  moonbit_string_t _M0L6_2atmpS1838;
  moonbit_string_t _M0L6_2atmpS1836;
  moonbit_string_t _M0L6_2atmpS1835;
  #line 536 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L14_2acasted__envS1834
  = (struct _M0R115_24hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c787*)_M0L6_2aenvS1833;
  _M0L8filenameS792 = _M0L14_2acasted__envS1834->$1;
  _M0L5indexS795 = _M0L14_2acasted__envS1834->$0;
  _M0L6_2acntS2007 = Moonbit_object_header(_M0L14_2acasted__envS1834)->rc;
  if (_M0L6_2acntS2007 > 1) {
    int32_t _M0L11_2anew__cntS2008 = _M0L6_2acntS2007 - 1;
    Moonbit_object_header(_M0L14_2acasted__envS1834)->rc
    = _M0L11_2anew__cntS2008;
    moonbit_incref(_M0L8filenameS792);
  } else if (_M0L6_2acntS2007 == 1) {
    #line 536 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
    moonbit_free(_M0L14_2acasted__envS1834);
  }
  if (!_M0L7skippedS790) {
    _if__result_2075 = 1;
  } else {
    _if__result_2075 = 0;
  }
  if (_if__result_2075) {
    
  }
  #line 542 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L10file__nameS791
  = _M0MPC16string6String14escape_2einner(_M0L8filenameS792, 1);
  #line 543 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L10test__nameS793
  = _M0MPC16string6String14escape_2einner(_M0L8testnameS788, 1);
  #line 544 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L7messageS794
  = _M0MPC16string6String14escape_2einner(_M0L7messageS789, 1);
  #line 545 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_2.data);
  #line 547 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1846
  = _M0IPC16string6StringPB4Show10to__string(_M0L10file__nameS791);
  #line 546 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1845
  = moonbit_add_string((moonbit_string_t)moonbit_string_literal_3.data, _M0L6_2atmpS1846);
  moonbit_decref(_M0L6_2atmpS1846);
  #line 546 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1843
  = moonbit_add_string(_M0L6_2atmpS1845, (moonbit_string_t)moonbit_string_literal_4.data);
  moonbit_decref(_M0L6_2atmpS1845);
  #line 547 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1844 = _M0IPC13int3IntPB4Show10to__string(_M0L5indexS795);
  #line 546 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1842 = moonbit_add_string(_M0L6_2atmpS1843, _M0L6_2atmpS1844);
  moonbit_decref(_M0L6_2atmpS1844);
  moonbit_decref(_M0L6_2atmpS1843);
  #line 546 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1840
  = moonbit_add_string(_M0L6_2atmpS1842, (moonbit_string_t)moonbit_string_literal_5.data);
  moonbit_decref(_M0L6_2atmpS1842);
  #line 547 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1841
  = _M0IPC16string6StringPB4Show10to__string(_M0L10test__nameS793);
  #line 546 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1839 = moonbit_add_string(_M0L6_2atmpS1840, _M0L6_2atmpS1841);
  moonbit_decref(_M0L6_2atmpS1841);
  moonbit_decref(_M0L6_2atmpS1840);
  #line 546 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1837
  = moonbit_add_string(_M0L6_2atmpS1839, (moonbit_string_t)moonbit_string_literal_6.data);
  moonbit_decref(_M0L6_2atmpS1839);
  #line 547 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1838
  = _M0IPC16string6StringPB4Show10to__string(_M0L7messageS794);
  #line 546 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1836 = moonbit_add_string(_M0L6_2atmpS1837, _M0L6_2atmpS1838);
  moonbit_decref(_M0L6_2atmpS1838);
  moonbit_decref(_M0L6_2atmpS1837);
  #line 546 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1835
  = moonbit_add_string(_M0L6_2atmpS1836, (moonbit_string_t)moonbit_string_literal_7.data);
  moonbit_decref(_M0L6_2atmpS1836);
  #line 546 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0FPB7printlnGsE(_M0L6_2atmpS1835);
  #line 549 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_8.data);
  return 0;
}

struct moonbit_result_0 _M0IP412hnlyxiaobing12MBOpenClacky3lib6errors41MoonBit__Test__Driver__Internal__No__ArgsP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__test(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12_2adiscard__S786,
  moonbit_string_t _M0L8filenameS783,
  int32_t _M0L5indexS777,
  struct _M0TWssbEu* _M0L14handle__resultS773,
  struct _M0TWRPC15error5ErrorEs* _M0L17error__to__stringS775
) {
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L10index__mapS753;
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L7_2abindS782;
  struct _M0TWEuQRPC15error5Error* _M0L1fS755;
  moonbit_string_t* _M0L5attrsS756;
  struct _M0TUWEuQRPC15error5ErrorNsE* _M0L7_2abindS776;
  moonbit_string_t _M0L4nameS759;
  moonbit_string_t _M0L4nameS757;
  int32_t _M0L6_2atmpS1832;
  struct _M0TWEOs* _M0L5_2aitS761;
  struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1829__l430__* _closure_2084;
  struct _M0TWEu* _M0L6_2atmpS1823;
  struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1825__l431__* _closure_2085;
  struct _M0TWRPC15error5ErrorEu* _M0L6_2atmpS1824;
  struct moonbit_result_0 _result_2086;
  #line 410 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  moonbit_decref(_M0L12_2adiscard__S786);
  moonbit_incref(_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors48moonbit__test__driver__internal__no__args__tests);
  #line 417 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L7_2abindS782
  = _M0MPB3Map3getGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors48moonbit__test__driver__internal__no__args__tests, _M0L8filenameS783);
  if (_M0L7_2abindS782 == 0) {
    struct moonbit_result_0 _result_2077;
    if (_M0L7_2abindS782) {
      moonbit_decref(_M0L7_2abindS782);
    }
    moonbit_decref(_M0L17error__to__stringS775);
    moonbit_decref(_M0L14handle__resultS773);
    _result_2077.tag = 1;
    _result_2077.data.ok = 0;
    return _result_2077;
  } else {
    struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L7_2aSomeS784 =
      _M0L7_2abindS782;
    struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L13_2aindex__mapS785 =
      _M0L7_2aSomeS784;
    _M0L10index__mapS753 = _M0L13_2aindex__mapS785;
    goto join_752;
  }
  join_752:;
  #line 419 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L7_2abindS776
  = _M0MPB3Map3getGiUWEuQRPC15error5ErrorNsEE(_M0L10index__mapS753, _M0L5indexS777);
  if (_M0L7_2abindS776 == 0) {
    struct moonbit_result_0 _result_2079;
    if (_M0L7_2abindS776) {
      moonbit_decref(_M0L7_2abindS776);
    }
    moonbit_decref(_M0L17error__to__stringS775);
    moonbit_decref(_M0L14handle__resultS773);
    _result_2079.tag = 1;
    _result_2079.data.ok = 0;
    return _result_2079;
  } else {
    struct _M0TUWEuQRPC15error5ErrorNsE* _M0L7_2aSomeS778 = _M0L7_2abindS776;
    struct _M0TUWEuQRPC15error5ErrorNsE* _M0L4_2axS779 = _M0L7_2aSomeS778;
    struct _M0TWEuQRPC15error5Error* _M0L4_2afS780 = _M0L4_2axS779->$0;
    moonbit_string_t* _M0L8_2afieldS1873 = _M0L4_2axS779->$1;
    int32_t _M0L6_2acntS2009 = Moonbit_object_header(_M0L4_2axS779)->rc;
    moonbit_string_t* _M0L8_2aattrsS781;
    if (_M0L6_2acntS2009 > 1) {
      int32_t _M0L11_2anew__cntS2010 = _M0L6_2acntS2009 - 1;
      Moonbit_object_header(_M0L4_2axS779)->rc = _M0L11_2anew__cntS2010;
      moonbit_incref(_M0L8_2afieldS1873);
      moonbit_incref(_M0L4_2afS780);
    } else if (_M0L6_2acntS2009 == 1) {
      #line 417 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
      moonbit_free(_M0L4_2axS779);
    }
    _M0L8_2aattrsS781 = _M0L8_2afieldS1873;
    _M0L1fS755 = _M0L4_2afS780;
    _M0L5attrsS756 = _M0L8_2aattrsS781;
    goto join_754;
  }
  join_754:;
  _M0L6_2atmpS1832 = Moonbit_array_length(_M0L5attrsS756);
  if (_M0L6_2atmpS1832 >= 1) {
    moonbit_string_t _M0L7_2anameS760 = (moonbit_string_t)_M0L5attrsS756[0];
    moonbit_incref(_M0L7_2anameS760);
    _M0L4nameS759 = _M0L7_2anameS760;
    goto join_758;
  } else {
    _M0L4nameS757 = (moonbit_string_t)moonbit_string_literal_0.data;
  }
  goto joinlet_2080;
  join_758:;
  _M0L4nameS757 = _M0L4nameS759;
  joinlet_2080:;
  #line 420 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L5_2aitS761 = _M0MPC15array13ReadOnlyArray4iterGsE(_M0L5attrsS756);
  while (1) {
    moonbit_string_t _M0L4attrS763;
    moonbit_string_t _M0L7_2abindS770;
    int32_t _M0L6_2atmpS1816;
    int64_t _M0L6_2atmpS1815;
    moonbit_incref(_M0L5_2aitS761);
    #line 422 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
    _M0L7_2abindS770 = _M0MPB4Iter4nextGsE(_M0L5_2aitS761);
    if (_M0L7_2abindS770 == 0) {
      if (_M0L7_2abindS770) {
        moonbit_decref(_M0L7_2abindS770);
      }
      moonbit_decref(_M0L5_2aitS761);
    } else {
      moonbit_string_t _M0L7_2aSomeS771 = _M0L7_2abindS770;
      moonbit_string_t _M0L7_2aattrS772 = _M0L7_2aSomeS771;
      _M0L4attrS763 = _M0L7_2aattrS772;
      goto join_762;
    }
    goto joinlet_2082;
    join_762:;
    _M0L6_2atmpS1816 = Moonbit_array_length(_M0L4attrS763);
    _M0L6_2atmpS1815 = (int64_t)_M0L6_2atmpS1816;
    moonbit_incref(_M0L4attrS763);
    #line 423 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
    if (
      _M0MPC16string6String24char__length__ge_2einner(_M0L4attrS763, 5, 0, _M0L6_2atmpS1815)
    ) {
      int32_t _M0L6_2atmpS1822 = _M0L4attrS763[0];
      int32_t _M0L4_2axS764 = _M0L6_2atmpS1822;
      if (_M0L4_2axS764 == 112) {
        int32_t _M0L6_2atmpS1821 = _M0L4attrS763[1];
        int32_t _M0L4_2axS765 = _M0L6_2atmpS1821;
        if (_M0L4_2axS765 == 97) {
          int32_t _M0L6_2atmpS1820 = _M0L4attrS763[2];
          int32_t _M0L4_2axS766 = _M0L6_2atmpS1820;
          if (_M0L4_2axS766 == 110) {
            int32_t _M0L6_2atmpS1819 = _M0L4attrS763[3];
            int32_t _M0L4_2axS767 = _M0L6_2atmpS1819;
            if (_M0L4_2axS767 == 105) {
              int32_t _M0L6_2atmpS1818 = _M0L4attrS763[4];
              int32_t _M0L4_2axS768;
              moonbit_decref(_M0L4attrS763);
              _M0L4_2axS768 = _M0L6_2atmpS1818;
              if (_M0L4_2axS768 == 99) {
                void* _M0L114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTestS1817;
                struct moonbit_result_0 _result_2083;
                moonbit_decref(_M0L17error__to__stringS775);
                moonbit_decref(_M0L14handle__resultS773);
                moonbit_decref(_M0L5_2aitS761);
                moonbit_decref(_M0L1fS755);
                _M0L114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTestS1817
                = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest));
                Moonbit_object_header(_M0L114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTestS1817)->meta
                = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest, $0) >> 2, 1, 9);
                ((struct _M0DTPC15error5Error114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest*)_M0L114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTestS1817)->$0
                = _M0L4nameS757;
                _result_2083.tag = 0;
                _result_2083.data.err
                = _M0L114hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTestS1817;
                return _result_2083;
              }
            } else {
              moonbit_decref(_M0L4attrS763);
            }
          } else {
            moonbit_decref(_M0L4attrS763);
          }
        } else {
          moonbit_decref(_M0L4attrS763);
        }
      } else {
        moonbit_decref(_M0L4attrS763);
      }
    } else {
      moonbit_decref(_M0L4attrS763);
    }
    continue;
    joinlet_2082:;
    break;
  }
  moonbit_incref(_M0L14handle__resultS773);
  moonbit_incref(_M0L4nameS757);
  _closure_2084
  = (struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1829__l430__*)moonbit_malloc(sizeof(struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1829__l430__));
  Moonbit_object_header(_closure_2084)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1829__l430__, $0) >> 2, 2, 0);
  _closure_2084->code
  = &_M0IP412hnlyxiaobing12MBOpenClacky3lib6errors41MoonBit__Test__Driver__Internal__No__ArgsP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testC1829l430;
  _closure_2084->$0 = _M0L14handle__resultS773;
  _closure_2084->$1 = _M0L4nameS757;
  _M0L6_2atmpS1823 = (struct _M0TWEu*)_closure_2084;
  _closure_2085
  = (struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1825__l431__*)moonbit_malloc(sizeof(struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1825__l431__));
  Moonbit_object_header(_closure_2085)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1825__l431__, $0) >> 2, 3, 0);
  _closure_2085->code
  = &_M0IP412hnlyxiaobing12MBOpenClacky3lib6errors41MoonBit__Test__Driver__Internal__No__ArgsP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testC1825l431;
  _closure_2085->$0 = _M0L17error__to__stringS775;
  _closure_2085->$1 = _M0L14handle__resultS773;
  _closure_2085->$2 = _M0L4nameS757;
  _M0L6_2atmpS1824 = (struct _M0TWRPC15error5ErrorEu*)_closure_2085;
  #line 428 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors45moonbit__test__driver__internal__catch__error(_M0L1fS755, _M0L6_2atmpS1823, _M0L6_2atmpS1824);
  _result_2086.tag = 1;
  _result_2086.data.ok = 1;
  return _result_2086;
}

int32_t _M0IP412hnlyxiaobing12MBOpenClacky3lib6errors41MoonBit__Test__Driver__Internal__No__ArgsP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testC1829l430(
  struct _M0TWEu* _M0L6_2aenvS1830
) {
  struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1829__l430__* _M0L14_2acasted__envS1831;
  moonbit_string_t _M0L4nameS757;
  struct _M0TWssbEu* _M0L8_2afieldS1875;
  int32_t _M0L6_2acntS2011;
  struct _M0TWssbEu* _M0L14handle__resultS773;
  #line 430 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L14_2acasted__envS1831
  = (struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1829__l430__*)_M0L6_2aenvS1830;
  _M0L4nameS757 = _M0L14_2acasted__envS1831->$1;
  _M0L8_2afieldS1875 = _M0L14_2acasted__envS1831->$0;
  _M0L6_2acntS2011 = Moonbit_object_header(_M0L14_2acasted__envS1831)->rc;
  if (_M0L6_2acntS2011 > 1) {
    int32_t _M0L11_2anew__cntS2012 = _M0L6_2acntS2011 - 1;
    Moonbit_object_header(_M0L14_2acasted__envS1831)->rc
    = _M0L11_2anew__cntS2012;
    moonbit_incref(_M0L4nameS757);
    moonbit_incref(_M0L8_2afieldS1875);
  } else if (_M0L6_2acntS2011 == 1) {
    #line 430 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
    moonbit_free(_M0L14_2acasted__envS1831);
  }
  _M0L14handle__resultS773 = _M0L8_2afieldS1875;
  #line 430 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L14handle__resultS773->code(_M0L14handle__resultS773, _M0L4nameS757, (moonbit_string_t)moonbit_string_literal_0.data, 0);
  return 0;
}

int32_t _M0IP412hnlyxiaobing12MBOpenClacky3lib6errors41MoonBit__Test__Driver__Internal__No__ArgsP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testC1825l431(
  struct _M0TWRPC15error5ErrorEu* _M0L6_2aenvS1826,
  void* _M0L3errS774
) {
  struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1825__l431__* _M0L14_2acasted__envS1827;
  moonbit_string_t _M0L4nameS757;
  struct _M0TWssbEu* _M0L14handle__resultS773;
  struct _M0TWRPC15error5ErrorEs* _M0L8_2afieldS1877;
  int32_t _M0L6_2acntS2013;
  struct _M0TWRPC15error5ErrorEs* _M0L17error__to__stringS775;
  moonbit_string_t _M0L6_2atmpS1828;
  #line 431 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L14_2acasted__envS1827
  = (struct _M0R201_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver_3a_3arun__test_7c_40hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eMoonBit__Test__Driver__Internal__No__Args_7c_2eanon__u1825__l431__*)_M0L6_2aenvS1826;
  _M0L4nameS757 = _M0L14_2acasted__envS1827->$2;
  _M0L14handle__resultS773 = _M0L14_2acasted__envS1827->$1;
  _M0L8_2afieldS1877 = _M0L14_2acasted__envS1827->$0;
  _M0L6_2acntS2013 = Moonbit_object_header(_M0L14_2acasted__envS1827)->rc;
  if (_M0L6_2acntS2013 > 1) {
    int32_t _M0L11_2anew__cntS2014 = _M0L6_2acntS2013 - 1;
    Moonbit_object_header(_M0L14_2acasted__envS1827)->rc
    = _M0L11_2anew__cntS2014;
    moonbit_incref(_M0L4nameS757);
    moonbit_incref(_M0L14handle__resultS773);
    moonbit_incref(_M0L8_2afieldS1877);
  } else if (_M0L6_2acntS2013 == 1) {
    #line 431 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
    moonbit_free(_M0L14_2acasted__envS1827);
  }
  _M0L17error__to__stringS775 = _M0L8_2afieldS1877;
  #line 431 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1828
  = _M0L17error__to__stringS775->code(_M0L17error__to__stringS775, _M0L3errS774);
  #line 431 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L14handle__resultS773->code(_M0L14handle__resultS773, _M0L4nameS757, _M0L6_2atmpS1828, 0);
  return 0;
}

int32_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors45moonbit__test__driver__internal__catch__error(
  struct _M0TWEuQRPC15error5Error* _M0L1fS748,
  struct _M0TWEu* _M0L6on__okS749,
  struct _M0TWRPC15error5ErrorEu* _M0L7on__errS746
) {
  void* _M0L11_2atry__errS744;
  struct moonbit_result_0 _tmp_2088;
  void* _M0L3errS745;
  #line 375 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  #line 382 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _tmp_2088 = _M0L1fS748->code(_M0L1fS748);
  if (_tmp_2088.tag) {
    int32_t const _M0L5_2aokS1813 = _tmp_2088.data.ok;
    moonbit_decref(_M0L7on__errS746);
  } else {
    void* const _M0L6_2aerrS1814 = _tmp_2088.data.err;
    moonbit_decref(_M0L6on__okS749);
    _M0L11_2atry__errS744 = _M0L6_2aerrS1814;
    goto join_743;
  }
  #line 382 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6on__okS749->code(_M0L6on__okS749);
  goto joinlet_2087;
  join_743:;
  _M0L3errS745 = _M0L11_2atry__errS744;
  #line 383 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L7on__errS746->code(_M0L7on__errS746, _M0L3errS745);
  joinlet_2087:;
  return 0;
}

struct _M0TPB5ArrayGUsiEE* _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__args(
  
) {
  int32_t _M0L45moonbit__test__driver__internal__parse__int__S703;
  int32_t _M0L61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS709;
  int32_t _M0L57moonbit__test__driver__internal__get__cli__args__internalS716;
  int32_t _M0L51moonbit__test__driver__internal__split__mbt__stringS721;
  struct _M0TUsiE** _M0L6_2atmpS1812;
  struct _M0TPB5ArrayGUsiEE* _M0L16file__and__indexS728;
  struct _M0TPB5ArrayGsE* _M0L9cli__argsS729;
  moonbit_string_t _M0L6_2atmpS1811;
  struct _M0TPB5ArrayGsE* _M0L10test__argsS730;
  int32_t _M0L7_2abindS731;
  int32_t _M0L2__S732;
  #line 193 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L45moonbit__test__driver__internal__parse__int__S703 = 0;
  _M0L61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS709 = 0;
  _M0L57moonbit__test__driver__internal__get__cli__args__internalS716
  = _M0L61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS709;
  _M0L51moonbit__test__driver__internal__split__mbt__stringS721 = 0;
  _M0L6_2atmpS1812 = (struct _M0TUsiE**)moonbit_empty_ref_array;
  _M0L16file__and__indexS728
  = (struct _M0TPB5ArrayGUsiEE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGUsiEE));
  Moonbit_object_header(_M0L16file__and__indexS728)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGUsiEE, $0) >> 2, 1, 0);
  _M0L16file__and__indexS728->$0 = _M0L6_2atmpS1812;
  _M0L16file__and__indexS728->$1 = 0;
  #line 282 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L9cli__argsS729
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN57moonbit__test__driver__internal__get__cli__args__internalS716(_M0L57moonbit__test__driver__internal__get__cli__args__internalS716);
  #line 284 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1811 = _M0MPC15array5Array2atGsE(_M0L9cli__argsS729, 1);
  #line 283 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L10test__argsS730
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN51moonbit__test__driver__internal__split__mbt__stringS721(_M0L51moonbit__test__driver__internal__split__mbt__stringS721, _M0L6_2atmpS1811, 47);
  _M0L7_2abindS731 = _M0L10test__argsS730->$1;
  _M0L2__S732 = 0;
  while (1) {
    if (_M0L2__S732 < _M0L7_2abindS731) {
      moonbit_string_t* _M0L3bufS1810 = _M0L10test__argsS730->$0;
      moonbit_string_t _M0L3argS733 =
        (moonbit_string_t)_M0L3bufS1810[_M0L2__S732];
      struct _M0TPB5ArrayGsE* _M0L16file__and__rangeS734;
      moonbit_string_t _M0L4fileS735;
      moonbit_string_t _M0L5rangeS736;
      struct _M0TPB5ArrayGsE* _M0L15start__and__endS737;
      moonbit_string_t _M0L6_2atmpS1808;
      int32_t _M0L5startS738;
      moonbit_string_t _M0L6_2atmpS1807;
      int32_t _M0L3endS739;
      int32_t _M0L1iS740;
      int32_t _M0L6_2atmpS1809;
      moonbit_incref(_M0L3argS733);
      #line 288 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
      _M0L16file__and__rangeS734
      = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN51moonbit__test__driver__internal__split__mbt__stringS721(_M0L51moonbit__test__driver__internal__split__mbt__stringS721, _M0L3argS733, 58);
      moonbit_incref(_M0L16file__and__rangeS734);
      #line 289 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
      _M0L4fileS735
      = _M0MPC15array5Array2atGsE(_M0L16file__and__rangeS734, 0);
      #line 290 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
      _M0L5rangeS736
      = _M0MPC15array5Array2atGsE(_M0L16file__and__rangeS734, 1);
      #line 291 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
      _M0L15start__and__endS737
      = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN51moonbit__test__driver__internal__split__mbt__stringS721(_M0L51moonbit__test__driver__internal__split__mbt__stringS721, _M0L5rangeS736, 45);
      moonbit_incref(_M0L15start__and__endS737);
      #line 294 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
      _M0L6_2atmpS1808
      = _M0MPC15array5Array2atGsE(_M0L15start__and__endS737, 0);
      #line 294 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
      _M0L5startS738
      = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN45moonbit__test__driver__internal__parse__int__S703(_M0L45moonbit__test__driver__internal__parse__int__S703, _M0L6_2atmpS1808);
      #line 295 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
      _M0L6_2atmpS1807
      = _M0MPC15array5Array2atGsE(_M0L15start__and__endS737, 1);
      #line 295 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
      _M0L3endS739
      = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN45moonbit__test__driver__internal__parse__int__S703(_M0L45moonbit__test__driver__internal__parse__int__S703, _M0L6_2atmpS1807);
      _M0L1iS740 = _M0L5startS738;
      while (1) {
        if (_M0L1iS740 < _M0L3endS739) {
          struct _M0TUsiE* _M0L8_2atupleS1805;
          int32_t _M0L6_2atmpS1806;
          moonbit_incref(_M0L4fileS735);
          _M0L8_2atupleS1805
          = (struct _M0TUsiE*)moonbit_malloc(sizeof(struct _M0TUsiE));
          Moonbit_object_header(_M0L8_2atupleS1805)->meta
          = Moonbit_make_regular_object_header(offsetof(struct _M0TUsiE, $0) >> 2, 1, 0);
          _M0L8_2atupleS1805->$0 = _M0L4fileS735;
          _M0L8_2atupleS1805->$1 = _M0L1iS740;
          moonbit_incref(_M0L16file__and__indexS728);
          #line 297 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
          _M0MPC15array5Array4pushGUsiEE(_M0L16file__and__indexS728, _M0L8_2atupleS1805);
          _M0L6_2atmpS1806 = _M0L1iS740 + 1;
          _M0L1iS740 = _M0L6_2atmpS1806;
          continue;
        } else {
          moonbit_decref(_M0L4fileS735);
        }
        break;
      }
      _M0L6_2atmpS1809 = _M0L2__S732 + 1;
      _M0L2__S732 = _M0L6_2atmpS1809;
      continue;
    } else {
      moonbit_decref(_M0L10test__argsS730);
    }
    break;
  }
  return _M0L16file__and__indexS728;
}

struct _M0TPB5ArrayGsE* _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN51moonbit__test__driver__internal__split__mbt__stringS721(
  int32_t _M0L6_2aenvS1786,
  moonbit_string_t _M0L1sS722,
  int32_t _M0L3sepS723
) {
  moonbit_string_t* _M0L6_2atmpS1804;
  struct _M0TPB5ArrayGsE* _M0L3resS724;
  struct _M0TPB8MutLocalGiE* _M0L1iS725;
  struct _M0TPB8MutLocalGiE* _M0L5startS726;
  int32_t _M0L3valS1799;
  int32_t _M0L6_2atmpS1800;
  #line 261 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS1804 = (moonbit_string_t*)moonbit_empty_ref_array;
  _M0L3resS724
  = (struct _M0TPB5ArrayGsE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGsE));
  Moonbit_object_header(_M0L3resS724)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGsE, $0) >> 2, 1, 0);
  _M0L3resS724->$0 = _M0L6_2atmpS1804;
  _M0L3resS724->$1 = 0;
  _M0L1iS725
  = (struct _M0TPB8MutLocalGiE*)moonbit_malloc(sizeof(struct _M0TPB8MutLocalGiE));
  Moonbit_object_header(_M0L1iS725)->meta
  = Moonbit_make_regular_object_header(sizeof(struct _M0TPB8MutLocalGiE) >> 2, 0, 0);
  _M0L1iS725->$0 = 0;
  _M0L5startS726
  = (struct _M0TPB8MutLocalGiE*)moonbit_malloc(sizeof(struct _M0TPB8MutLocalGiE));
  Moonbit_object_header(_M0L5startS726)->meta
  = Moonbit_make_regular_object_header(sizeof(struct _M0TPB8MutLocalGiE) >> 2, 0, 0);
  _M0L5startS726->$0 = 0;
  while (1) {
    int32_t _M0L3valS1787 = _M0L1iS725->$0;
    int32_t _M0L6_2atmpS1788 = Moonbit_array_length(_M0L1sS722);
    if (_M0L3valS1787 < _M0L6_2atmpS1788) {
      int32_t _M0L3valS1791 = _M0L1iS725->$0;
      int32_t _M0L6_2atmpS1790;
      int32_t _M0L6_2atmpS1789;
      int32_t _M0L3valS1798;
      int32_t _M0L6_2atmpS1797;
      if (
        _M0L3valS1791 < 0
        || _M0L3valS1791 >= Moonbit_array_length(_M0L1sS722)
      ) {
        #line 269 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
        moonbit_panic();
      }
      _M0L6_2atmpS1790 = _M0L1sS722[_M0L3valS1791];
      _M0L6_2atmpS1789 = _M0L6_2atmpS1790;
      if (_M0L6_2atmpS1789 == _M0L3sepS723) {
        int32_t _M0L3valS1793 = _M0L5startS726->$0;
        int32_t _M0L3valS1794 = _M0L1iS725->$0;
        moonbit_string_t _M0L6_2atmpS1792;
        int32_t _M0L3valS1796;
        int32_t _M0L6_2atmpS1795;
        moonbit_incref(_M0L1sS722);
        #line 270 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
        _M0L6_2atmpS1792
        = _M0MPC16string6String17unsafe__substring(_M0L1sS722, _M0L3valS1793, _M0L3valS1794);
        moonbit_incref(_M0L3resS724);
        #line 270 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
        _M0MPC15array5Array4pushGsE(_M0L3resS724, _M0L6_2atmpS1792);
        _M0L3valS1796 = _M0L1iS725->$0;
        _M0L6_2atmpS1795 = _M0L3valS1796 + 1;
        _M0L5startS726->$0 = _M0L6_2atmpS1795;
      }
      _M0L3valS1798 = _M0L1iS725->$0;
      _M0L6_2atmpS1797 = _M0L3valS1798 + 1;
      _M0L1iS725->$0 = _M0L6_2atmpS1797;
      continue;
    } else {
      moonbit_decref(_M0L1iS725);
    }
    break;
  }
  _M0L3valS1799 = _M0L5startS726->$0;
  _M0L6_2atmpS1800 = Moonbit_array_length(_M0L1sS722);
  if (_M0L3valS1799 < _M0L6_2atmpS1800) {
    int32_t _M0L3valS1802 = _M0L5startS726->$0;
    int32_t _M0L6_2atmpS1803;
    moonbit_string_t _M0L6_2atmpS1801;
    moonbit_decref(_M0L5startS726);
    _M0L6_2atmpS1803 = Moonbit_array_length(_M0L1sS722);
    #line 276 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
    _M0L6_2atmpS1801
    = _M0MPC16string6String17unsafe__substring(_M0L1sS722, _M0L3valS1802, _M0L6_2atmpS1803);
    moonbit_incref(_M0L3resS724);
    #line 276 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
    _M0MPC15array5Array4pushGsE(_M0L3resS724, _M0L6_2atmpS1801);
  } else {
    moonbit_decref(_M0L5startS726);
    moonbit_decref(_M0L1sS722);
  }
  return _M0L3resS724;
}

struct _M0TPB5ArrayGsE* _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN57moonbit__test__driver__internal__get__cli__args__internalS716(
  int32_t _M0L61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS709
) {
  moonbit_bytes_t* _M0L3tmpS717;
  int32_t _M0L6_2atmpS1785;
  struct _M0TPB5ArrayGsE* _M0L3resS718;
  int32_t _M0L1iS719;
  #line 250 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  #line 253 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L3tmpS717
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__get__cli__args__ffi();
  _M0L6_2atmpS1785 = Moonbit_array_length(_M0L3tmpS717);
  #line 254 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L3resS718 = _M0MPC15array5Array11new_2einnerGsE(_M0L6_2atmpS1785);
  _M0L1iS719 = 0;
  while (1) {
    int32_t _M0L6_2atmpS1781 = Moonbit_array_length(_M0L3tmpS717);
    if (_M0L1iS719 < _M0L6_2atmpS1781) {
      moonbit_bytes_t _M0L6_2atmpS1783;
      moonbit_string_t _M0L6_2atmpS1782;
      int32_t _M0L6_2atmpS1784;
      if (_M0L1iS719 < 0 || _M0L1iS719 >= Moonbit_array_length(_M0L3tmpS717)) {
        #line 256 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
        moonbit_panic();
      }
      _M0L6_2atmpS1783 = (moonbit_bytes_t)_M0L3tmpS717[_M0L1iS719];
      moonbit_incref(_M0L6_2atmpS1783);
      #line 256 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
      _M0L6_2atmpS1782
      = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS709(_M0L61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS709, _M0L6_2atmpS1783);
      moonbit_incref(_M0L3resS718);
      #line 256 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
      _M0MPC15array5Array4pushGsE(_M0L3resS718, _M0L6_2atmpS1782);
      _M0L6_2atmpS1784 = _M0L1iS719 + 1;
      _M0L1iS719 = _M0L6_2atmpS1784;
      continue;
    } else {
      moonbit_decref(_M0L3tmpS717);
    }
    break;
  }
  return _M0L3resS718;
}

moonbit_string_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS709(
  int32_t _M0L6_2aenvS1695,
  moonbit_bytes_t _M0L5bytesS710
) {
  struct _M0TPB13StringBuilder* _M0L3resS711;
  int32_t _M0L3lenS712;
  struct _M0TPB8MutLocalGiE* _M0L1iS713;
  #line 206 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  #line 209 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L3resS711 = _M0MPB13StringBuilder11new_2einner(0);
  _M0L3lenS712 = Moonbit_array_length(_M0L5bytesS710);
  _M0L1iS713
  = (struct _M0TPB8MutLocalGiE*)moonbit_malloc(sizeof(struct _M0TPB8MutLocalGiE));
  Moonbit_object_header(_M0L1iS713)->meta
  = Moonbit_make_regular_object_header(sizeof(struct _M0TPB8MutLocalGiE) >> 2, 0, 0);
  _M0L1iS713->$0 = 0;
  while (1) {
    int32_t _M0L3valS1696 = _M0L1iS713->$0;
    if (_M0L3valS1696 < _M0L3lenS712) {
      int32_t _M0L3valS1780 = _M0L1iS713->$0;
      int32_t _M0L6_2atmpS1779;
      int32_t _M0L6_2atmpS1778;
      struct _M0TPB8MutLocalGiE* _M0L1cS714;
      int32_t _M0L3valS1697;
      if (
        _M0L3valS1780 < 0
        || _M0L3valS1780 >= Moonbit_array_length(_M0L5bytesS710)
      ) {
        #line 213 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
        moonbit_panic();
      }
      _M0L6_2atmpS1779 = _M0L5bytesS710[_M0L3valS1780];
      _M0L6_2atmpS1778 = (int32_t)_M0L6_2atmpS1779;
      _M0L1cS714
      = (struct _M0TPB8MutLocalGiE*)moonbit_malloc(sizeof(struct _M0TPB8MutLocalGiE));
      Moonbit_object_header(_M0L1cS714)->meta
      = Moonbit_make_regular_object_header(sizeof(struct _M0TPB8MutLocalGiE) >> 2, 0, 0);
      _M0L1cS714->$0 = _M0L6_2atmpS1778;
      _M0L3valS1697 = _M0L1cS714->$0;
      if (_M0L3valS1697 < 128) {
        int32_t _M0L3valS1699 = _M0L1cS714->$0;
        int32_t _M0L6_2atmpS1698;
        int32_t _M0L3valS1701;
        int32_t _M0L6_2atmpS1700;
        moonbit_decref(_M0L1cS714);
        _M0L6_2atmpS1698 = _M0L3valS1699;
        moonbit_incref(_M0L3resS711);
        #line 215 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
        _M0IPB13StringBuilderPB6Logger11write__char(_M0L3resS711, _M0L6_2atmpS1698);
        _M0L3valS1701 = _M0L1iS713->$0;
        _M0L6_2atmpS1700 = _M0L3valS1701 + 1;
        _M0L1iS713->$0 = _M0L6_2atmpS1700;
      } else {
        int32_t _M0L3valS1702 = _M0L1cS714->$0;
        if (_M0L3valS1702 < 224) {
          int32_t _M0L3valS1704 = _M0L1iS713->$0;
          int32_t _M0L6_2atmpS1703 = _M0L3valS1704 + 1;
          int32_t _M0L3valS1713;
          int32_t _M0L6_2atmpS1712;
          int32_t _M0L6_2atmpS1706;
          int32_t _M0L3valS1711;
          int32_t _M0L6_2atmpS1710;
          int32_t _M0L6_2atmpS1709;
          int32_t _M0L6_2atmpS1708;
          int32_t _M0L6_2atmpS1707;
          int32_t _M0L6_2atmpS1705;
          int32_t _M0L3valS1715;
          int32_t _M0L6_2atmpS1714;
          int32_t _M0L3valS1717;
          int32_t _M0L6_2atmpS1716;
          if (_M0L6_2atmpS1703 >= _M0L3lenS712) {
            moonbit_decref(_M0L1cS714);
            moonbit_decref(_M0L1iS713);
            moonbit_decref(_M0L5bytesS710);
            break;
          }
          _M0L3valS1713 = _M0L1cS714->$0;
          _M0L6_2atmpS1712 = _M0L3valS1713 & 31;
          _M0L6_2atmpS1706 = _M0L6_2atmpS1712 << 6;
          _M0L3valS1711 = _M0L1iS713->$0;
          _M0L6_2atmpS1710 = _M0L3valS1711 + 1;
          if (
            _M0L6_2atmpS1710 < 0
            || _M0L6_2atmpS1710 >= Moonbit_array_length(_M0L5bytesS710)
          ) {
            #line 221 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
            moonbit_panic();
          }
          _M0L6_2atmpS1709 = _M0L5bytesS710[_M0L6_2atmpS1710];
          _M0L6_2atmpS1708 = (int32_t)_M0L6_2atmpS1709;
          _M0L6_2atmpS1707 = _M0L6_2atmpS1708 & 63;
          _M0L6_2atmpS1705 = _M0L6_2atmpS1706 | _M0L6_2atmpS1707;
          _M0L1cS714->$0 = _M0L6_2atmpS1705;
          _M0L3valS1715 = _M0L1cS714->$0;
          moonbit_decref(_M0L1cS714);
          _M0L6_2atmpS1714 = _M0L3valS1715;
          moonbit_incref(_M0L3resS711);
          #line 222 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
          _M0IPB13StringBuilderPB6Logger11write__char(_M0L3resS711, _M0L6_2atmpS1714);
          _M0L3valS1717 = _M0L1iS713->$0;
          _M0L6_2atmpS1716 = _M0L3valS1717 + 2;
          _M0L1iS713->$0 = _M0L6_2atmpS1716;
        } else {
          int32_t _M0L3valS1718 = _M0L1cS714->$0;
          if (_M0L3valS1718 < 240) {
            int32_t _M0L3valS1720 = _M0L1iS713->$0;
            int32_t _M0L6_2atmpS1719 = _M0L3valS1720 + 2;
            int32_t _M0L3valS1736;
            int32_t _M0L6_2atmpS1735;
            int32_t _M0L6_2atmpS1728;
            int32_t _M0L3valS1734;
            int32_t _M0L6_2atmpS1733;
            int32_t _M0L6_2atmpS1732;
            int32_t _M0L6_2atmpS1731;
            int32_t _M0L6_2atmpS1730;
            int32_t _M0L6_2atmpS1729;
            int32_t _M0L6_2atmpS1722;
            int32_t _M0L3valS1727;
            int32_t _M0L6_2atmpS1726;
            int32_t _M0L6_2atmpS1725;
            int32_t _M0L6_2atmpS1724;
            int32_t _M0L6_2atmpS1723;
            int32_t _M0L6_2atmpS1721;
            int32_t _M0L3valS1738;
            int32_t _M0L6_2atmpS1737;
            int32_t _M0L3valS1740;
            int32_t _M0L6_2atmpS1739;
            if (_M0L6_2atmpS1719 >= _M0L3lenS712) {
              moonbit_decref(_M0L1cS714);
              moonbit_decref(_M0L1iS713);
              moonbit_decref(_M0L5bytesS710);
              break;
            }
            _M0L3valS1736 = _M0L1cS714->$0;
            _M0L6_2atmpS1735 = _M0L3valS1736 & 15;
            _M0L6_2atmpS1728 = _M0L6_2atmpS1735 << 12;
            _M0L3valS1734 = _M0L1iS713->$0;
            _M0L6_2atmpS1733 = _M0L3valS1734 + 1;
            if (
              _M0L6_2atmpS1733 < 0
              || _M0L6_2atmpS1733 >= Moonbit_array_length(_M0L5bytesS710)
            ) {
              #line 229 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
              moonbit_panic();
            }
            _M0L6_2atmpS1732 = _M0L5bytesS710[_M0L6_2atmpS1733];
            _M0L6_2atmpS1731 = (int32_t)_M0L6_2atmpS1732;
            _M0L6_2atmpS1730 = _M0L6_2atmpS1731 & 63;
            _M0L6_2atmpS1729 = _M0L6_2atmpS1730 << 6;
            _M0L6_2atmpS1722 = _M0L6_2atmpS1728 | _M0L6_2atmpS1729;
            _M0L3valS1727 = _M0L1iS713->$0;
            _M0L6_2atmpS1726 = _M0L3valS1727 + 2;
            if (
              _M0L6_2atmpS1726 < 0
              || _M0L6_2atmpS1726 >= Moonbit_array_length(_M0L5bytesS710)
            ) {
              #line 230 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
              moonbit_panic();
            }
            _M0L6_2atmpS1725 = _M0L5bytesS710[_M0L6_2atmpS1726];
            _M0L6_2atmpS1724 = (int32_t)_M0L6_2atmpS1725;
            _M0L6_2atmpS1723 = _M0L6_2atmpS1724 & 63;
            _M0L6_2atmpS1721 = _M0L6_2atmpS1722 | _M0L6_2atmpS1723;
            _M0L1cS714->$0 = _M0L6_2atmpS1721;
            _M0L3valS1738 = _M0L1cS714->$0;
            moonbit_decref(_M0L1cS714);
            _M0L6_2atmpS1737 = _M0L3valS1738;
            moonbit_incref(_M0L3resS711);
            #line 231 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
            _M0IPB13StringBuilderPB6Logger11write__char(_M0L3resS711, _M0L6_2atmpS1737);
            _M0L3valS1740 = _M0L1iS713->$0;
            _M0L6_2atmpS1739 = _M0L3valS1740 + 3;
            _M0L1iS713->$0 = _M0L6_2atmpS1739;
          } else {
            int32_t _M0L3valS1742 = _M0L1iS713->$0;
            int32_t _M0L6_2atmpS1741 = _M0L3valS1742 + 3;
            int32_t _M0L3valS1765;
            int32_t _M0L6_2atmpS1764;
            int32_t _M0L6_2atmpS1757;
            int32_t _M0L3valS1763;
            int32_t _M0L6_2atmpS1762;
            int32_t _M0L6_2atmpS1761;
            int32_t _M0L6_2atmpS1760;
            int32_t _M0L6_2atmpS1759;
            int32_t _M0L6_2atmpS1758;
            int32_t _M0L6_2atmpS1750;
            int32_t _M0L3valS1756;
            int32_t _M0L6_2atmpS1755;
            int32_t _M0L6_2atmpS1754;
            int32_t _M0L6_2atmpS1753;
            int32_t _M0L6_2atmpS1752;
            int32_t _M0L6_2atmpS1751;
            int32_t _M0L6_2atmpS1744;
            int32_t _M0L3valS1749;
            int32_t _M0L6_2atmpS1748;
            int32_t _M0L6_2atmpS1747;
            int32_t _M0L6_2atmpS1746;
            int32_t _M0L6_2atmpS1745;
            int32_t _M0L6_2atmpS1743;
            int32_t _M0L3valS1767;
            int32_t _M0L6_2atmpS1766;
            int32_t _M0L3valS1771;
            int32_t _M0L6_2atmpS1770;
            int32_t _M0L6_2atmpS1769;
            int32_t _M0L6_2atmpS1768;
            int32_t _M0L3valS1775;
            int32_t _M0L6_2atmpS1774;
            int32_t _M0L6_2atmpS1773;
            int32_t _M0L6_2atmpS1772;
            int32_t _M0L3valS1777;
            int32_t _M0L6_2atmpS1776;
            if (_M0L6_2atmpS1741 >= _M0L3lenS712) {
              moonbit_decref(_M0L1cS714);
              moonbit_decref(_M0L1iS713);
              moonbit_decref(_M0L5bytesS710);
              break;
            }
            _M0L3valS1765 = _M0L1cS714->$0;
            _M0L6_2atmpS1764 = _M0L3valS1765 & 7;
            _M0L6_2atmpS1757 = _M0L6_2atmpS1764 << 18;
            _M0L3valS1763 = _M0L1iS713->$0;
            _M0L6_2atmpS1762 = _M0L3valS1763 + 1;
            if (
              _M0L6_2atmpS1762 < 0
              || _M0L6_2atmpS1762 >= Moonbit_array_length(_M0L5bytesS710)
            ) {
              #line 238 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
              moonbit_panic();
            }
            _M0L6_2atmpS1761 = _M0L5bytesS710[_M0L6_2atmpS1762];
            _M0L6_2atmpS1760 = (int32_t)_M0L6_2atmpS1761;
            _M0L6_2atmpS1759 = _M0L6_2atmpS1760 & 63;
            _M0L6_2atmpS1758 = _M0L6_2atmpS1759 << 12;
            _M0L6_2atmpS1750 = _M0L6_2atmpS1757 | _M0L6_2atmpS1758;
            _M0L3valS1756 = _M0L1iS713->$0;
            _M0L6_2atmpS1755 = _M0L3valS1756 + 2;
            if (
              _M0L6_2atmpS1755 < 0
              || _M0L6_2atmpS1755 >= Moonbit_array_length(_M0L5bytesS710)
            ) {
              #line 239 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
              moonbit_panic();
            }
            _M0L6_2atmpS1754 = _M0L5bytesS710[_M0L6_2atmpS1755];
            _M0L6_2atmpS1753 = (int32_t)_M0L6_2atmpS1754;
            _M0L6_2atmpS1752 = _M0L6_2atmpS1753 & 63;
            _M0L6_2atmpS1751 = _M0L6_2atmpS1752 << 6;
            _M0L6_2atmpS1744 = _M0L6_2atmpS1750 | _M0L6_2atmpS1751;
            _M0L3valS1749 = _M0L1iS713->$0;
            _M0L6_2atmpS1748 = _M0L3valS1749 + 3;
            if (
              _M0L6_2atmpS1748 < 0
              || _M0L6_2atmpS1748 >= Moonbit_array_length(_M0L5bytesS710)
            ) {
              #line 240 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
              moonbit_panic();
            }
            _M0L6_2atmpS1747 = _M0L5bytesS710[_M0L6_2atmpS1748];
            _M0L6_2atmpS1746 = (int32_t)_M0L6_2atmpS1747;
            _M0L6_2atmpS1745 = _M0L6_2atmpS1746 & 63;
            _M0L6_2atmpS1743 = _M0L6_2atmpS1744 | _M0L6_2atmpS1745;
            _M0L1cS714->$0 = _M0L6_2atmpS1743;
            _M0L3valS1767 = _M0L1cS714->$0;
            _M0L6_2atmpS1766 = _M0L3valS1767 - 65536;
            _M0L1cS714->$0 = _M0L6_2atmpS1766;
            _M0L3valS1771 = _M0L1cS714->$0;
            _M0L6_2atmpS1770 = _M0L3valS1771 >> 10;
            _M0L6_2atmpS1769 = _M0L6_2atmpS1770 + 55296;
            _M0L6_2atmpS1768 = _M0L6_2atmpS1769;
            moonbit_incref(_M0L3resS711);
            #line 242 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
            _M0IPB13StringBuilderPB6Logger11write__char(_M0L3resS711, _M0L6_2atmpS1768);
            _M0L3valS1775 = _M0L1cS714->$0;
            moonbit_decref(_M0L1cS714);
            _M0L6_2atmpS1774 = _M0L3valS1775 & 1023;
            _M0L6_2atmpS1773 = _M0L6_2atmpS1774 + 56320;
            _M0L6_2atmpS1772 = _M0L6_2atmpS1773;
            moonbit_incref(_M0L3resS711);
            #line 243 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
            _M0IPB13StringBuilderPB6Logger11write__char(_M0L3resS711, _M0L6_2atmpS1772);
            _M0L3valS1777 = _M0L1iS713->$0;
            _M0L6_2atmpS1776 = _M0L3valS1777 + 4;
            _M0L1iS713->$0 = _M0L6_2atmpS1776;
          }
        }
      }
      continue;
    } else {
      moonbit_decref(_M0L1iS713);
      moonbit_decref(_M0L5bytesS710);
    }
    break;
  }
  #line 247 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  return _M0MPB13StringBuilder10to__string(_M0L3resS711);
}

int32_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__argsN45moonbit__test__driver__internal__parse__int__S703(
  int32_t _M0L6_2aenvS1688,
  moonbit_string_t _M0L1sS704
) {
  struct _M0TPB8MutLocalGiE* _M0L3resS705;
  int32_t _M0L3lenS706;
  int32_t _M0L1iS707;
  int32_t _result_2095;
  #line 197 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L3resS705
  = (struct _M0TPB8MutLocalGiE*)moonbit_malloc(sizeof(struct _M0TPB8MutLocalGiE));
  Moonbit_object_header(_M0L3resS705)->meta
  = Moonbit_make_regular_object_header(sizeof(struct _M0TPB8MutLocalGiE) >> 2, 0, 0);
  _M0L3resS705->$0 = 0;
  _M0L3lenS706 = Moonbit_array_length(_M0L1sS704);
  _M0L1iS707 = 0;
  while (1) {
    if (_M0L1iS707 < _M0L3lenS706) {
      int32_t _M0L3valS1693 = _M0L3resS705->$0;
      int32_t _M0L6_2atmpS1690 = _M0L3valS1693 * 10;
      int32_t _M0L6_2atmpS1692;
      int32_t _M0L6_2atmpS1691;
      int32_t _M0L6_2atmpS1689;
      int32_t _M0L6_2atmpS1694;
      if (_M0L1iS707 < 0 || _M0L1iS707 >= Moonbit_array_length(_M0L1sS704)) {
        #line 201 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
        moonbit_panic();
      }
      _M0L6_2atmpS1692 = _M0L1sS704[_M0L1iS707];
      _M0L6_2atmpS1691 = _M0L6_2atmpS1692 - 48;
      _M0L6_2atmpS1689 = _M0L6_2atmpS1690 + _M0L6_2atmpS1691;
      _M0L3resS705->$0 = _M0L6_2atmpS1689;
      _M0L6_2atmpS1694 = _M0L1iS707 + 1;
      _M0L1iS707 = _M0L6_2atmpS1694;
      continue;
    } else {
      moonbit_decref(_M0L1sS704);
    }
    break;
  }
  _result_2095 = _M0L3resS705->$0;
  moonbit_decref(_M0L3resS705);
  return _result_2095;
}

struct moonbit_result_0 _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testGRP412hnlyxiaobing12MBOpenClacky3lib6errors43MoonBit__Test__Driver__Internal__With__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12_2adiscard__S683,
  moonbit_string_t _M0L12_2adiscard__S684,
  int32_t _M0L12_2adiscard__S685,
  struct _M0TWssbEu* _M0L12_2adiscard__S686,
  struct _M0TWRPC15error5ErrorEs* _M0L12_2adiscard__S687
) {
  struct moonbit_result_0 _result_2096;
  #line 34 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  moonbit_decref(_M0L12_2adiscard__S687);
  moonbit_decref(_M0L12_2adiscard__S686);
  moonbit_decref(_M0L12_2adiscard__S684);
  moonbit_decref(_M0L12_2adiscard__S683);
  _result_2096.tag = 1;
  _result_2096.data.ok = 0;
  return _result_2096;
}

struct moonbit_result_0 _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testGRP412hnlyxiaobing12MBOpenClacky3lib6errors48MoonBit__Test__Driver__Internal__Async__No__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12_2adiscard__S688,
  moonbit_string_t _M0L12_2adiscard__S689,
  int32_t _M0L12_2adiscard__S690,
  struct _M0TWssbEu* _M0L12_2adiscard__S691,
  struct _M0TWRPC15error5ErrorEs* _M0L12_2adiscard__S692
) {
  struct moonbit_result_0 _result_2097;
  #line 34 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  moonbit_decref(_M0L12_2adiscard__S692);
  moonbit_decref(_M0L12_2adiscard__S691);
  moonbit_decref(_M0L12_2adiscard__S689);
  moonbit_decref(_M0L12_2adiscard__S688);
  _result_2097.tag = 1;
  _result_2097.data.ok = 0;
  return _result_2097;
}

struct moonbit_result_0 _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testGRP412hnlyxiaobing12MBOpenClacky3lib6errors50MoonBit__Test__Driver__Internal__Async__With__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12_2adiscard__S693,
  moonbit_string_t _M0L12_2adiscard__S694,
  int32_t _M0L12_2adiscard__S695,
  struct _M0TWssbEu* _M0L12_2adiscard__S696,
  struct _M0TWRPC15error5ErrorEs* _M0L12_2adiscard__S697
) {
  struct moonbit_result_0 _result_2098;
  #line 34 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  moonbit_decref(_M0L12_2adiscard__S697);
  moonbit_decref(_M0L12_2adiscard__S696);
  moonbit_decref(_M0L12_2adiscard__S694);
  moonbit_decref(_M0L12_2adiscard__S693);
  _result_2098.tag = 1;
  _result_2098.data.ok = 0;
  return _result_2098;
}

struct moonbit_result_0 _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors21MoonBit__Test__Driver9run__testGRP412hnlyxiaobing12MBOpenClacky3lib6errors50MoonBit__Test__Driver__Internal__With__Bench__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12_2adiscard__S698,
  moonbit_string_t _M0L12_2adiscard__S699,
  int32_t _M0L12_2adiscard__S700,
  struct _M0TWssbEu* _M0L12_2adiscard__S701,
  struct _M0TWRPC15error5ErrorEs* _M0L12_2adiscard__S702
) {
  struct moonbit_result_0 _result_2099;
  #line 34 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  moonbit_decref(_M0L12_2adiscard__S702);
  moonbit_decref(_M0L12_2adiscard__S701);
  moonbit_decref(_M0L12_2adiscard__S699);
  moonbit_decref(_M0L12_2adiscard__S698);
  _result_2099.tag = 1;
  _result_2099.data.ok = 0;
  return _result_2099;
}

int32_t _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors28MoonBit__Async__Test__Driver17run__async__testsGRP412hnlyxiaobing12MBOpenClacky3lib6errors34MoonBit__Async__Test__Driver__ImplE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12_2adiscard__S682
) {
  #line 12 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  moonbit_decref(_M0L12_2adiscard__S682);
  return 0;
}

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__5(
  
) {
  void* _M0L76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableErrorS1677;
  int32_t _M0L6_2atmpS1675;
  moonbit_string_t _M0L6_2atmpS1676;
  struct moonbit_result_0 _tmp_2100;
  void* _M0L92hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eUpstreamTruncatedError_2eUpstreamTruncatedErrorS1682;
  int32_t _M0L6_2atmpS1680;
  moonbit_string_t _M0L6_2atmpS1681;
  struct moonbit_result_0 _tmp_2102;
  void* _M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1687;
  int32_t _M0L6_2atmpS1685;
  moonbit_string_t _M0L6_2atmpS1686;
  #line 52 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableErrorS1677
  = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableError));
  Moonbit_object_header(_M0L76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableErrorS1677)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableError, $0) >> 2, 1, 7);
  ((struct _M0DTPC15error5Error76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableError*)_M0L76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableErrorS1677)->$0
  = (moonbit_string_t)moonbit_string_literal_9.data;
  #line 53 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L6_2atmpS1675
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors20is__retryable__error(_M0L76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableErrorS1677);
  _M0L6_2atmpS1676 = 0;
  #line 53 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _tmp_2100
  = _M0FPB12assert__true(_M0L6_2atmpS1675, _M0L6_2atmpS1676, (moonbit_string_t)moonbit_string_literal_10.data);
  if (_tmp_2100.tag) {
    int32_t const _M0L5_2aokS1678 = _tmp_2100.data.ok;
  } else {
    void* const _M0L6_2aerrS1679 = _tmp_2100.data.err;
    struct moonbit_result_0 _result_2101;
    _result_2101.tag = 0;
    _result_2101.data.err = _M0L6_2aerrS1679;
    return _result_2101;
  }
  _M0L92hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eUpstreamTruncatedError_2eUpstreamTruncatedErrorS1682
  = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error92hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eUpstreamTruncatedError_2eUpstreamTruncatedError));
  Moonbit_object_header(_M0L92hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eUpstreamTruncatedError_2eUpstreamTruncatedErrorS1682)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error92hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eUpstreamTruncatedError_2eUpstreamTruncatedError, $0) >> 2, 1, 8);
  ((struct _M0DTPC15error5Error92hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eUpstreamTruncatedError_2eUpstreamTruncatedError*)_M0L92hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eUpstreamTruncatedError_2eUpstreamTruncatedErrorS1682)->$0
  = (moonbit_string_t)moonbit_string_literal_9.data;
  #line 54 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L6_2atmpS1680
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors20is__retryable__error(_M0L92hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eUpstreamTruncatedError_2eUpstreamTruncatedErrorS1682);
  _M0L6_2atmpS1681 = 0;
  #line 54 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _tmp_2102
  = _M0FPB12assert__true(_M0L6_2atmpS1680, _M0L6_2atmpS1681, (moonbit_string_t)moonbit_string_literal_11.data);
  if (_tmp_2102.tag) {
    int32_t const _M0L5_2aokS1683 = _tmp_2102.data.ok;
  } else {
    void* const _M0L6_2aerrS1684 = _tmp_2102.data.err;
    struct moonbit_result_0 _result_2103;
    _result_2103.tag = 0;
    _result_2103.data.err = _M0L6_2aerrS1684;
    return _result_2103;
  }
  _M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1687
  = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentError));
  Moonbit_object_header(_M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1687)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentError, $0) >> 2, 1, 3);
  ((struct _M0DTPC15error5Error68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentError*)_M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1687)->$0
  = (moonbit_string_t)moonbit_string_literal_9.data;
  #line 55 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L6_2atmpS1685
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors20is__retryable__error(_M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1687);
  _M0L6_2atmpS1686 = 0;
  #line 55 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  return _M0FPB13assert__false(_M0L6_2atmpS1685, _M0L6_2atmpS1686, (moonbit_string_t)moonbit_string_literal_12.data);
}

int32_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors20is__retryable__error(
  void* _M0L3errS681
) {
  #line 56 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors.mbt"
  switch (Moonbit_object_tag(_M0L3errS681)) {
    case 7: {
      moonbit_decref(_M0L3errS681);
      return 1;
      break;
    }
    
    case 8: {
      moonbit_decref(_M0L3errS681);
      return 1;
      break;
    }
    default: {
      moonbit_decref(_M0L3errS681);
      return 0;
      break;
    }
  }
}

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__4(
  
) {
  void* _M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1649;
  int32_t _M0L6_2atmpS1647;
  moonbit_string_t _M0L6_2atmpS1648;
  struct moonbit_result_0 _tmp_2104;
  void* _M0L78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestErrorS1654;
  int32_t _M0L6_2atmpS1652;
  moonbit_string_t _M0L6_2atmpS1653;
  struct moonbit_result_0 _tmp_2106;
  void* _M0L74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallErrorS1659;
  int32_t _M0L6_2atmpS1657;
  moonbit_string_t _M0L6_2atmpS1658;
  struct moonbit_result_0 _tmp_2108;
  void* _M0L96hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBrowserNotReachableError_2eBrowserNotReachableErrorS1664;
  int32_t _M0L6_2atmpS1662;
  moonbit_string_t _M0L6_2atmpS1663;
  struct moonbit_result_0 _tmp_2110;
  void* _M0L76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableErrorS1669;
  int32_t _M0L6_2atmpS1667;
  moonbit_string_t _M0L6_2atmpS1668;
  struct moonbit_result_0 _tmp_2112;
  void* _M0L80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterruptedS1674;
  int32_t _M0L6_2atmpS1672;
  moonbit_string_t _M0L6_2atmpS1673;
  #line 43 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1649
  = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentError));
  Moonbit_object_header(_M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1649)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentError, $0) >> 2, 1, 3);
  ((struct _M0DTPC15error5Error68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentError*)_M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1649)->$0
  = (moonbit_string_t)moonbit_string_literal_9.data;
  #line 44 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L6_2atmpS1647
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors16is__agent__error(_M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1649);
  _M0L6_2atmpS1648 = 0;
  #line 44 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _tmp_2104
  = _M0FPB12assert__true(_M0L6_2atmpS1647, _M0L6_2atmpS1648, (moonbit_string_t)moonbit_string_literal_13.data);
  if (_tmp_2104.tag) {
    int32_t const _M0L5_2aokS1650 = _tmp_2104.data.ok;
  } else {
    void* const _M0L6_2aerrS1651 = _tmp_2104.data.err;
    struct moonbit_result_0 _result_2105;
    _result_2105.tag = 0;
    _result_2105.data.err = _M0L6_2aerrS1651;
    return _result_2105;
  }
  _M0L78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestErrorS1654
  = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestError));
  Moonbit_object_header(_M0L78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestErrorS1654)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestError, $1) >> 2, 1, 4);
  ((struct _M0DTPC15error5Error78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestError*)_M0L78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestErrorS1654)->$0
  = 400;
  ((struct _M0DTPC15error5Error78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestError*)_M0L78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestErrorS1654)->$1
  = (moonbit_string_t)moonbit_string_literal_9.data;
  #line 45 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L6_2atmpS1652
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors16is__agent__error(_M0L78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestErrorS1654);
  _M0L6_2atmpS1653 = 0;
  #line 45 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _tmp_2106
  = _M0FPB12assert__true(_M0L6_2atmpS1652, _M0L6_2atmpS1653, (moonbit_string_t)moonbit_string_literal_14.data);
  if (_tmp_2106.tag) {
    int32_t const _M0L5_2aokS1655 = _tmp_2106.data.ok;
  } else {
    void* const _M0L6_2aerrS1656 = _tmp_2106.data.err;
    struct moonbit_result_0 _result_2107;
    _result_2107.tag = 0;
    _result_2107.data.err = _M0L6_2aerrS1656;
    return _result_2107;
  }
  _M0L74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallErrorS1659
  = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallError));
  Moonbit_object_header(_M0L74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallErrorS1659)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallError, $0) >> 2, 2, 5);
  ((struct _M0DTPC15error5Error74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallError*)_M0L74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallErrorS1659)->$0
  = (moonbit_string_t)moonbit_string_literal_15.data;
  ((struct _M0DTPC15error5Error74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallError*)_M0L74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallErrorS1659)->$1
  = (moonbit_string_t)moonbit_string_literal_9.data;
  #line 46 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L6_2atmpS1657
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors16is__agent__error(_M0L74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallErrorS1659);
  _M0L6_2atmpS1658 = 0;
  #line 46 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _tmp_2108
  = _M0FPB12assert__true(_M0L6_2atmpS1657, _M0L6_2atmpS1658, (moonbit_string_t)moonbit_string_literal_16.data);
  if (_tmp_2108.tag) {
    int32_t const _M0L5_2aokS1660 = _tmp_2108.data.ok;
  } else {
    void* const _M0L6_2aerrS1661 = _tmp_2108.data.err;
    struct moonbit_result_0 _result_2109;
    _result_2109.tag = 0;
    _result_2109.data.err = _M0L6_2aerrS1661;
    return _result_2109;
  }
  _M0L96hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBrowserNotReachableError_2eBrowserNotReachableErrorS1664
  = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error96hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBrowserNotReachableError_2eBrowserNotReachableError));
  Moonbit_object_header(_M0L96hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBrowserNotReachableError_2eBrowserNotReachableErrorS1664)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error96hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBrowserNotReachableError_2eBrowserNotReachableError, $0) >> 2, 1, 6);
  ((struct _M0DTPC15error5Error96hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBrowserNotReachableError_2eBrowserNotReachableError*)_M0L96hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBrowserNotReachableError_2eBrowserNotReachableErrorS1664)->$0
  = (moonbit_string_t)moonbit_string_literal_9.data;
  #line 47 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L6_2atmpS1662
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors16is__agent__error(_M0L96hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBrowserNotReachableError_2eBrowserNotReachableErrorS1664);
  _M0L6_2atmpS1663 = 0;
  #line 47 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _tmp_2110
  = _M0FPB12assert__true(_M0L6_2atmpS1662, _M0L6_2atmpS1663, (moonbit_string_t)moonbit_string_literal_17.data);
  if (_tmp_2110.tag) {
    int32_t const _M0L5_2aokS1665 = _tmp_2110.data.ok;
  } else {
    void* const _M0L6_2aerrS1666 = _tmp_2110.data.err;
    struct moonbit_result_0 _result_2111;
    _result_2111.tag = 0;
    _result_2111.data.err = _M0L6_2aerrS1666;
    return _result_2111;
  }
  _M0L76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableErrorS1669
  = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableError));
  Moonbit_object_header(_M0L76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableErrorS1669)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableError, $0) >> 2, 1, 7);
  ((struct _M0DTPC15error5Error76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableError*)_M0L76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableErrorS1669)->$0
  = (moonbit_string_t)moonbit_string_literal_9.data;
  #line 48 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L6_2atmpS1667
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors16is__agent__error(_M0L76hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eRetryableError_2eRetryableErrorS1669);
  _M0L6_2atmpS1668 = 0;
  #line 48 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _tmp_2112
  = _M0FPB13assert__false(_M0L6_2atmpS1667, _M0L6_2atmpS1668, (moonbit_string_t)moonbit_string_literal_18.data);
  if (_tmp_2112.tag) {
    int32_t const _M0L5_2aokS1670 = _tmp_2112.data.ok;
  } else {
    void* const _M0L6_2aerrS1671 = _tmp_2112.data.err;
    struct moonbit_result_0 _result_2113;
    _result_2113.tag = 0;
    _result_2113.data.err = _M0L6_2aerrS1671;
    return _result_2113;
  }
  _M0L80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterruptedS1674
  = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterrupted));
  Moonbit_object_header(_M0L80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterruptedS1674)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterrupted, $0) >> 2, 1, 2);
  ((struct _M0DTPC15error5Error80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterrupted*)_M0L80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterruptedS1674)->$0
  = (moonbit_string_t)moonbit_string_literal_9.data;
  #line 49 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L6_2atmpS1672
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors16is__agent__error(_M0L80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterruptedS1674);
  _M0L6_2atmpS1673 = 0;
  #line 49 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  return _M0FPB13assert__false(_M0L6_2atmpS1672, _M0L6_2atmpS1673, (moonbit_string_t)moonbit_string_literal_19.data);
}

int32_t _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors16is__agent__error(
  void* _M0L3errS680
) {
  #line 45 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors.mbt"
  switch (Moonbit_object_tag(_M0L3errS680)) {
    case 3: {
      moonbit_decref(_M0L3errS680);
      return 1;
      break;
    }
    
    case 4: {
      moonbit_decref(_M0L3errS680);
      return 1;
      break;
    }
    
    case 5: {
      moonbit_decref(_M0L3errS680);
      return 1;
      break;
    }
    
    case 6: {
      moonbit_decref(_M0L3errS680);
      return 1;
      break;
    }
    default: {
      moonbit_decref(_M0L3errS680);
      return 0;
      break;
    }
  }
}

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__3(
  
) {
  void* _M0L11_2atry__errS673;
  void* _M0L74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallErrorS1646;
  moonbit_string_t _M0L10tool__nameS675;
  moonbit_string_t _M0L3msgS676;
  struct _M0DTPC15error5Error74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallError* _M0L16_2aToolCallErrorS677;
  moonbit_string_t _M0L13_2atool__nameS678;
  moonbit_string_t _M0L8_2afieldS1883;
  int32_t _M0L6_2acntS2015;
  moonbit_string_t _M0L6_2amsgS679;
  struct _M0TPB4Show _M0L6_2atmpS1630;
  moonbit_string_t _M0L6_2atmpS1633;
  moonbit_string_t _M0L6_2atmpS1634;
  moonbit_string_t _M0L6_2atmpS1635;
  moonbit_string_t _M0L6_2atmpS1636;
  moonbit_string_t* _M0L6_2atmpS1632;
  struct _M0TPB5ArrayGORPB9SourceLocE* _M0L6_2atmpS1631;
  struct moonbit_result_0 _tmp_2116;
  struct _M0TPB4Show _M0L6_2atmpS1639;
  moonbit_string_t _M0L6_2atmpS1642;
  moonbit_string_t _M0L6_2atmpS1643;
  moonbit_string_t _M0L6_2atmpS1644;
  moonbit_string_t _M0L6_2atmpS1645;
  moonbit_string_t* _M0L6_2atmpS1641;
  struct _M0TPB5ArrayGORPB9SourceLocE* _M0L6_2atmpS1640;
  #line 31 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallErrorS1646
  = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallError));
  Moonbit_object_header(_M0L74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallErrorS1646)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallError, $0) >> 2, 2, 5);
  ((struct _M0DTPC15error5Error74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallError*)_M0L74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallErrorS1646)->$0
  = (moonbit_string_t)moonbit_string_literal_20.data;
  ((struct _M0DTPC15error5Error74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallError*)_M0L74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallErrorS1646)->$1
  = (moonbit_string_t)moonbit_string_literal_21.data;
  _M0L11_2atry__errS673
  = _M0L74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallErrorS1646;
  goto join_672;
  join_672:;
  _M0L16_2aToolCallErrorS677
  = (struct _M0DTPC15error5Error74hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eToolCallError_2eToolCallError*)_M0L11_2atry__errS673;
  _M0L13_2atool__nameS678 = _M0L16_2aToolCallErrorS677->$0;
  _M0L8_2afieldS1883 = _M0L16_2aToolCallErrorS677->$1;
  _M0L6_2acntS2015 = Moonbit_object_header(_M0L16_2aToolCallErrorS677)->rc;
  if (_M0L6_2acntS2015 > 1) {
    int32_t _M0L11_2anew__cntS2016 = _M0L6_2acntS2015 - 1;
    Moonbit_object_header(_M0L16_2aToolCallErrorS677)->rc
    = _M0L11_2anew__cntS2016;
    moonbit_incref(_M0L8_2afieldS1883);
    moonbit_incref(_M0L13_2atool__nameS678);
  } else if (_M0L6_2acntS2015 == 1) {
    #line 32 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
    moonbit_free(_M0L16_2aToolCallErrorS677);
  }
  _M0L6_2amsgS679 = _M0L8_2afieldS1883;
  _M0L10tool__nameS675 = _M0L13_2atool__nameS678;
  _M0L3msgS676 = _M0L6_2amsgS679;
  goto join_674;
  join_674:;
  _M0L6_2atmpS1630
  = (struct _M0TPB4Show){
    _M0FP079String_2eas___40moonbitlang_2fcore_2fbuiltin_2eShow_2estatic__method__table__id,
      _M0L10tool__nameS675
  };
  _M0L6_2atmpS1633 = (moonbit_string_t)moonbit_string_literal_22.data;
  _M0L6_2atmpS1634 = (moonbit_string_t)moonbit_string_literal_23.data;
  _M0L6_2atmpS1635 = 0;
  _M0L6_2atmpS1636 = 0;
  _M0L6_2atmpS1632 = (moonbit_string_t*)moonbit_make_ref_array_raw(4);
  _M0L6_2atmpS1632[0] = _M0L6_2atmpS1633;
  _M0L6_2atmpS1632[1] = _M0L6_2atmpS1634;
  _M0L6_2atmpS1632[2] = _M0L6_2atmpS1635;
  _M0L6_2atmpS1632[3] = _M0L6_2atmpS1636;
  _M0L6_2atmpS1631
  = (struct _M0TPB5ArrayGORPB9SourceLocE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGORPB9SourceLocE));
  Moonbit_object_header(_M0L6_2atmpS1631)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGORPB9SourceLocE, $0) >> 2, 1, 0);
  _M0L6_2atmpS1631->$0 = _M0L6_2atmpS1632;
  _M0L6_2atmpS1631->$1 = 4;
  #line 36 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _tmp_2116
  = _M0FPB15inspect_2einner(_M0L6_2atmpS1630, (moonbit_string_t)moonbit_string_literal_20.data, (moonbit_string_t)moonbit_string_literal_24.data, _M0L6_2atmpS1631);
  if (_tmp_2116.tag) {
    int32_t const _M0L5_2aokS1637 = _tmp_2116.data.ok;
  } else {
    void* const _M0L6_2aerrS1638 = _tmp_2116.data.err;
    struct moonbit_result_0 _result_2117;
    moonbit_decref(_M0L3msgS676);
    _result_2117.tag = 0;
    _result_2117.data.err = _M0L6_2aerrS1638;
    return _result_2117;
  }
  _M0L6_2atmpS1639
  = (struct _M0TPB4Show){
    _M0FP079String_2eas___40moonbitlang_2fcore_2fbuiltin_2eShow_2estatic__method__table__id,
      _M0L3msgS676
  };
  _M0L6_2atmpS1642 = (moonbit_string_t)moonbit_string_literal_25.data;
  _M0L6_2atmpS1643 = (moonbit_string_t)moonbit_string_literal_26.data;
  _M0L6_2atmpS1644 = 0;
  _M0L6_2atmpS1645 = 0;
  _M0L6_2atmpS1641 = (moonbit_string_t*)moonbit_make_ref_array_raw(4);
  _M0L6_2atmpS1641[0] = _M0L6_2atmpS1642;
  _M0L6_2atmpS1641[1] = _M0L6_2atmpS1643;
  _M0L6_2atmpS1641[2] = _M0L6_2atmpS1644;
  _M0L6_2atmpS1641[3] = _M0L6_2atmpS1645;
  _M0L6_2atmpS1640
  = (struct _M0TPB5ArrayGORPB9SourceLocE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGORPB9SourceLocE));
  Moonbit_object_header(_M0L6_2atmpS1640)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGORPB9SourceLocE, $0) >> 2, 1, 0);
  _M0L6_2atmpS1640->$0 = _M0L6_2atmpS1641;
  _M0L6_2atmpS1640->$1 = 4;
  #line 37 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  return _M0FPB15inspect_2einner(_M0L6_2atmpS1639, (moonbit_string_t)moonbit_string_literal_21.data, (moonbit_string_t)moonbit_string_literal_27.data, _M0L6_2atmpS1640);
}

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__2(
  
) {
  void* _M0L11_2atry__errS665;
  void* _M0L78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestErrorS1629;
  int32_t _M0L6statusS667;
  moonbit_string_t _M0L3msgS668;
  struct _M0DTPC15error5Error78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestError* _M0L18_2aBadRequestErrorS669;
  int32_t _M0L9_2astatusS670;
  moonbit_string_t _M0L8_2afieldS1885;
  int32_t _M0L6_2acntS2017;
  moonbit_string_t _M0L6_2amsgS671;
  moonbit_string_t _M0L6_2atmpS1619;
  struct moonbit_result_0 _tmp_2120;
  struct _M0TPB4Show _M0L6_2atmpS1622;
  moonbit_string_t _M0L6_2atmpS1625;
  moonbit_string_t _M0L6_2atmpS1626;
  moonbit_string_t _M0L6_2atmpS1627;
  moonbit_string_t _M0L6_2atmpS1628;
  moonbit_string_t* _M0L6_2atmpS1624;
  struct _M0TPB5ArrayGORPB9SourceLocE* _M0L6_2atmpS1623;
  #line 19 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestErrorS1629
  = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestError));
  Moonbit_object_header(_M0L78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestErrorS1629)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestError, $1) >> 2, 1, 4);
  ((struct _M0DTPC15error5Error78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestError*)_M0L78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestErrorS1629)->$0
  = 400;
  ((struct _M0DTPC15error5Error78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestError*)_M0L78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestErrorS1629)->$1
  = (moonbit_string_t)moonbit_string_literal_28.data;
  _M0L11_2atry__errS665
  = _M0L78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestErrorS1629;
  goto join_664;
  join_664:;
  _M0L18_2aBadRequestErrorS669
  = (struct _M0DTPC15error5Error78hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eBadRequestError_2eBadRequestError*)_M0L11_2atry__errS665;
  _M0L9_2astatusS670 = _M0L18_2aBadRequestErrorS669->$0;
  _M0L8_2afieldS1885 = _M0L18_2aBadRequestErrorS669->$1;
  _M0L6_2acntS2017 = Moonbit_object_header(_M0L18_2aBadRequestErrorS669)->rc;
  if (_M0L6_2acntS2017 > 1) {
    int32_t _M0L11_2anew__cntS2018 = _M0L6_2acntS2017 - 1;
    Moonbit_object_header(_M0L18_2aBadRequestErrorS669)->rc
    = _M0L11_2anew__cntS2018;
    moonbit_incref(_M0L8_2afieldS1885);
  } else if (_M0L6_2acntS2017 == 1) {
    #line 20 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
    moonbit_free(_M0L18_2aBadRequestErrorS669);
  }
  _M0L6_2amsgS671 = _M0L8_2afieldS1885;
  _M0L6statusS667 = _M0L9_2astatusS670;
  _M0L3msgS668 = _M0L6_2amsgS671;
  goto join_666;
  join_666:;
  _M0L6_2atmpS1619 = 0;
  #line 24 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _tmp_2120
  = _M0FPB10assert__eqGiE(_M0L6statusS667, 400, _M0L6_2atmpS1619, (moonbit_string_t)moonbit_string_literal_29.data);
  if (_tmp_2120.tag) {
    int32_t const _M0L5_2aokS1620 = _tmp_2120.data.ok;
  } else {
    void* const _M0L6_2aerrS1621 = _tmp_2120.data.err;
    struct moonbit_result_0 _result_2121;
    moonbit_decref(_M0L3msgS668);
    _result_2121.tag = 0;
    _result_2121.data.err = _M0L6_2aerrS1621;
    return _result_2121;
  }
  _M0L6_2atmpS1622
  = (struct _M0TPB4Show){
    _M0FP079String_2eas___40moonbitlang_2fcore_2fbuiltin_2eShow_2estatic__method__table__id,
      _M0L3msgS668
  };
  _M0L6_2atmpS1625 = (moonbit_string_t)moonbit_string_literal_30.data;
  _M0L6_2atmpS1626 = (moonbit_string_t)moonbit_string_literal_31.data;
  _M0L6_2atmpS1627 = 0;
  _M0L6_2atmpS1628 = 0;
  _M0L6_2atmpS1624 = (moonbit_string_t*)moonbit_make_ref_array_raw(4);
  _M0L6_2atmpS1624[0] = _M0L6_2atmpS1625;
  _M0L6_2atmpS1624[1] = _M0L6_2atmpS1626;
  _M0L6_2atmpS1624[2] = _M0L6_2atmpS1627;
  _M0L6_2atmpS1624[3] = _M0L6_2atmpS1628;
  _M0L6_2atmpS1623
  = (struct _M0TPB5ArrayGORPB9SourceLocE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGORPB9SourceLocE));
  Moonbit_object_header(_M0L6_2atmpS1623)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGORPB9SourceLocE, $0) >> 2, 1, 0);
  _M0L6_2atmpS1623->$0 = _M0L6_2atmpS1624;
  _M0L6_2atmpS1623->$1 = 4;
  #line 25 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  return _M0FPB15inspect_2einner(_M0L6_2atmpS1622, (moonbit_string_t)moonbit_string_literal_28.data, (moonbit_string_t)moonbit_string_literal_32.data, _M0L6_2atmpS1623);
}

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__1(
  
) {
  void* _M0L11_2atry__errS659;
  void* _M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1618;
  moonbit_string_t _M0L3msgS661;
  struct _M0DTPC15error5Error68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentError* _M0L13_2aAgentErrorS662;
  moonbit_string_t _M0L8_2afieldS1886;
  int32_t _M0L6_2acntS2019;
  moonbit_string_t _M0L6_2amsgS663;
  struct _M0TPB4Show _M0L6_2atmpS1611;
  moonbit_string_t _M0L6_2atmpS1614;
  moonbit_string_t _M0L6_2atmpS1615;
  moonbit_string_t _M0L6_2atmpS1616;
  moonbit_string_t _M0L6_2atmpS1617;
  moonbit_string_t* _M0L6_2atmpS1613;
  struct _M0TPB5ArrayGORPB9SourceLocE* _M0L6_2atmpS1612;
  #line 10 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1618
  = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentError));
  Moonbit_object_header(_M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1618)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentError, $0) >> 2, 1, 3);
  ((struct _M0DTPC15error5Error68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentError*)_M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1618)->$0
  = (moonbit_string_t)moonbit_string_literal_33.data;
  _M0L11_2atry__errS659
  = _M0L68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentErrorS1618;
  goto join_658;
  join_658:;
  _M0L13_2aAgentErrorS662
  = (struct _M0DTPC15error5Error68hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentError_2eAgentError*)_M0L11_2atry__errS659;
  _M0L8_2afieldS1886 = _M0L13_2aAgentErrorS662->$0;
  _M0L6_2acntS2019 = Moonbit_object_header(_M0L13_2aAgentErrorS662)->rc;
  if (_M0L6_2acntS2019 > 1) {
    int32_t _M0L11_2anew__cntS2020 = _M0L6_2acntS2019 - 1;
    Moonbit_object_header(_M0L13_2aAgentErrorS662)->rc
    = _M0L11_2anew__cntS2020;
    moonbit_incref(_M0L8_2afieldS1886);
  } else if (_M0L6_2acntS2019 == 1) {
    #line 11 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
    moonbit_free(_M0L13_2aAgentErrorS662);
  }
  _M0L6_2amsgS663 = _M0L8_2afieldS1886;
  _M0L3msgS661 = _M0L6_2amsgS663;
  goto join_660;
  join_660:;
  _M0L6_2atmpS1611
  = (struct _M0TPB4Show){
    _M0FP079String_2eas___40moonbitlang_2fcore_2fbuiltin_2eShow_2estatic__method__table__id,
      _M0L3msgS661
  };
  _M0L6_2atmpS1614 = (moonbit_string_t)moonbit_string_literal_34.data;
  _M0L6_2atmpS1615 = (moonbit_string_t)moonbit_string_literal_35.data;
  _M0L6_2atmpS1616 = 0;
  _M0L6_2atmpS1617 = 0;
  _M0L6_2atmpS1613 = (moonbit_string_t*)moonbit_make_ref_array_raw(4);
  _M0L6_2atmpS1613[0] = _M0L6_2atmpS1614;
  _M0L6_2atmpS1613[1] = _M0L6_2atmpS1615;
  _M0L6_2atmpS1613[2] = _M0L6_2atmpS1616;
  _M0L6_2atmpS1613[3] = _M0L6_2atmpS1617;
  _M0L6_2atmpS1612
  = (struct _M0TPB5ArrayGORPB9SourceLocE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGORPB9SourceLocE));
  Moonbit_object_header(_M0L6_2atmpS1612)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGORPB9SourceLocE, $0) >> 2, 1, 0);
  _M0L6_2atmpS1612->$0 = _M0L6_2atmpS1613;
  _M0L6_2atmpS1612->$1 = 4;
  #line 14 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  return _M0FPB15inspect_2einner(_M0L6_2atmpS1611, (moonbit_string_t)moonbit_string_literal_33.data, (moonbit_string_t)moonbit_string_literal_36.data, _M0L6_2atmpS1612);
}

struct moonbit_result_0 _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors47____test__6572726f72735f7762746573742e6d6274__0(
  
) {
  void* _M0L11_2atry__errS653;
  void* _M0L80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterruptedS1610;
  moonbit_string_t _M0L3msgS655;
  struct _M0DTPC15error5Error80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterrupted* _M0L19_2aAgentInterruptedS656;
  moonbit_string_t _M0L8_2afieldS1887;
  int32_t _M0L6_2acntS2021;
  moonbit_string_t _M0L6_2amsgS657;
  struct _M0TPB4Show _M0L6_2atmpS1603;
  moonbit_string_t _M0L6_2atmpS1606;
  moonbit_string_t _M0L6_2atmpS1607;
  moonbit_string_t _M0L6_2atmpS1608;
  moonbit_string_t _M0L6_2atmpS1609;
  moonbit_string_t* _M0L6_2atmpS1605;
  struct _M0TPB5ArrayGORPB9SourceLocE* _M0L6_2atmpS1604;
  #line 1 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  _M0L80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterruptedS1610
  = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterrupted));
  Moonbit_object_header(_M0L80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterruptedS1610)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterrupted, $0) >> 2, 1, 2);
  ((struct _M0DTPC15error5Error80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterrupted*)_M0L80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterruptedS1610)->$0
  = (moonbit_string_t)moonbit_string_literal_37.data;
  _M0L11_2atry__errS653
  = _M0L80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterruptedS1610;
  goto join_652;
  join_652:;
  _M0L19_2aAgentInterruptedS656
  = (struct _M0DTPC15error5Error80hnlyxiaobing_2fMBOpenClacky_2flib_2ferrors_2eAgentInterrupted_2eAgentInterrupted*)_M0L11_2atry__errS653;
  _M0L8_2afieldS1887 = _M0L19_2aAgentInterruptedS656->$0;
  _M0L6_2acntS2021 = Moonbit_object_header(_M0L19_2aAgentInterruptedS656)->rc;
  if (_M0L6_2acntS2021 > 1) {
    int32_t _M0L11_2anew__cntS2022 = _M0L6_2acntS2021 - 1;
    Moonbit_object_header(_M0L19_2aAgentInterruptedS656)->rc
    = _M0L11_2anew__cntS2022;
    moonbit_incref(_M0L8_2afieldS1887);
  } else if (_M0L6_2acntS2021 == 1) {
    #line 2 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
    moonbit_free(_M0L19_2aAgentInterruptedS656);
  }
  _M0L6_2amsgS657 = _M0L8_2afieldS1887;
  _M0L3msgS655 = _M0L6_2amsgS657;
  goto join_654;
  join_654:;
  _M0L6_2atmpS1603
  = (struct _M0TPB4Show){
    _M0FP079String_2eas___40moonbitlang_2fcore_2fbuiltin_2eShow_2estatic__method__table__id,
      _M0L3msgS655
  };
  _M0L6_2atmpS1606 = (moonbit_string_t)moonbit_string_literal_38.data;
  _M0L6_2atmpS1607 = (moonbit_string_t)moonbit_string_literal_39.data;
  _M0L6_2atmpS1608 = 0;
  _M0L6_2atmpS1609 = 0;
  _M0L6_2atmpS1605 = (moonbit_string_t*)moonbit_make_ref_array_raw(4);
  _M0L6_2atmpS1605[0] = _M0L6_2atmpS1606;
  _M0L6_2atmpS1605[1] = _M0L6_2atmpS1607;
  _M0L6_2atmpS1605[2] = _M0L6_2atmpS1608;
  _M0L6_2atmpS1605[3] = _M0L6_2atmpS1609;
  _M0L6_2atmpS1604
  = (struct _M0TPB5ArrayGORPB9SourceLocE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGORPB9SourceLocE));
  Moonbit_object_header(_M0L6_2atmpS1604)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGORPB9SourceLocE, $0) >> 2, 1, 0);
  _M0L6_2atmpS1604->$0 = _M0L6_2atmpS1605;
  _M0L6_2atmpS1604->$1 = 4;
  #line 5 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\errors_wbtest.mbt"
  return _M0FPB15inspect_2einner(_M0L6_2atmpS1603, (moonbit_string_t)moonbit_string_literal_37.data, (moonbit_string_t)moonbit_string_literal_40.data, _M0L6_2atmpS1604);
}

moonbit_string_t _M0MPC15array5Array2atGsE(
  struct _M0TPB5ArrayGsE* _M0L4selfS650,
  int32_t _M0L5indexS651
) {
  int32_t _M0L3lenS649;
  int32_t _if__result_2126;
  #line 183 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\array.mbt"
  _M0L3lenS649 = _M0L4selfS650->$1;
  if (_M0L5indexS651 >= 0) {
    _if__result_2126 = _M0L5indexS651 < _M0L3lenS649;
  } else {
    _if__result_2126 = 0;
  }
  if (_if__result_2126) {
    moonbit_string_t* _M0L6_2atmpS1602;
    moonbit_string_t _M0L6_2atmpS1888;
    #line 188 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\array.mbt"
    _M0L6_2atmpS1602 = _M0MPC15array5Array6bufferGsE(_M0L4selfS650);
    if (
      _M0L5indexS651 < 0
      || _M0L5indexS651 >= Moonbit_array_length(_M0L6_2atmpS1602)
    ) {
      #line 188 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\array.mbt"
      moonbit_panic();
    }
    _M0L6_2atmpS1888 = (moonbit_string_t)_M0L6_2atmpS1602[_M0L5indexS651];
    moonbit_incref(_M0L6_2atmpS1888);
    moonbit_decref(_M0L6_2atmpS1602);
    return _M0L6_2atmpS1888;
  } else {
    moonbit_decref(_M0L4selfS650);
    #line 187 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\array.mbt"
    moonbit_panic();
  }
}

moonbit_string_t _M0IPB9SourceLocPB4Show10to__string(
  moonbit_string_t _M0L4selfS648
) {
  #line 48 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  return _M0L4selfS648;
}

int32_t _M0FPB7printlnGsE(moonbit_string_t _M0L5inputS647) {
  moonbit_string_t _M0L6_2atmpS1601;
  #line 37 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  #line 38 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  _M0L6_2atmpS1601 = _M0IPC16string6StringPB4Show10to__string(_M0L5inputS647);
  #line 38 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  moonbit_println(_M0L6_2atmpS1601);
  moonbit_decref(_M0L6_2atmpS1601);
  return 0;
}

struct moonbit_result_0 _M0FPB12assert__true(
  int32_t _M0L1xS642,
  moonbit_string_t _M0L3msgS644,
  moonbit_string_t _M0L3locS646
) {
  #line 123 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
  if (!_M0L1xS642) {
    moonbit_string_t _M0L9fail__msgS643;
    if (_M0L3msgS644 == 0) {
      moonbit_string_t _M0L6_2atmpS1599;
      moonbit_string_t _M0L6_2atmpS1598;
      if (_M0L3msgS644) {
        moonbit_decref(_M0L3msgS644);
      }
      #line 129 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
      _M0L6_2atmpS1599 = _M0IPC14bool4BoolPB4Show10to__string(_M0L1xS642);
      #line 127 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
      _M0L6_2atmpS1598
      = moonbit_add_string((moonbit_string_t)moonbit_string_literal_41.data, _M0L6_2atmpS1599);
      moonbit_decref(_M0L6_2atmpS1599);
      #line 127 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
      _M0L9fail__msgS643
      = moonbit_add_string(_M0L6_2atmpS1598, (moonbit_string_t)moonbit_string_literal_42.data);
      moonbit_decref(_M0L6_2atmpS1598);
    } else {
      moonbit_string_t _M0L7_2aSomeS645 = _M0L3msgS644;
      _M0L9fail__msgS643 = _M0L7_2aSomeS645;
    }
    #line 131 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
    return _M0FPB4failGuE(_M0L9fail__msgS643, _M0L3locS646);
  } else {
    int32_t _M0L6_2atmpS1600;
    struct moonbit_result_0 _result_2127;
    moonbit_decref(_M0L3locS646);
    if (_M0L3msgS644) {
      moonbit_decref(_M0L3msgS644);
    }
    _M0L6_2atmpS1600 = 0;
    _result_2127.tag = 1;
    _result_2127.data.ok = _M0L6_2atmpS1600;
    return _result_2127;
  }
}

struct moonbit_result_0 _M0FPB13assert__false(
  int32_t _M0L1xS637,
  moonbit_string_t _M0L3msgS639,
  moonbit_string_t _M0L3locS641
) {
  #line 156 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
  if (_M0L1xS637) {
    moonbit_string_t _M0L9fail__msgS638;
    if (_M0L3msgS639 == 0) {
      moonbit_string_t _M0L6_2atmpS1596;
      moonbit_string_t _M0L6_2atmpS1595;
      if (_M0L3msgS639) {
        moonbit_decref(_M0L3msgS639);
      }
      #line 162 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
      _M0L6_2atmpS1596 = _M0IPC14bool4BoolPB4Show10to__string(_M0L1xS637);
      #line 160 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
      _M0L6_2atmpS1595
      = moonbit_add_string((moonbit_string_t)moonbit_string_literal_41.data, _M0L6_2atmpS1596);
      moonbit_decref(_M0L6_2atmpS1596);
      #line 160 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
      _M0L9fail__msgS638
      = moonbit_add_string(_M0L6_2atmpS1595, (moonbit_string_t)moonbit_string_literal_43.data);
      moonbit_decref(_M0L6_2atmpS1595);
    } else {
      moonbit_string_t _M0L7_2aSomeS640 = _M0L3msgS639;
      _M0L9fail__msgS638 = _M0L7_2aSomeS640;
    }
    #line 164 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
    return _M0FPB4failGuE(_M0L9fail__msgS638, _M0L3locS641);
  } else {
    int32_t _M0L6_2atmpS1597;
    struct moonbit_result_0 _result_2128;
    moonbit_decref(_M0L3locS641);
    if (_M0L3msgS639) {
      moonbit_decref(_M0L3msgS639);
    }
    _M0L6_2atmpS1597 = 0;
    _result_2128.tag = 1;
    _result_2128.data.ok = _M0L6_2atmpS1597;
    return _result_2128;
  }
}

int32_t _M0IPC13int3IntPB4Hash13hash__combine(
  int32_t _M0L4selfS636,
  struct _M0TPB6Hasher* _M0L6hasherS635
) {
  #line 530 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  #line 531 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0MPB6Hasher12combine__int(_M0L6hasherS635, _M0L4selfS636);
  return 0;
}

int32_t _M0IPC16string6StringPB4Hash13hash__combine(
  moonbit_string_t _M0L4selfS634,
  struct _M0TPB6Hasher* _M0L6hasherS633
) {
  #line 496 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  #line 497 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0MPB6Hasher15combine__string(_M0L6hasherS633, _M0L4selfS634);
  return 0;
}

int32_t _M0MPB6Hasher15combine__string(
  struct _M0TPB6Hasher* _M0L4selfS631,
  moonbit_string_t _M0L5valueS629
) {
  int32_t _M0L7_2abindS628;
  int32_t _M0L1iS630;
  #line 387 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0L7_2abindS628 = Moonbit_array_length(_M0L5valueS629);
  _M0L1iS630 = 0;
  while (1) {
    if (_M0L1iS630 < _M0L7_2abindS628) {
      int32_t _M0L6_2atmpS1593 = _M0L5valueS629[_M0L1iS630];
      int32_t _M0L6_2atmpS1592 = (int32_t)_M0L6_2atmpS1593;
      uint32_t _M0L6_2atmpS1591 = *(uint32_t*)&_M0L6_2atmpS1592;
      int32_t _M0L6_2atmpS1594;
      moonbit_incref(_M0L4selfS631);
      #line 389 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
      _M0MPB6Hasher13combine__uint(_M0L4selfS631, _M0L6_2atmpS1591);
      _M0L6_2atmpS1594 = _M0L1iS630 + 1;
      _M0L1iS630 = _M0L6_2atmpS1594;
      continue;
    } else {
      moonbit_decref(_M0L4selfS631);
      moonbit_decref(_M0L5valueS629);
    }
    break;
  }
  return 0;
}

int32_t _M0MPC16string6String20unsafe__charcode__at(
  moonbit_string_t _M0L4selfS626,
  int32_t _M0L3idxS627
) {
  int32_t _result_2130;
  #line 1778 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\intrinsics.mbt"
  _result_2130 = _M0L4selfS626[_M0L3idxS627];
  moonbit_decref(_M0L4selfS626);
  return _result_2130;
}

struct _M0TUWEuQRPC15error5ErrorNsE* _M0MPB3Map3getGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L4selfS613,
  int32_t _M0L3keyS609
) {
  int32_t _M0L4hashS608;
  int32_t _M0L14capacity__maskS1576;
  int32_t _M0L6_2atmpS1575;
  int32_t _M0L1iS610;
  int32_t _M0L3idxS611;
  #line 217 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  #line 218 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L4hashS608 = _M0IP016_24default__implPB4Hash4hashGiE(_M0L3keyS609);
  _M0L14capacity__maskS1576 = _M0L4selfS613->$3;
  _M0L6_2atmpS1575 = _M0L4hashS608 & _M0L14capacity__maskS1576;
  _M0L1iS610 = 0;
  _M0L3idxS611 = _M0L6_2atmpS1575;
  while (1) {
    struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE** _M0L7entriesS1574 =
      _M0L4selfS613->$0;
    struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2abindS612;
    if (
      _M0L3idxS611 < 0
      || _M0L3idxS611 >= Moonbit_array_length(_M0L7entriesS1574)
    ) {
      #line 220 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      moonbit_panic();
    }
    _M0L7_2abindS612
    = (struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE*)_M0L7entriesS1574[
        _M0L3idxS611
      ];
    if (_M0L7_2abindS612 == 0) {
      struct _M0TUWEuQRPC15error5ErrorNsE* _M0L6_2atmpS1563;
      if (_M0L7_2abindS612) {
        moonbit_incref(_M0L7_2abindS612);
      }
      moonbit_decref(_M0L4selfS613);
      if (_M0L7_2abindS612) {
        moonbit_decref(_M0L7_2abindS612);
      }
      _M0L6_2atmpS1563 = 0;
      return _M0L6_2atmpS1563;
    } else {
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2aSomeS614 =
        _M0L7_2abindS612;
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L8_2aentryS615 =
        _M0L7_2aSomeS614;
      int32_t _M0L4hashS1565 = _M0L8_2aentryS615->$3;
      int32_t _if__result_2132;
      int32_t _M0L3pslS1568;
      int32_t _M0L6_2atmpS1570;
      int32_t _M0L6_2atmpS1572;
      int32_t _M0L14capacity__maskS1573;
      int32_t _M0L6_2atmpS1571;
      if (_M0L4hashS1565 == _M0L4hashS608) {
        int32_t _M0L3keyS1564 = _M0L8_2aentryS615->$4;
        _if__result_2132 = _M0L3keyS1564 == _M0L3keyS609;
      } else {
        _if__result_2132 = 0;
      }
      if (_if__result_2132) {
        struct _M0TUWEuQRPC15error5ErrorNsE* _M0L8_2afieldS1889;
        int32_t _M0L6_2acntS2023;
        struct _M0TUWEuQRPC15error5ErrorNsE* _M0L5valueS1567;
        struct _M0TUWEuQRPC15error5ErrorNsE* _M0L6_2atmpS1566;
        moonbit_incref(_M0L8_2aentryS615);
        moonbit_decref(_M0L4selfS613);
        _M0L8_2afieldS1889 = _M0L8_2aentryS615->$5;
        _M0L6_2acntS2023 = Moonbit_object_header(_M0L8_2aentryS615)->rc;
        if (_M0L6_2acntS2023 > 1) {
          int32_t _M0L11_2anew__cntS2025 = _M0L6_2acntS2023 - 1;
          Moonbit_object_header(_M0L8_2aentryS615)->rc
          = _M0L11_2anew__cntS2025;
          moonbit_incref(_M0L8_2afieldS1889);
        } else if (_M0L6_2acntS2023 == 1) {
          struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L8_2afieldS2024 =
            _M0L8_2aentryS615->$1;
          if (_M0L8_2afieldS2024) {
            moonbit_decref(_M0L8_2afieldS2024);
          }
          #line 222 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
          moonbit_free(_M0L8_2aentryS615);
        }
        _M0L5valueS1567 = _M0L8_2afieldS1889;
        _M0L6_2atmpS1566 = _M0L5valueS1567;
        return _M0L6_2atmpS1566;
      } else {
        moonbit_incref(_M0L8_2aentryS615);
      }
      _M0L3pslS1568 = _M0L8_2aentryS615->$2;
      moonbit_decref(_M0L8_2aentryS615);
      if (_M0L1iS610 > _M0L3pslS1568) {
        struct _M0TUWEuQRPC15error5ErrorNsE* _M0L6_2atmpS1569;
        moonbit_decref(_M0L4selfS613);
        _M0L6_2atmpS1569 = 0;
        return _M0L6_2atmpS1569;
      }
      _M0L6_2atmpS1570 = _M0L1iS610 + 1;
      _M0L6_2atmpS1572 = _M0L3idxS611 + 1;
      _M0L14capacity__maskS1573 = _M0L4selfS613->$3;
      _M0L6_2atmpS1571 = _M0L6_2atmpS1572 & _M0L14capacity__maskS1573;
      _M0L1iS610 = _M0L6_2atmpS1570;
      _M0L3idxS611 = _M0L6_2atmpS1571;
      continue;
    }
    break;
  }
}

struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0MPB3Map3getGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L4selfS622,
  moonbit_string_t _M0L3keyS618
) {
  int32_t _M0L4hashS617;
  int32_t _M0L14capacity__maskS1590;
  int32_t _M0L6_2atmpS1589;
  int32_t _M0L1iS619;
  int32_t _M0L3idxS620;
  #line 217 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  moonbit_incref(_M0L3keyS618);
  #line 218 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L4hashS617 = _M0IP016_24default__implPB4Hash4hashGsE(_M0L3keyS618);
  _M0L14capacity__maskS1590 = _M0L4selfS622->$3;
  _M0L6_2atmpS1589 = _M0L4hashS617 & _M0L14capacity__maskS1590;
  _M0L1iS619 = 0;
  _M0L3idxS620 = _M0L6_2atmpS1589;
  while (1) {
    struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE** _M0L7entriesS1588 =
      _M0L4selfS622->$0;
    struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2abindS621;
    if (
      _M0L3idxS620 < 0
      || _M0L3idxS620 >= Moonbit_array_length(_M0L7entriesS1588)
    ) {
      #line 220 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      moonbit_panic();
    }
    _M0L7_2abindS621
    = (struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*)_M0L7entriesS1588[
        _M0L3idxS620
      ];
    if (_M0L7_2abindS621 == 0) {
      struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L6_2atmpS1577;
      if (_M0L7_2abindS621) {
        moonbit_incref(_M0L7_2abindS621);
      }
      moonbit_decref(_M0L4selfS622);
      if (_M0L7_2abindS621) {
        moonbit_decref(_M0L7_2abindS621);
      }
      moonbit_decref(_M0L3keyS618);
      _M0L6_2atmpS1577 = 0;
      return _M0L6_2atmpS1577;
    } else {
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2aSomeS623 =
        _M0L7_2abindS621;
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L8_2aentryS624 =
        _M0L7_2aSomeS623;
      int32_t _M0L4hashS1579 = _M0L8_2aentryS624->$3;
      int32_t _if__result_2134;
      int32_t _M0L3pslS1582;
      int32_t _M0L6_2atmpS1584;
      int32_t _M0L6_2atmpS1586;
      int32_t _M0L14capacity__maskS1587;
      int32_t _M0L6_2atmpS1585;
      if (_M0L4hashS1579 == _M0L4hashS617) {
        moonbit_string_t _M0L3keyS1578 = _M0L8_2aentryS624->$4;
        #line 221 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
        _if__result_2134
        = moonbit_val_array_equal(_M0L3keyS1578, _M0L3keyS618);
      } else {
        _if__result_2134 = 0;
      }
      if (_if__result_2134) {
        struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L8_2afieldS1892;
        int32_t _M0L6_2acntS2026;
        struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L5valueS1581;
        struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L6_2atmpS1580;
        moonbit_incref(_M0L8_2aentryS624);
        moonbit_decref(_M0L4selfS622);
        moonbit_decref(_M0L3keyS618);
        _M0L8_2afieldS1892 = _M0L8_2aentryS624->$5;
        _M0L6_2acntS2026 = Moonbit_object_header(_M0L8_2aentryS624)->rc;
        if (_M0L6_2acntS2026 > 1) {
          int32_t _M0L11_2anew__cntS2029 = _M0L6_2acntS2026 - 1;
          Moonbit_object_header(_M0L8_2aentryS624)->rc
          = _M0L11_2anew__cntS2029;
          moonbit_incref(_M0L8_2afieldS1892);
        } else if (_M0L6_2acntS2026 == 1) {
          moonbit_string_t _M0L8_2afieldS2028 = _M0L8_2aentryS624->$4;
          struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L8_2afieldS2027;
          moonbit_decref(_M0L8_2afieldS2028);
          _M0L8_2afieldS2027 = _M0L8_2aentryS624->$1;
          if (_M0L8_2afieldS2027) {
            moonbit_decref(_M0L8_2afieldS2027);
          }
          #line 222 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
          moonbit_free(_M0L8_2aentryS624);
        }
        _M0L5valueS1581 = _M0L8_2afieldS1892;
        _M0L6_2atmpS1580 = _M0L5valueS1581;
        return _M0L6_2atmpS1580;
      } else {
        moonbit_incref(_M0L8_2aentryS624);
      }
      _M0L3pslS1582 = _M0L8_2aentryS624->$2;
      moonbit_decref(_M0L8_2aentryS624);
      if (_M0L1iS619 > _M0L3pslS1582) {
        struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L6_2atmpS1583;
        moonbit_decref(_M0L4selfS622);
        moonbit_decref(_M0L3keyS618);
        _M0L6_2atmpS1583 = 0;
        return _M0L6_2atmpS1583;
      }
      _M0L6_2atmpS1584 = _M0L1iS619 + 1;
      _M0L6_2atmpS1586 = _M0L3idxS620 + 1;
      _M0L14capacity__maskS1587 = _M0L4selfS622->$3;
      _M0L6_2atmpS1585 = _M0L6_2atmpS1586 & _M0L14capacity__maskS1587;
      _M0L1iS619 = _M0L6_2atmpS1584;
      _M0L3idxS620 = _M0L6_2atmpS1585;
      continue;
    }
    break;
  }
}

struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0MPB3Map11from__arrayGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB9ArrayViewGUsRPB3MapGiUWEuQRPC15error5ErrorNsEEEE _M0L3arrS593
) {
  int32_t _M0L6lengthS592;
  int32_t _M0Lm8capacityS594;
  int32_t _M0L6_2atmpS1540;
  int32_t _M0L6_2atmpS1539;
  int32_t _M0L6_2atmpS1550;
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L1mS595;
  int32_t _M0L3endS1548;
  int32_t _M0L5startS1549;
  int32_t _M0L7_2abindS596;
  int32_t _M0L2__S597;
  #line 73 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  moonbit_incref(_M0L3arrS593.$0);
  #line 74 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L6lengthS592
  = _M0MPC15array9ArrayView6lengthGUsRPB3MapGiUWEuQRPC15error5ErrorNsEEEE(_M0L3arrS593);
  #line 75 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0Lm8capacityS594 = _M0MPC13int3Int20next__power__of__two(_M0L6lengthS592);
  _M0L6_2atmpS1540 = _M0Lm8capacityS594;
  #line 76 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L6_2atmpS1539 = _M0FPB21calc__grow__threshold(_M0L6_2atmpS1540);
  if (_M0L6lengthS592 > _M0L6_2atmpS1539) {
    int32_t _M0L6_2atmpS1541 = _M0Lm8capacityS594;
    _M0Lm8capacityS594 = _M0L6_2atmpS1541 * 2;
  }
  _M0L6_2atmpS1550 = _M0Lm8capacityS594;
  #line 79 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L1mS595
  = _M0MPB3Map11new_2einnerGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(_M0L6_2atmpS1550);
  _M0L3endS1548 = _M0L3arrS593.$2;
  _M0L5startS1549 = _M0L3arrS593.$1;
  _M0L7_2abindS596 = _M0L3endS1548 - _M0L5startS1549;
  _M0L2__S597 = 0;
  while (1) {
    if (_M0L2__S597 < _M0L7_2abindS596) {
      struct _M0TUsRPB3MapGiUWEuQRPC15error5ErrorNsEEE** _M0L3bufS1545 =
        _M0L3arrS593.$0;
      int32_t _M0L5startS1547 = _M0L3arrS593.$1;
      int32_t _M0L6_2atmpS1546 = _M0L5startS1547 + _M0L2__S597;
      struct _M0TUsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L1eS598 =
        (struct _M0TUsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*)_M0L3bufS1545[
          _M0L6_2atmpS1546
        ];
      moonbit_string_t _M0L6_2atmpS1542 = _M0L1eS598->$0;
      struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L6_2atmpS1543 =
        _M0L1eS598->$1;
      int32_t _M0L6_2atmpS1544;
      moonbit_incref(_M0L6_2atmpS1543);
      moonbit_incref(_M0L6_2atmpS1542);
      moonbit_incref(_M0L1mS595);
      #line 81 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      _M0MPB3Map3setGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(_M0L1mS595, _M0L6_2atmpS1542, _M0L6_2atmpS1543);
      _M0L6_2atmpS1544 = _M0L2__S597 + 1;
      _M0L2__S597 = _M0L6_2atmpS1544;
      continue;
    } else {
      moonbit_decref(_M0L3arrS593.$0);
    }
    break;
  }
  return _M0L1mS595;
}

struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0MPB3Map11from__arrayGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB9ArrayViewGUiUWEuQRPC15error5ErrorNsEEE _M0L3arrS601
) {
  int32_t _M0L6lengthS600;
  int32_t _M0Lm8capacityS602;
  int32_t _M0L6_2atmpS1552;
  int32_t _M0L6_2atmpS1551;
  int32_t _M0L6_2atmpS1562;
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L1mS603;
  int32_t _M0L3endS1560;
  int32_t _M0L5startS1561;
  int32_t _M0L7_2abindS604;
  int32_t _M0L2__S605;
  #line 73 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  moonbit_incref(_M0L3arrS601.$0);
  #line 74 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L6lengthS600
  = _M0MPC15array9ArrayView6lengthGUiUWEuQRPC15error5ErrorNsEEE(_M0L3arrS601);
  #line 75 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0Lm8capacityS602 = _M0MPC13int3Int20next__power__of__two(_M0L6lengthS600);
  _M0L6_2atmpS1552 = _M0Lm8capacityS602;
  #line 76 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L6_2atmpS1551 = _M0FPB21calc__grow__threshold(_M0L6_2atmpS1552);
  if (_M0L6lengthS600 > _M0L6_2atmpS1551) {
    int32_t _M0L6_2atmpS1553 = _M0Lm8capacityS602;
    _M0Lm8capacityS602 = _M0L6_2atmpS1553 * 2;
  }
  _M0L6_2atmpS1562 = _M0Lm8capacityS602;
  #line 79 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L1mS603
  = _M0MPB3Map11new_2einnerGiUWEuQRPC15error5ErrorNsEE(_M0L6_2atmpS1562);
  _M0L3endS1560 = _M0L3arrS601.$2;
  _M0L5startS1561 = _M0L3arrS601.$1;
  _M0L7_2abindS604 = _M0L3endS1560 - _M0L5startS1561;
  _M0L2__S605 = 0;
  while (1) {
    if (_M0L2__S605 < _M0L7_2abindS604) {
      struct _M0TUiUWEuQRPC15error5ErrorNsEE** _M0L3bufS1557 =
        _M0L3arrS601.$0;
      int32_t _M0L5startS1559 = _M0L3arrS601.$1;
      int32_t _M0L6_2atmpS1558 = _M0L5startS1559 + _M0L2__S605;
      struct _M0TUiUWEuQRPC15error5ErrorNsEE* _M0L1eS606 =
        (struct _M0TUiUWEuQRPC15error5ErrorNsEE*)_M0L3bufS1557[
          _M0L6_2atmpS1558
        ];
      int32_t _M0L6_2atmpS1554 = _M0L1eS606->$0;
      struct _M0TUWEuQRPC15error5ErrorNsE* _M0L6_2atmpS1555 = _M0L1eS606->$1;
      int32_t _M0L6_2atmpS1556;
      moonbit_incref(_M0L6_2atmpS1555);
      moonbit_incref(_M0L1mS603);
      #line 81 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      _M0MPB3Map3setGiUWEuQRPC15error5ErrorNsEE(_M0L1mS603, _M0L6_2atmpS1554, _M0L6_2atmpS1555);
      _M0L6_2atmpS1556 = _M0L2__S605 + 1;
      _M0L2__S605 = _M0L6_2atmpS1556;
      continue;
    } else {
      moonbit_decref(_M0L3arrS601.$0);
    }
    break;
  }
  return _M0L1mS603;
}

int32_t _M0MPB3Map3setGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L4selfS586,
  moonbit_string_t _M0L3keyS587,
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L5valueS588
) {
  int32_t _M0L6_2atmpS1537;
  #line 108 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  moonbit_incref(_M0L3keyS587);
  #line 110 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L6_2atmpS1537 = _M0IP016_24default__implPB4Hash4hashGsE(_M0L3keyS587);
  #line 110 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0MPB3Map15set__with__hashGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(_M0L4selfS586, _M0L3keyS587, _M0L5valueS588, _M0L6_2atmpS1537);
  return 0;
}

int32_t _M0MPB3Map3setGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L4selfS589,
  int32_t _M0L3keyS590,
  struct _M0TUWEuQRPC15error5ErrorNsE* _M0L5valueS591
) {
  int32_t _M0L6_2atmpS1538;
  #line 108 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  #line 110 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L6_2atmpS1538 = _M0IP016_24default__implPB4Hash4hashGiE(_M0L3keyS590);
  #line 110 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0MPB3Map15set__with__hashGiUWEuQRPC15error5ErrorNsEE(_M0L4selfS589, _M0L3keyS590, _M0L5valueS591, _M0L6_2atmpS1538);
  return 0;
}

int32_t _M0MPB3Map4growGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L4selfS565
) {
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L9old__headS564;
  int32_t _M0L8capacityS1529;
  int32_t _M0L13new__capacityS566;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L6_2atmpS1524;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE** _M0L6_2atmpS1523;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE** _M0L6_2aoldS1907;
  int32_t _M0L6_2atmpS1525;
  int32_t _M0L8capacityS1527;
  int32_t _M0L6_2atmpS1526;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L6_2atmpS1528;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L6_2aoldS1906;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L1xS567;
  #line 489 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L9old__headS564 = _M0L4selfS565->$5;
  _M0L8capacityS1529 = _M0L4selfS565->$2;
  _M0L13new__capacityS566 = _M0L8capacityS1529 << 1;
  _M0L6_2atmpS1524 = 0;
  _M0L6_2atmpS1523
  = (struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE**)moonbit_make_ref_array(_M0L13new__capacityS566, _M0L6_2atmpS1524);
  _M0L6_2aoldS1907 = _M0L4selfS565->$0;
  if (_M0L9old__headS564) {
    moonbit_incref(_M0L9old__headS564);
  }
  moonbit_decref(_M0L6_2aoldS1907);
  _M0L4selfS565->$0 = _M0L6_2atmpS1523;
  _M0L4selfS565->$2 = _M0L13new__capacityS566;
  _M0L6_2atmpS1525 = _M0L13new__capacityS566 - 1;
  _M0L4selfS565->$3 = _M0L6_2atmpS1525;
  _M0L8capacityS1527 = _M0L4selfS565->$2;
  #line 495 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L6_2atmpS1526 = _M0FPB21calc__grow__threshold(_M0L8capacityS1527);
  _M0L4selfS565->$4 = _M0L6_2atmpS1526;
  _M0L4selfS565->$1 = 0;
  _M0L6_2atmpS1528 = 0;
  _M0L6_2aoldS1906 = _M0L4selfS565->$5;
  if (_M0L6_2aoldS1906) {
    moonbit_decref(_M0L6_2aoldS1906);
  }
  _M0L4selfS565->$5 = _M0L6_2atmpS1528;
  _M0L4selfS565->$6 = -1;
  _M0L1xS567 = _M0L9old__headS564;
  while (1) {
    if (_M0L1xS567 == 0) {
      if (_M0L1xS567) {
        moonbit_decref(_M0L1xS567);
      }
      moonbit_decref(_M0L4selfS565);
      break;
    } else {
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2aSomeS568 =
        _M0L1xS567;
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L4_2axS569 =
        _M0L7_2aSomeS568;
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2anextS570 =
        _M0L4_2axS569->$1;
      moonbit_string_t _M0L6_2akeyS571 = _M0L4_2axS569->$4;
      struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L8_2avalueS572 =
        _M0L4_2axS569->$5;
      int32_t _M0L7_2ahashS573 = _M0L4_2axS569->$3;
      int32_t _M0L6_2acntS2030 = Moonbit_object_header(_M0L4_2axS569)->rc;
      if (_M0L6_2acntS2030 > 1) {
        int32_t _M0L11_2anew__cntS2031 = _M0L6_2acntS2030 - 1;
        Moonbit_object_header(_M0L4_2axS569)->rc = _M0L11_2anew__cntS2031;
        moonbit_incref(_M0L8_2avalueS572);
        moonbit_incref(_M0L6_2akeyS571);
        if (_M0L7_2anextS570) {
          moonbit_incref(_M0L7_2anextS570);
        }
      } else if (_M0L6_2acntS2030 == 1) {
        #line 499 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
        moonbit_free(_M0L4_2axS569);
      }
      moonbit_incref(_M0L4selfS565);
      #line 502 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      _M0MPB3Map15set__with__hashGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(_M0L4selfS565, _M0L6_2akeyS571, _M0L8_2avalueS572, _M0L7_2ahashS573);
      _M0L1xS567 = _M0L7_2anextS570;
      continue;
    }
    break;
  }
  return 0;
}

int32_t _M0MPB3Map4growGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L4selfS576
) {
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L9old__headS575;
  int32_t _M0L8capacityS1536;
  int32_t _M0L13new__capacityS577;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L6_2atmpS1531;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE** _M0L6_2atmpS1530;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE** _M0L6_2aoldS1912;
  int32_t _M0L6_2atmpS1532;
  int32_t _M0L8capacityS1534;
  int32_t _M0L6_2atmpS1533;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L6_2atmpS1535;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L6_2aoldS1911;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L1xS578;
  #line 489 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L9old__headS575 = _M0L4selfS576->$5;
  _M0L8capacityS1536 = _M0L4selfS576->$2;
  _M0L13new__capacityS577 = _M0L8capacityS1536 << 1;
  _M0L6_2atmpS1531 = 0;
  _M0L6_2atmpS1530
  = (struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE**)moonbit_make_ref_array(_M0L13new__capacityS577, _M0L6_2atmpS1531);
  _M0L6_2aoldS1912 = _M0L4selfS576->$0;
  if (_M0L9old__headS575) {
    moonbit_incref(_M0L9old__headS575);
  }
  moonbit_decref(_M0L6_2aoldS1912);
  _M0L4selfS576->$0 = _M0L6_2atmpS1530;
  _M0L4selfS576->$2 = _M0L13new__capacityS577;
  _M0L6_2atmpS1532 = _M0L13new__capacityS577 - 1;
  _M0L4selfS576->$3 = _M0L6_2atmpS1532;
  _M0L8capacityS1534 = _M0L4selfS576->$2;
  #line 495 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L6_2atmpS1533 = _M0FPB21calc__grow__threshold(_M0L8capacityS1534);
  _M0L4selfS576->$4 = _M0L6_2atmpS1533;
  _M0L4selfS576->$1 = 0;
  _M0L6_2atmpS1535 = 0;
  _M0L6_2aoldS1911 = _M0L4selfS576->$5;
  if (_M0L6_2aoldS1911) {
    moonbit_decref(_M0L6_2aoldS1911);
  }
  _M0L4selfS576->$5 = _M0L6_2atmpS1535;
  _M0L4selfS576->$6 = -1;
  _M0L1xS578 = _M0L9old__headS575;
  while (1) {
    if (_M0L1xS578 == 0) {
      if (_M0L1xS578) {
        moonbit_decref(_M0L1xS578);
      }
      moonbit_decref(_M0L4selfS576);
      break;
    } else {
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2aSomeS579 =
        _M0L1xS578;
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L4_2axS580 =
        _M0L7_2aSomeS579;
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2anextS581 =
        _M0L4_2axS580->$1;
      int32_t _M0L6_2akeyS582 = _M0L4_2axS580->$4;
      struct _M0TUWEuQRPC15error5ErrorNsE* _M0L8_2avalueS583 =
        _M0L4_2axS580->$5;
      int32_t _M0L7_2ahashS584 = _M0L4_2axS580->$3;
      int32_t _M0L6_2acntS2032 = Moonbit_object_header(_M0L4_2axS580)->rc;
      if (_M0L6_2acntS2032 > 1) {
        int32_t _M0L11_2anew__cntS2033 = _M0L6_2acntS2032 - 1;
        Moonbit_object_header(_M0L4_2axS580)->rc = _M0L11_2anew__cntS2033;
        moonbit_incref(_M0L8_2avalueS583);
        if (_M0L7_2anextS581) {
          moonbit_incref(_M0L7_2anextS581);
        }
      } else if (_M0L6_2acntS2032 == 1) {
        #line 499 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
        moonbit_free(_M0L4_2axS580);
      }
      moonbit_incref(_M0L4selfS576);
      #line 502 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      _M0MPB3Map15set__with__hashGiUWEuQRPC15error5ErrorNsEE(_M0L4selfS576, _M0L6_2akeyS582, _M0L8_2avalueS583, _M0L7_2ahashS584);
      _M0L1xS578 = _M0L7_2anextS581;
      continue;
    }
    break;
  }
  return 0;
}

int32_t _M0MPB3Map15set__with__hashGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L4selfS535,
  moonbit_string_t _M0L3keyS541,
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L5valueS542,
  int32_t _M0L4hashS537
) {
  int32_t _M0L14capacity__maskS1504;
  int32_t _M0L6_2atmpS1503;
  int32_t _M0L3pslS532;
  int32_t _M0L3idxS533;
  #line 114 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L14capacity__maskS1504 = _M0L4selfS535->$3;
  _M0L6_2atmpS1503 = _M0L4hashS537 & _M0L14capacity__maskS1504;
  _M0L3pslS532 = 0;
  _M0L3idxS533 = _M0L6_2atmpS1503;
  while (1) {
    struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE** _M0L7entriesS1502 =
      _M0L4selfS535->$0;
    struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2abindS534;
    if (
      _M0L3idxS533 < 0
      || _M0L3idxS533 >= Moonbit_array_length(_M0L7entriesS1502)
    ) {
      #line 122 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      moonbit_panic();
    }
    _M0L7_2abindS534
    = (struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*)_M0L7entriesS1502[
        _M0L3idxS533
      ];
    if (_M0L7_2abindS534 == 0) {
      int32_t _M0L4sizeS1487 = _M0L4selfS535->$1;
      int32_t _M0L8grow__atS1488 = _M0L4selfS535->$4;
      int32_t _M0L7_2abindS538;
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2abindS539;
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L5entryS540;
      if (_M0L4sizeS1487 >= _M0L8grow__atS1488) {
        int32_t _M0L14capacity__maskS1490;
        int32_t _M0L6_2atmpS1489;
        moonbit_incref(_M0L4selfS535);
        #line 126 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
        _M0MPB3Map4growGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(_M0L4selfS535);
        _M0L14capacity__maskS1490 = _M0L4selfS535->$3;
        _M0L6_2atmpS1489 = _M0L4hashS537 & _M0L14capacity__maskS1490;
        _M0L3pslS532 = 0;
        _M0L3idxS533 = _M0L6_2atmpS1489;
        continue;
      }
      _M0L7_2abindS538 = _M0L4selfS535->$6;
      _M0L7_2abindS539 = 0;
      _M0L5entryS540
      = (struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*)moonbit_malloc(sizeof(struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE));
      Moonbit_object_header(_M0L5entryS540)->meta
      = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE, $1) >> 2, 3, 0);
      _M0L5entryS540->$0 = _M0L7_2abindS538;
      _M0L5entryS540->$1 = _M0L7_2abindS539;
      _M0L5entryS540->$2 = _M0L3pslS532;
      _M0L5entryS540->$3 = _M0L4hashS537;
      _M0L5entryS540->$4 = _M0L3keyS541;
      _M0L5entryS540->$5 = _M0L5valueS542;
      #line 131 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      _M0MPB3Map20add__entry__to__tailGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(_M0L4selfS535, _M0L3idxS533, _M0L5entryS540);
      return 0;
    } else {
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2aSomeS543 =
        _M0L7_2abindS534;
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L14_2acurr__entryS544 =
        _M0L7_2aSomeS543;
      int32_t _M0L4hashS1492 = _M0L14_2acurr__entryS544->$3;
      int32_t _if__result_2140;
      int32_t _M0L3pslS1493;
      int32_t _M0L6_2atmpS1498;
      int32_t _M0L6_2atmpS1500;
      int32_t _M0L14capacity__maskS1501;
      int32_t _M0L6_2atmpS1499;
      if (_M0L4hashS1492 == _M0L4hashS537) {
        moonbit_string_t _M0L3keyS1491 = _M0L14_2acurr__entryS544->$4;
        #line 135 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
        _if__result_2140
        = moonbit_val_array_equal(_M0L3keyS1491, _M0L3keyS541);
      } else {
        _if__result_2140 = 0;
      }
      if (_if__result_2140) {
        struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L6_2aoldS1914;
        moonbit_incref(_M0L14_2acurr__entryS544);
        moonbit_decref(_M0L3keyS541);
        moonbit_decref(_M0L4selfS535);
        _M0L6_2aoldS1914 = _M0L14_2acurr__entryS544->$5;
        moonbit_decref(_M0L6_2aoldS1914);
        _M0L14_2acurr__entryS544->$5 = _M0L5valueS542;
        moonbit_decref(_M0L14_2acurr__entryS544);
        return 0;
      } else {
        moonbit_incref(_M0L14_2acurr__entryS544);
      }
      _M0L3pslS1493 = _M0L14_2acurr__entryS544->$2;
      if (_M0L3pslS532 > _M0L3pslS1493) {
        int32_t _M0L4sizeS1494 = _M0L4selfS535->$1;
        int32_t _M0L8grow__atS1495 = _M0L4selfS535->$4;
        int32_t _M0L7_2abindS545;
        struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2abindS546;
        struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L5entryS547;
        if (_M0L4sizeS1494 >= _M0L8grow__atS1495) {
          int32_t _M0L14capacity__maskS1497;
          int32_t _M0L6_2atmpS1496;
          moonbit_decref(_M0L14_2acurr__entryS544);
          moonbit_incref(_M0L4selfS535);
          #line 143 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
          _M0MPB3Map4growGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(_M0L4selfS535);
          _M0L14capacity__maskS1497 = _M0L4selfS535->$3;
          _M0L6_2atmpS1496 = _M0L4hashS537 & _M0L14capacity__maskS1497;
          _M0L3pslS532 = 0;
          _M0L3idxS533 = _M0L6_2atmpS1496;
          continue;
        }
        moonbit_incref(_M0L4selfS535);
        #line 147 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
        _M0MPB3Map10push__awayGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(_M0L4selfS535, _M0L3idxS533, _M0L14_2acurr__entryS544);
        _M0L7_2abindS545 = _M0L4selfS535->$6;
        _M0L7_2abindS546 = 0;
        _M0L5entryS547
        = (struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*)moonbit_malloc(sizeof(struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE));
        Moonbit_object_header(_M0L5entryS547)->meta
        = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE, $1) >> 2, 3, 0);
        _M0L5entryS547->$0 = _M0L7_2abindS545;
        _M0L5entryS547->$1 = _M0L7_2abindS546;
        _M0L5entryS547->$2 = _M0L3pslS532;
        _M0L5entryS547->$3 = _M0L4hashS537;
        _M0L5entryS547->$4 = _M0L3keyS541;
        _M0L5entryS547->$5 = _M0L5valueS542;
        #line 149 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
        _M0MPB3Map20add__entry__to__tailGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(_M0L4selfS535, _M0L3idxS533, _M0L5entryS547);
        return 0;
      } else {
        moonbit_decref(_M0L14_2acurr__entryS544);
      }
      _M0L6_2atmpS1498 = _M0L3pslS532 + 1;
      _M0L6_2atmpS1500 = _M0L3idxS533 + 1;
      _M0L14capacity__maskS1501 = _M0L4selfS535->$3;
      _M0L6_2atmpS1499 = _M0L6_2atmpS1500 & _M0L14capacity__maskS1501;
      _M0L3pslS532 = _M0L6_2atmpS1498;
      _M0L3idxS533 = _M0L6_2atmpS1499;
      continue;
    }
    break;
  }
  return 0;
}

int32_t _M0MPB3Map15set__with__hashGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L4selfS551,
  int32_t _M0L3keyS557,
  struct _M0TUWEuQRPC15error5ErrorNsE* _M0L5valueS558,
  int32_t _M0L4hashS553
) {
  int32_t _M0L14capacity__maskS1522;
  int32_t _M0L6_2atmpS1521;
  int32_t _M0L3pslS548;
  int32_t _M0L3idxS549;
  #line 114 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L14capacity__maskS1522 = _M0L4selfS551->$3;
  _M0L6_2atmpS1521 = _M0L4hashS553 & _M0L14capacity__maskS1522;
  _M0L3pslS548 = 0;
  _M0L3idxS549 = _M0L6_2atmpS1521;
  while (1) {
    struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE** _M0L7entriesS1520 =
      _M0L4selfS551->$0;
    struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2abindS550;
    if (
      _M0L3idxS549 < 0
      || _M0L3idxS549 >= Moonbit_array_length(_M0L7entriesS1520)
    ) {
      #line 122 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      moonbit_panic();
    }
    _M0L7_2abindS550
    = (struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE*)_M0L7entriesS1520[
        _M0L3idxS549
      ];
    if (_M0L7_2abindS550 == 0) {
      int32_t _M0L4sizeS1505 = _M0L4selfS551->$1;
      int32_t _M0L8grow__atS1506 = _M0L4selfS551->$4;
      int32_t _M0L7_2abindS554;
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2abindS555;
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L5entryS556;
      if (_M0L4sizeS1505 >= _M0L8grow__atS1506) {
        int32_t _M0L14capacity__maskS1508;
        int32_t _M0L6_2atmpS1507;
        moonbit_incref(_M0L4selfS551);
        #line 126 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
        _M0MPB3Map4growGiUWEuQRPC15error5ErrorNsEE(_M0L4selfS551);
        _M0L14capacity__maskS1508 = _M0L4selfS551->$3;
        _M0L6_2atmpS1507 = _M0L4hashS553 & _M0L14capacity__maskS1508;
        _M0L3pslS548 = 0;
        _M0L3idxS549 = _M0L6_2atmpS1507;
        continue;
      }
      _M0L7_2abindS554 = _M0L4selfS551->$6;
      _M0L7_2abindS555 = 0;
      _M0L5entryS556
      = (struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE*)moonbit_malloc(sizeof(struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE));
      Moonbit_object_header(_M0L5entryS556)->meta
      = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE, $1) >> 2, 2, 0);
      _M0L5entryS556->$0 = _M0L7_2abindS554;
      _M0L5entryS556->$1 = _M0L7_2abindS555;
      _M0L5entryS556->$2 = _M0L3pslS548;
      _M0L5entryS556->$3 = _M0L4hashS553;
      _M0L5entryS556->$4 = _M0L3keyS557;
      _M0L5entryS556->$5 = _M0L5valueS558;
      #line 131 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      _M0MPB3Map20add__entry__to__tailGiUWEuQRPC15error5ErrorNsEE(_M0L4selfS551, _M0L3idxS549, _M0L5entryS556);
      return 0;
    } else {
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2aSomeS559 =
        _M0L7_2abindS550;
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L14_2acurr__entryS560 =
        _M0L7_2aSomeS559;
      int32_t _M0L4hashS1510 = _M0L14_2acurr__entryS560->$3;
      int32_t _if__result_2142;
      int32_t _M0L3pslS1511;
      int32_t _M0L6_2atmpS1516;
      int32_t _M0L6_2atmpS1518;
      int32_t _M0L14capacity__maskS1519;
      int32_t _M0L6_2atmpS1517;
      if (_M0L4hashS1510 == _M0L4hashS553) {
        int32_t _M0L3keyS1509 = _M0L14_2acurr__entryS560->$4;
        _if__result_2142 = _M0L3keyS1509 == _M0L3keyS557;
      } else {
        _if__result_2142 = 0;
      }
      if (_if__result_2142) {
        struct _M0TUWEuQRPC15error5ErrorNsE* _M0L6_2aoldS1918;
        moonbit_incref(_M0L14_2acurr__entryS560);
        moonbit_decref(_M0L4selfS551);
        _M0L6_2aoldS1918 = _M0L14_2acurr__entryS560->$5;
        moonbit_decref(_M0L6_2aoldS1918);
        _M0L14_2acurr__entryS560->$5 = _M0L5valueS558;
        moonbit_decref(_M0L14_2acurr__entryS560);
        return 0;
      } else {
        moonbit_incref(_M0L14_2acurr__entryS560);
      }
      _M0L3pslS1511 = _M0L14_2acurr__entryS560->$2;
      if (_M0L3pslS548 > _M0L3pslS1511) {
        int32_t _M0L4sizeS1512 = _M0L4selfS551->$1;
        int32_t _M0L8grow__atS1513 = _M0L4selfS551->$4;
        int32_t _M0L7_2abindS561;
        struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2abindS562;
        struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L5entryS563;
        if (_M0L4sizeS1512 >= _M0L8grow__atS1513) {
          int32_t _M0L14capacity__maskS1515;
          int32_t _M0L6_2atmpS1514;
          moonbit_decref(_M0L14_2acurr__entryS560);
          moonbit_incref(_M0L4selfS551);
          #line 143 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
          _M0MPB3Map4growGiUWEuQRPC15error5ErrorNsEE(_M0L4selfS551);
          _M0L14capacity__maskS1515 = _M0L4selfS551->$3;
          _M0L6_2atmpS1514 = _M0L4hashS553 & _M0L14capacity__maskS1515;
          _M0L3pslS548 = 0;
          _M0L3idxS549 = _M0L6_2atmpS1514;
          continue;
        }
        moonbit_incref(_M0L4selfS551);
        #line 147 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
        _M0MPB3Map10push__awayGiUWEuQRPC15error5ErrorNsEE(_M0L4selfS551, _M0L3idxS549, _M0L14_2acurr__entryS560);
        _M0L7_2abindS561 = _M0L4selfS551->$6;
        _M0L7_2abindS562 = 0;
        _M0L5entryS563
        = (struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE*)moonbit_malloc(sizeof(struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE));
        Moonbit_object_header(_M0L5entryS563)->meta
        = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE, $1) >> 2, 2, 0);
        _M0L5entryS563->$0 = _M0L7_2abindS561;
        _M0L5entryS563->$1 = _M0L7_2abindS562;
        _M0L5entryS563->$2 = _M0L3pslS548;
        _M0L5entryS563->$3 = _M0L4hashS553;
        _M0L5entryS563->$4 = _M0L3keyS557;
        _M0L5entryS563->$5 = _M0L5valueS558;
        #line 149 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
        _M0MPB3Map20add__entry__to__tailGiUWEuQRPC15error5ErrorNsEE(_M0L4selfS551, _M0L3idxS549, _M0L5entryS563);
        return 0;
      } else {
        moonbit_decref(_M0L14_2acurr__entryS560);
      }
      _M0L6_2atmpS1516 = _M0L3pslS548 + 1;
      _M0L6_2atmpS1518 = _M0L3idxS549 + 1;
      _M0L14capacity__maskS1519 = _M0L4selfS551->$3;
      _M0L6_2atmpS1517 = _M0L6_2atmpS1518 & _M0L14capacity__maskS1519;
      _M0L3pslS548 = _M0L6_2atmpS1516;
      _M0L3idxS549 = _M0L6_2atmpS1517;
      continue;
    }
    break;
  }
  return 0;
}

int32_t _M0MPB3Map10push__awayGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L4selfS516,
  int32_t _M0L3idxS521,
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L5entryS520
) {
  int32_t _M0L3pslS1470;
  int32_t _M0L6_2atmpS1466;
  int32_t _M0L6_2atmpS1468;
  int32_t _M0L14capacity__maskS1469;
  int32_t _M0L6_2atmpS1467;
  int32_t _M0L3pslS512;
  int32_t _M0L3idxS513;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L5entryS514;
  #line 159 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L3pslS1470 = _M0L5entryS520->$2;
  _M0L6_2atmpS1466 = _M0L3pslS1470 + 1;
  _M0L6_2atmpS1468 = _M0L3idxS521 + 1;
  _M0L14capacity__maskS1469 = _M0L4selfS516->$3;
  _M0L6_2atmpS1467 = _M0L6_2atmpS1468 & _M0L14capacity__maskS1469;
  _M0L3pslS512 = _M0L6_2atmpS1466;
  _M0L3idxS513 = _M0L6_2atmpS1467;
  _M0L5entryS514 = _M0L5entryS520;
  while (1) {
    struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE** _M0L7entriesS1465 =
      _M0L4selfS516->$0;
    struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2abindS515;
    if (
      _M0L3idxS513 < 0
      || _M0L3idxS513 >= Moonbit_array_length(_M0L7entriesS1465)
    ) {
      #line 165 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      moonbit_panic();
    }
    _M0L7_2abindS515
    = (struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*)_M0L7entriesS1465[
        _M0L3idxS513
      ];
    if (_M0L7_2abindS515 == 0) {
      _M0L5entryS514->$2 = _M0L3pslS512;
      #line 168 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      _M0MPB3Map10set__entryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(_M0L4selfS516, _M0L5entryS514, _M0L3idxS513);
      break;
    } else {
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2aSomeS518 =
        _M0L7_2abindS515;
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L14_2acurr__entryS519 =
        _M0L7_2aSomeS518;
      int32_t _M0L3pslS1455 = _M0L14_2acurr__entryS519->$2;
      if (_M0L3pslS512 > _M0L3pslS1455) {
        int32_t _M0L3pslS1460;
        int32_t _M0L6_2atmpS1456;
        int32_t _M0L6_2atmpS1458;
        int32_t _M0L14capacity__maskS1459;
        int32_t _M0L6_2atmpS1457;
        _M0L5entryS514->$2 = _M0L3pslS512;
        moonbit_incref(_M0L14_2acurr__entryS519);
        moonbit_incref(_M0L4selfS516);
        #line 174 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
        _M0MPB3Map10set__entryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(_M0L4selfS516, _M0L5entryS514, _M0L3idxS513);
        _M0L3pslS1460 = _M0L14_2acurr__entryS519->$2;
        _M0L6_2atmpS1456 = _M0L3pslS1460 + 1;
        _M0L6_2atmpS1458 = _M0L3idxS513 + 1;
        _M0L14capacity__maskS1459 = _M0L4selfS516->$3;
        _M0L6_2atmpS1457 = _M0L6_2atmpS1458 & _M0L14capacity__maskS1459;
        _M0L3pslS512 = _M0L6_2atmpS1456;
        _M0L3idxS513 = _M0L6_2atmpS1457;
        _M0L5entryS514 = _M0L14_2acurr__entryS519;
        continue;
      } else {
        int32_t _M0L6_2atmpS1461 = _M0L3pslS512 + 1;
        int32_t _M0L6_2atmpS1463 = _M0L3idxS513 + 1;
        int32_t _M0L14capacity__maskS1464 = _M0L4selfS516->$3;
        int32_t _M0L6_2atmpS1462 =
          _M0L6_2atmpS1463 & _M0L14capacity__maskS1464;
        struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _tmp_2144 =
          _M0L5entryS514;
        _M0L3pslS512 = _M0L6_2atmpS1461;
        _M0L3idxS513 = _M0L6_2atmpS1462;
        _M0L5entryS514 = _tmp_2144;
        continue;
      }
    }
    break;
  }
  return 0;
}

int32_t _M0MPB3Map10push__awayGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L4selfS526,
  int32_t _M0L3idxS531,
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L5entryS530
) {
  int32_t _M0L3pslS1486;
  int32_t _M0L6_2atmpS1482;
  int32_t _M0L6_2atmpS1484;
  int32_t _M0L14capacity__maskS1485;
  int32_t _M0L6_2atmpS1483;
  int32_t _M0L3pslS522;
  int32_t _M0L3idxS523;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L5entryS524;
  #line 159 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L3pslS1486 = _M0L5entryS530->$2;
  _M0L6_2atmpS1482 = _M0L3pslS1486 + 1;
  _M0L6_2atmpS1484 = _M0L3idxS531 + 1;
  _M0L14capacity__maskS1485 = _M0L4selfS526->$3;
  _M0L6_2atmpS1483 = _M0L6_2atmpS1484 & _M0L14capacity__maskS1485;
  _M0L3pslS522 = _M0L6_2atmpS1482;
  _M0L3idxS523 = _M0L6_2atmpS1483;
  _M0L5entryS524 = _M0L5entryS530;
  while (1) {
    struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE** _M0L7entriesS1481 =
      _M0L4selfS526->$0;
    struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2abindS525;
    if (
      _M0L3idxS523 < 0
      || _M0L3idxS523 >= Moonbit_array_length(_M0L7entriesS1481)
    ) {
      #line 165 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      moonbit_panic();
    }
    _M0L7_2abindS525
    = (struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE*)_M0L7entriesS1481[
        _M0L3idxS523
      ];
    if (_M0L7_2abindS525 == 0) {
      _M0L5entryS524->$2 = _M0L3pslS522;
      #line 168 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      _M0MPB3Map10set__entryGiUWEuQRPC15error5ErrorNsEE(_M0L4selfS526, _M0L5entryS524, _M0L3idxS523);
      break;
    } else {
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2aSomeS528 =
        _M0L7_2abindS525;
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L14_2acurr__entryS529 =
        _M0L7_2aSomeS528;
      int32_t _M0L3pslS1471 = _M0L14_2acurr__entryS529->$2;
      if (_M0L3pslS522 > _M0L3pslS1471) {
        int32_t _M0L3pslS1476;
        int32_t _M0L6_2atmpS1472;
        int32_t _M0L6_2atmpS1474;
        int32_t _M0L14capacity__maskS1475;
        int32_t _M0L6_2atmpS1473;
        _M0L5entryS524->$2 = _M0L3pslS522;
        moonbit_incref(_M0L14_2acurr__entryS529);
        moonbit_incref(_M0L4selfS526);
        #line 174 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
        _M0MPB3Map10set__entryGiUWEuQRPC15error5ErrorNsEE(_M0L4selfS526, _M0L5entryS524, _M0L3idxS523);
        _M0L3pslS1476 = _M0L14_2acurr__entryS529->$2;
        _M0L6_2atmpS1472 = _M0L3pslS1476 + 1;
        _M0L6_2atmpS1474 = _M0L3idxS523 + 1;
        _M0L14capacity__maskS1475 = _M0L4selfS526->$3;
        _M0L6_2atmpS1473 = _M0L6_2atmpS1474 & _M0L14capacity__maskS1475;
        _M0L3pslS522 = _M0L6_2atmpS1472;
        _M0L3idxS523 = _M0L6_2atmpS1473;
        _M0L5entryS524 = _M0L14_2acurr__entryS529;
        continue;
      } else {
        int32_t _M0L6_2atmpS1477 = _M0L3pslS522 + 1;
        int32_t _M0L6_2atmpS1479 = _M0L3idxS523 + 1;
        int32_t _M0L14capacity__maskS1480 = _M0L4selfS526->$3;
        int32_t _M0L6_2atmpS1478 =
          _M0L6_2atmpS1479 & _M0L14capacity__maskS1480;
        struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _tmp_2146 =
          _M0L5entryS524;
        _M0L3pslS522 = _M0L6_2atmpS1477;
        _M0L3idxS523 = _M0L6_2atmpS1478;
        _M0L5entryS524 = _tmp_2146;
        continue;
      }
    }
    break;
  }
  return 0;
}

int32_t _M0MPB3Map10set__entryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L4selfS500,
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L5entryS502,
  int32_t _M0L8new__idxS501
) {
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE** _M0L7entriesS1451;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L6_2atmpS1452;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L6_2aoldS1926;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L8_2afieldS1925;
  int32_t _M0L6_2acntS2034;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2abindS503;
  #line 186 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L7entriesS1451 = _M0L4selfS500->$0;
  moonbit_incref(_M0L5entryS502);
  _M0L6_2atmpS1452 = _M0L5entryS502;
  if (
    _M0L8new__idxS501 < 0
    || _M0L8new__idxS501 >= Moonbit_array_length(_M0L7entriesS1451)
  ) {
    #line 191 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
    moonbit_panic();
  }
  _M0L6_2aoldS1926
  = (struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*)_M0L7entriesS1451[
      _M0L8new__idxS501
    ];
  if (_M0L6_2aoldS1926) {
    moonbit_decref(_M0L6_2aoldS1926);
  }
  _M0L7entriesS1451[_M0L8new__idxS501] = _M0L6_2atmpS1452;
  _M0L8_2afieldS1925 = _M0L5entryS502->$1;
  _M0L6_2acntS2034 = Moonbit_object_header(_M0L5entryS502)->rc;
  if (_M0L6_2acntS2034 > 1) {
    int32_t _M0L11_2anew__cntS2037 = _M0L6_2acntS2034 - 1;
    Moonbit_object_header(_M0L5entryS502)->rc = _M0L11_2anew__cntS2037;
    if (_M0L8_2afieldS1925) {
      moonbit_incref(_M0L8_2afieldS1925);
    }
  } else if (_M0L6_2acntS2034 == 1) {
    struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L8_2afieldS2036 =
      _M0L5entryS502->$5;
    moonbit_string_t _M0L8_2afieldS2035;
    moonbit_decref(_M0L8_2afieldS2036);
    _M0L8_2afieldS2035 = _M0L5entryS502->$4;
    moonbit_decref(_M0L8_2afieldS2035);
    #line 192 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
    moonbit_free(_M0L5entryS502);
  }
  _M0L7_2abindS503 = _M0L8_2afieldS1925;
  if (_M0L7_2abindS503 == 0) {
    if (_M0L7_2abindS503) {
      moonbit_decref(_M0L7_2abindS503);
    }
    _M0L4selfS500->$6 = _M0L8new__idxS501;
    moonbit_decref(_M0L4selfS500);
  } else {
    struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2aSomeS504;
    struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2anextS505;
    moonbit_decref(_M0L4selfS500);
    _M0L7_2aSomeS504 = _M0L7_2abindS503;
    _M0L7_2anextS505 = _M0L7_2aSomeS504;
    _M0L7_2anextS505->$0 = _M0L8new__idxS501;
    moonbit_decref(_M0L7_2anextS505);
  }
  return 0;
}

int32_t _M0MPB3Map10set__entryGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L4selfS506,
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L5entryS508,
  int32_t _M0L8new__idxS507
) {
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE** _M0L7entriesS1453;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L6_2atmpS1454;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L6_2aoldS1929;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L8_2afieldS1928;
  int32_t _M0L6_2acntS2038;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2abindS509;
  #line 186 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L7entriesS1453 = _M0L4selfS506->$0;
  moonbit_incref(_M0L5entryS508);
  _M0L6_2atmpS1454 = _M0L5entryS508;
  if (
    _M0L8new__idxS507 < 0
    || _M0L8new__idxS507 >= Moonbit_array_length(_M0L7entriesS1453)
  ) {
    #line 191 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
    moonbit_panic();
  }
  _M0L6_2aoldS1929
  = (struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE*)_M0L7entriesS1453[
      _M0L8new__idxS507
    ];
  if (_M0L6_2aoldS1929) {
    moonbit_decref(_M0L6_2aoldS1929);
  }
  _M0L7entriesS1453[_M0L8new__idxS507] = _M0L6_2atmpS1454;
  _M0L8_2afieldS1928 = _M0L5entryS508->$1;
  _M0L6_2acntS2038 = Moonbit_object_header(_M0L5entryS508)->rc;
  if (_M0L6_2acntS2038 > 1) {
    int32_t _M0L11_2anew__cntS2040 = _M0L6_2acntS2038 - 1;
    Moonbit_object_header(_M0L5entryS508)->rc = _M0L11_2anew__cntS2040;
    if (_M0L8_2afieldS1928) {
      moonbit_incref(_M0L8_2afieldS1928);
    }
  } else if (_M0L6_2acntS2038 == 1) {
    struct _M0TUWEuQRPC15error5ErrorNsE* _M0L8_2afieldS2039 =
      _M0L5entryS508->$5;
    moonbit_decref(_M0L8_2afieldS2039);
    #line 192 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
    moonbit_free(_M0L5entryS508);
  }
  _M0L7_2abindS509 = _M0L8_2afieldS1928;
  if (_M0L7_2abindS509 == 0) {
    if (_M0L7_2abindS509) {
      moonbit_decref(_M0L7_2abindS509);
    }
    _M0L4selfS506->$6 = _M0L8new__idxS507;
    moonbit_decref(_M0L4selfS506);
  } else {
    struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2aSomeS510;
    struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2anextS511;
    moonbit_decref(_M0L4selfS506);
    _M0L7_2aSomeS510 = _M0L7_2abindS509;
    _M0L7_2anextS511 = _M0L7_2aSomeS510;
    _M0L7_2anextS511->$0 = _M0L8new__idxS507;
    moonbit_decref(_M0L7_2anextS511);
  }
  return 0;
}

int32_t _M0MPB3Map20add__entry__to__tailGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L4selfS493,
  int32_t _M0L3idxS495,
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L5entryS494
) {
  int32_t _M0L7_2abindS492;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE** _M0L7entriesS1438;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L6_2atmpS1439;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L6_2aoldS1931;
  int32_t _M0L4sizeS1441;
  int32_t _M0L6_2atmpS1440;
  #line 444 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L7_2abindS492 = _M0L4selfS493->$6;
  switch (_M0L7_2abindS492) {
    case -1: {
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L6_2atmpS1433;
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L6_2aoldS1933;
      moonbit_incref(_M0L5entryS494);
      _M0L6_2atmpS1433 = _M0L5entryS494;
      _M0L6_2aoldS1933 = _M0L4selfS493->$5;
      if (_M0L6_2aoldS1933) {
        moonbit_decref(_M0L6_2aoldS1933);
      }
      _M0L4selfS493->$5 = _M0L6_2atmpS1433;
      break;
    }
    default: {
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE** _M0L7entriesS1437 =
        _M0L4selfS493->$0;
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L6_2atmpS1436;
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L6_2atmpS1434;
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L6_2atmpS1435;
      struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L6_2aoldS1934;
      if (
        _M0L7_2abindS492 < 0
        || _M0L7_2abindS492 >= Moonbit_array_length(_M0L7entriesS1437)
      ) {
        #line 451 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
        moonbit_panic();
      }
      _M0L6_2atmpS1436
      = (struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*)_M0L7entriesS1437[
          _M0L7_2abindS492
        ];
      if (_M0L6_2atmpS1436) {
        moonbit_incref(_M0L6_2atmpS1436);
      }
      #line 451 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      _M0L6_2atmpS1434
      = _M0MPC16option6Option6unwrapGRPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEEE(_M0L6_2atmpS1436);
      moonbit_incref(_M0L5entryS494);
      _M0L6_2atmpS1435 = _M0L5entryS494;
      _M0L6_2aoldS1934 = _M0L6_2atmpS1434->$1;
      if (_M0L6_2aoldS1934) {
        moonbit_decref(_M0L6_2aoldS1934);
      }
      _M0L6_2atmpS1434->$1 = _M0L6_2atmpS1435;
      moonbit_decref(_M0L6_2atmpS1434);
      break;
    }
  }
  _M0L4selfS493->$6 = _M0L3idxS495;
  _M0L7entriesS1438 = _M0L4selfS493->$0;
  _M0L6_2atmpS1439 = _M0L5entryS494;
  if (
    _M0L3idxS495 < 0
    || _M0L3idxS495 >= Moonbit_array_length(_M0L7entriesS1438)
  ) {
    #line 454 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
    moonbit_panic();
  }
  _M0L6_2aoldS1931
  = (struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*)_M0L7entriesS1438[
      _M0L3idxS495
    ];
  if (_M0L6_2aoldS1931) {
    moonbit_decref(_M0L6_2aoldS1931);
  }
  _M0L7entriesS1438[_M0L3idxS495] = _M0L6_2atmpS1439;
  _M0L4sizeS1441 = _M0L4selfS493->$1;
  _M0L6_2atmpS1440 = _M0L4sizeS1441 + 1;
  _M0L4selfS493->$1 = _M0L6_2atmpS1440;
  moonbit_decref(_M0L4selfS493);
  return 0;
}

int32_t _M0MPB3Map20add__entry__to__tailGiUWEuQRPC15error5ErrorNsEE(
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L4selfS497,
  int32_t _M0L3idxS499,
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L5entryS498
) {
  int32_t _M0L7_2abindS496;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE** _M0L7entriesS1447;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L6_2atmpS1448;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L6_2aoldS1937;
  int32_t _M0L4sizeS1450;
  int32_t _M0L6_2atmpS1449;
  #line 444 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L7_2abindS496 = _M0L4selfS497->$6;
  switch (_M0L7_2abindS496) {
    case -1: {
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L6_2atmpS1442;
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L6_2aoldS1939;
      moonbit_incref(_M0L5entryS498);
      _M0L6_2atmpS1442 = _M0L5entryS498;
      _M0L6_2aoldS1939 = _M0L4selfS497->$5;
      if (_M0L6_2aoldS1939) {
        moonbit_decref(_M0L6_2aoldS1939);
      }
      _M0L4selfS497->$5 = _M0L6_2atmpS1442;
      break;
    }
    default: {
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE** _M0L7entriesS1446 =
        _M0L4selfS497->$0;
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L6_2atmpS1445;
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L6_2atmpS1443;
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L6_2atmpS1444;
      struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L6_2aoldS1940;
      if (
        _M0L7_2abindS496 < 0
        || _M0L7_2abindS496 >= Moonbit_array_length(_M0L7entriesS1446)
      ) {
        #line 451 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
        moonbit_panic();
      }
      _M0L6_2atmpS1445
      = (struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE*)_M0L7entriesS1446[
          _M0L7_2abindS496
        ];
      if (_M0L6_2atmpS1445) {
        moonbit_incref(_M0L6_2atmpS1445);
      }
      #line 451 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
      _M0L6_2atmpS1443
      = _M0MPC16option6Option6unwrapGRPB5EntryGiUWEuQRPC15error5ErrorNsEEE(_M0L6_2atmpS1445);
      moonbit_incref(_M0L5entryS498);
      _M0L6_2atmpS1444 = _M0L5entryS498;
      _M0L6_2aoldS1940 = _M0L6_2atmpS1443->$1;
      if (_M0L6_2aoldS1940) {
        moonbit_decref(_M0L6_2aoldS1940);
      }
      _M0L6_2atmpS1443->$1 = _M0L6_2atmpS1444;
      moonbit_decref(_M0L6_2atmpS1443);
      break;
    }
  }
  _M0L4selfS497->$6 = _M0L3idxS499;
  _M0L7entriesS1447 = _M0L4selfS497->$0;
  _M0L6_2atmpS1448 = _M0L5entryS498;
  if (
    _M0L3idxS499 < 0
    || _M0L3idxS499 >= Moonbit_array_length(_M0L7entriesS1447)
  ) {
    #line 454 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
    moonbit_panic();
  }
  _M0L6_2aoldS1937
  = (struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE*)_M0L7entriesS1447[
      _M0L3idxS499
    ];
  if (_M0L6_2aoldS1937) {
    moonbit_decref(_M0L6_2aoldS1937);
  }
  _M0L7entriesS1447[_M0L3idxS499] = _M0L6_2atmpS1448;
  _M0L4sizeS1450 = _M0L4selfS497->$1;
  _M0L6_2atmpS1449 = _M0L4sizeS1450 + 1;
  _M0L4selfS497->$1 = _M0L6_2atmpS1449;
  moonbit_decref(_M0L4selfS497);
  return 0;
}

struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0MPB3Map11new_2einnerGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(
  int32_t _M0L8capacityS481
) {
  int32_t _M0L8capacityS480;
  int32_t _M0L7_2abindS482;
  int32_t _M0L7_2abindS483;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L6_2atmpS1431;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE** _M0L7_2abindS484;
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2abindS485;
  struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _block_2147;
  #line 58 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  #line 59 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L8capacityS480
  = _M0MPC13int3Int20next__power__of__two(_M0L8capacityS481);
  _M0L7_2abindS482 = _M0L8capacityS480 - 1;
  #line 64 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L7_2abindS483 = _M0FPB21calc__grow__threshold(_M0L8capacityS480);
  _M0L6_2atmpS1431 = 0;
  _M0L7_2abindS484
  = (struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE**)moonbit_make_ref_array(_M0L8capacityS480, _M0L6_2atmpS1431);
  _M0L7_2abindS485 = 0;
  _block_2147
  = (struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*)moonbit_malloc(sizeof(struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE));
  Moonbit_object_header(_block_2147)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB3MapGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE, $0) >> 2, 2, 0);
  _block_2147->$0 = _M0L7_2abindS484;
  _block_2147->$1 = 0;
  _block_2147->$2 = _M0L8capacityS480;
  _block_2147->$3 = _M0L7_2abindS482;
  _block_2147->$4 = _M0L7_2abindS483;
  _block_2147->$5 = _M0L7_2abindS485;
  _block_2147->$6 = -1;
  return _block_2147;
}

struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0MPB3Map11new_2einnerGiUWEuQRPC15error5ErrorNsEE(
  int32_t _M0L8capacityS487
) {
  int32_t _M0L8capacityS486;
  int32_t _M0L7_2abindS488;
  int32_t _M0L7_2abindS489;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L6_2atmpS1432;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE** _M0L7_2abindS490;
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2abindS491;
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _block_2148;
  #line 58 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  #line 59 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L8capacityS486
  = _M0MPC13int3Int20next__power__of__two(_M0L8capacityS487);
  _M0L7_2abindS488 = _M0L8capacityS486 - 1;
  #line 64 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L7_2abindS489 = _M0FPB21calc__grow__threshold(_M0L8capacityS486);
  _M0L6_2atmpS1432 = 0;
  _M0L7_2abindS490
  = (struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE**)moonbit_make_ref_array(_M0L8capacityS486, _M0L6_2atmpS1432);
  _M0L7_2abindS491 = 0;
  _block_2148
  = (struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE*)moonbit_malloc(sizeof(struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE));
  Moonbit_object_header(_block_2148)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE, $0) >> 2, 2, 0);
  _block_2148->$0 = _M0L7_2abindS490;
  _block_2148->$1 = 0;
  _block_2148->$2 = _M0L8capacityS486;
  _block_2148->$3 = _M0L7_2abindS488;
  _block_2148->$4 = _M0L7_2abindS489;
  _block_2148->$5 = _M0L7_2abindS491;
  _block_2148->$6 = -1;
  return _block_2148;
}

int32_t _M0MPC13int3Int20next__power__of__two(int32_t _M0L4selfS479) {
  #line 33 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\int.mbt"
  if (_M0L4selfS479 >= 0) {
    int32_t _M0L6_2atmpS1430;
    int32_t _M0L6_2atmpS1429;
    int32_t _M0L6_2atmpS1428;
    int32_t _M0L6_2atmpS1427;
    if (_M0L4selfS479 <= 1) {
      return 1;
    }
    if (_M0L4selfS479 > 1073741824) {
      return 1073741824;
    }
    _M0L6_2atmpS1430 = _M0L4selfS479 - 1;
    #line 44 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\int.mbt"
    _M0L6_2atmpS1429 = moonbit_clz32(_M0L6_2atmpS1430);
    _M0L6_2atmpS1428 = _M0L6_2atmpS1429 - 1;
    _M0L6_2atmpS1427 = 2147483647 >> (_M0L6_2atmpS1428 & 31);
    return _M0L6_2atmpS1427 + 1;
  } else {
    #line 34 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\int.mbt"
    moonbit_panic();
  }
}

int32_t _M0FPB21calc__grow__threshold(int32_t _M0L8capacityS478) {
  int32_t _M0L6_2atmpS1426;
  #line 511 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\linked_hash_map.mbt"
  _M0L6_2atmpS1426 = _M0L8capacityS478 * 13;
  return _M0L6_2atmpS1426 / 16;
}

struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0MPC16option6Option6unwrapGRPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEEE(
  struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L4selfS474
) {
  #line 37 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\option.mbt"
  if (_M0L4selfS474 == 0) {
    if (_M0L4selfS474) {
      moonbit_decref(_M0L4selfS474);
    }
    #line 39 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\option.mbt"
    moonbit_panic();
  } else {
    struct _M0TPB5EntryGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L7_2aSomeS475 =
      _M0L4selfS474;
    return _M0L7_2aSomeS475;
  }
}

struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0MPC16option6Option6unwrapGRPB5EntryGiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L4selfS476
) {
  #line 37 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\option.mbt"
  if (_M0L4selfS476 == 0) {
    if (_M0L4selfS476) {
      moonbit_decref(_M0L4selfS476);
    }
    #line 39 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\option.mbt"
    moonbit_panic();
  } else {
    struct _M0TPB5EntryGiUWEuQRPC15error5ErrorNsEE* _M0L7_2aSomeS477 =
      _M0L4selfS476;
    return _M0L7_2aSomeS477;
  }
}

struct _M0TWEOs* _M0MPC15array13ReadOnlyArray4iterGsE(
  moonbit_string_t* _M0L4selfS473
) {
  moonbit_string_t* _M0L6_2atmpS1425;
  #line 165 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\readonlyarray.mbt"
  _M0L6_2atmpS1425 = _M0L4selfS473;
  #line 167 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\readonlyarray.mbt"
  return _M0MPC15array10FixedArray4iterGsE(_M0L6_2atmpS1425);
}

struct _M0TWEOs* _M0MPC15array10FixedArray4iterGsE(
  moonbit_string_t* _M0L4selfS472
) {
  moonbit_string_t* _M0L6_2atmpS1423;
  int32_t _M0L6_2atmpS1424;
  struct _M0TPB9ArrayViewGsE _M0L6_2atmpS1422;
  #line 1509 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray.mbt"
  moonbit_incref(_M0L4selfS472);
  _M0L6_2atmpS1423 = _M0L4selfS472;
  _M0L6_2atmpS1424 = Moonbit_array_length(_M0L4selfS472);
  moonbit_decref(_M0L4selfS472);
  _M0L6_2atmpS1422
  = (struct _M0TPB9ArrayViewGsE){
    0, _M0L6_2atmpS1424, _M0L6_2atmpS1423
  };
  #line 1511 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray.mbt"
  return _M0MPC15array9ArrayView4iterGsE(_M0L6_2atmpS1422);
}

struct _M0TWEOs* _M0MPC15array9ArrayView4iterGsE(
  struct _M0TPB9ArrayViewGsE _M0L4selfS470
) {
  struct _M0TPB8MutLocalGiE* _M0L1iS469;
  struct _M0R59ArrayView_3a_3aiter_7c_5bString_5d_7c_2eanon__u1411__l674__* _closure_2149;
  struct _M0TWEOs* _M0L6_2atmpS1410;
  #line 671 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arrayview.mbt"
  _M0L1iS469
  = (struct _M0TPB8MutLocalGiE*)moonbit_malloc(sizeof(struct _M0TPB8MutLocalGiE));
  Moonbit_object_header(_M0L1iS469)->meta
  = Moonbit_make_regular_object_header(sizeof(struct _M0TPB8MutLocalGiE) >> 2, 0, 0);
  _M0L1iS469->$0 = 0;
  _closure_2149
  = (struct _M0R59ArrayView_3a_3aiter_7c_5bString_5d_7c_2eanon__u1411__l674__*)moonbit_malloc(sizeof(struct _M0R59ArrayView_3a_3aiter_7c_5bString_5d_7c_2eanon__u1411__l674__));
  Moonbit_object_header(_closure_2149)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0R59ArrayView_3a_3aiter_7c_5bString_5d_7c_2eanon__u1411__l674__, $0_0) >> 2, 2, 0);
  _closure_2149->code = &_M0MPC15array9ArrayView4iterGsEC1411l674;
  _closure_2149->$0_0 = _M0L4selfS470.$0;
  _closure_2149->$0_1 = _M0L4selfS470.$1;
  _closure_2149->$0_2 = _M0L4selfS470.$2;
  _closure_2149->$1 = _M0L1iS469;
  _M0L6_2atmpS1410 = (struct _M0TWEOs*)_closure_2149;
  #line 674 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arrayview.mbt"
  return _M0MPB4Iter3newGsE(_M0L6_2atmpS1410);
}

moonbit_string_t _M0MPC15array9ArrayView4iterGsEC1411l674(
  struct _M0TWEOs* _M0L6_2aenvS1412
) {
  struct _M0R59ArrayView_3a_3aiter_7c_5bString_5d_7c_2eanon__u1411__l674__* _M0L14_2acasted__envS1413;
  struct _M0TPB8MutLocalGiE* _M0L1iS469;
  struct _M0TPB9ArrayViewGsE _M0L8_2afieldS1945;
  int32_t _M0L6_2acntS2041;
  struct _M0TPB9ArrayViewGsE _M0L4selfS470;
  int32_t _M0L3valS1414;
  int32_t _M0L6_2atmpS1415;
  #line 674 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arrayview.mbt"
  _M0L14_2acasted__envS1413
  = (struct _M0R59ArrayView_3a_3aiter_7c_5bString_5d_7c_2eanon__u1411__l674__*)_M0L6_2aenvS1412;
  _M0L1iS469 = _M0L14_2acasted__envS1413->$1;
  _M0L8_2afieldS1945
  = (struct _M0TPB9ArrayViewGsE){
    _M0L14_2acasted__envS1413->$0_1,
      _M0L14_2acasted__envS1413->$0_2,
      _M0L14_2acasted__envS1413->$0_0
  };
  _M0L6_2acntS2041 = Moonbit_object_header(_M0L14_2acasted__envS1413)->rc;
  if (_M0L6_2acntS2041 > 1) {
    int32_t _M0L11_2anew__cntS2042 = _M0L6_2acntS2041 - 1;
    Moonbit_object_header(_M0L14_2acasted__envS1413)->rc
    = _M0L11_2anew__cntS2042;
    moonbit_incref(_M0L1iS469);
    moonbit_incref(_M0L8_2afieldS1945.$0);
  } else if (_M0L6_2acntS2041 == 1) {
    #line 674 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arrayview.mbt"
    moonbit_free(_M0L14_2acasted__envS1413);
  }
  _M0L4selfS470 = _M0L8_2afieldS1945;
  _M0L3valS1414 = _M0L1iS469->$0;
  moonbit_incref(_M0L4selfS470.$0);
  #line 675 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arrayview.mbt"
  _M0L6_2atmpS1415 = _M0MPC15array9ArrayView6lengthGsE(_M0L4selfS470);
  if (_M0L3valS1414 < _M0L6_2atmpS1415) {
    moonbit_string_t* _M0L3bufS1418 = _M0L4selfS470.$0;
    int32_t _M0L5startS1420 = _M0L4selfS470.$1;
    int32_t _M0L3valS1421 = _M0L1iS469->$0;
    int32_t _M0L6_2atmpS1419 = _M0L5startS1420 + _M0L3valS1421;
    moonbit_string_t _M0L6_2atmpS1943 =
      (moonbit_string_t)_M0L3bufS1418[_M0L6_2atmpS1419];
    moonbit_string_t _M0L4elemS471;
    int32_t _M0L3valS1417;
    int32_t _M0L6_2atmpS1416;
    moonbit_incref(_M0L6_2atmpS1943);
    moonbit_decref(_M0L3bufS1418);
    _M0L4elemS471 = _M0L6_2atmpS1943;
    _M0L3valS1417 = _M0L1iS469->$0;
    _M0L6_2atmpS1416 = _M0L3valS1417 + 1;
    _M0L1iS469->$0 = _M0L6_2atmpS1416;
    moonbit_decref(_M0L1iS469);
    return _M0L4elemS471;
  } else {
    moonbit_decref(_M0L4selfS470.$0);
    moonbit_decref(_M0L1iS469);
    return 0;
  }
}

int32_t _M0IPC16string6StringPB4Show6output(
  moonbit_string_t _M0L4selfS467,
  struct _M0TPB6Logger _M0L6loggerS468
) {
  int32_t _M0L6_2atmpS1409;
  struct _M0TPC16string10StringView _M0L6_2atmpS1408;
  #line 244 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L6_2atmpS1409 = Moonbit_array_length(_M0L4selfS467);
  _M0L6_2atmpS1408
  = (struct _M0TPC16string10StringView){
    0, _M0L6_2atmpS1409, _M0L4selfS467
  };
  #line 245 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0MPC16string10StringView18escape__to_2einner(_M0L6_2atmpS1408, _M0L6loggerS468, 1);
  return 0;
}

moonbit_string_t _M0IPC13int3IntPB4Show10to__string(int32_t _M0L4selfS466) {
  #line 45 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  #line 46 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  return _M0MPC13int3Int18to__string_2einner(_M0L4selfS466, 10);
}

int32_t _M0IPC13int3IntPB4Show6output(
  int32_t _M0L4selfS465,
  struct _M0TPB6Logger _M0L6loggerS464
) {
  moonbit_string_t _M0L6_2atmpS1407;
  #line 40 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  #line 41 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L6_2atmpS1407 = _M0MPC13int3Int18to__string_2einner(_M0L4selfS465, 10);
  #line 41 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L6loggerS464.$0->$method_0(_M0L6loggerS464.$1, _M0L6_2atmpS1407);
  return 0;
}

moonbit_string_t _M0IPC14bool4BoolPB4Show10to__string(int32_t _M0L4selfS463) {
  #line 31 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  if (_M0L4selfS463) {
    return (moonbit_string_t)moonbit_string_literal_44.data;
  } else {
    return (moonbit_string_t)moonbit_string_literal_45.data;
  }
}

int32_t _M0MPC15array5Array4pushGsE(
  struct _M0TPB5ArrayGsE* _M0L4selfS457,
  moonbit_string_t _M0L5valueS459
) {
  int32_t _M0L3lenS1397;
  moonbit_string_t* _M0L6_2atmpS1399;
  int32_t _M0L6_2atmpS1398;
  int32_t _M0L6lengthS458;
  moonbit_string_t* _M0L3bufS1400;
  moonbit_string_t _M0L6_2aoldS1947;
  int32_t _M0L6_2atmpS1401;
  #line 242 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L3lenS1397 = _M0L4selfS457->$1;
  moonbit_incref(_M0L4selfS457);
  #line 243 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L6_2atmpS1399 = _M0MPC15array5Array6bufferGsE(_M0L4selfS457);
  _M0L6_2atmpS1398 = Moonbit_array_length(_M0L6_2atmpS1399);
  moonbit_decref(_M0L6_2atmpS1399);
  if (_M0L3lenS1397 == _M0L6_2atmpS1398) {
    moonbit_incref(_M0L4selfS457);
    #line 244 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
    _M0MPC15array5Array7reallocGsE(_M0L4selfS457);
  }
  _M0L6lengthS458 = _M0L4selfS457->$1;
  _M0L3bufS1400 = _M0L4selfS457->$0;
  _M0L6_2aoldS1947 = (moonbit_string_t)_M0L3bufS1400[_M0L6lengthS458];
  moonbit_decref(_M0L6_2aoldS1947);
  _M0L3bufS1400[_M0L6lengthS458] = _M0L5valueS459;
  _M0L6_2atmpS1401 = _M0L6lengthS458 + 1;
  _M0L4selfS457->$1 = _M0L6_2atmpS1401;
  moonbit_decref(_M0L4selfS457);
  return 0;
}

int32_t _M0MPC15array5Array4pushGUsiEE(
  struct _M0TPB5ArrayGUsiEE* _M0L4selfS460,
  struct _M0TUsiE* _M0L5valueS462
) {
  int32_t _M0L3lenS1402;
  struct _M0TUsiE** _M0L6_2atmpS1404;
  int32_t _M0L6_2atmpS1403;
  int32_t _M0L6lengthS461;
  struct _M0TUsiE** _M0L3bufS1405;
  struct _M0TUsiE* _M0L6_2aoldS1949;
  int32_t _M0L6_2atmpS1406;
  #line 242 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L3lenS1402 = _M0L4selfS460->$1;
  moonbit_incref(_M0L4selfS460);
  #line 243 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L6_2atmpS1404 = _M0MPC15array5Array6bufferGUsiEE(_M0L4selfS460);
  _M0L6_2atmpS1403 = Moonbit_array_length(_M0L6_2atmpS1404);
  moonbit_decref(_M0L6_2atmpS1404);
  if (_M0L3lenS1402 == _M0L6_2atmpS1403) {
    moonbit_incref(_M0L4selfS460);
    #line 244 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
    _M0MPC15array5Array7reallocGUsiEE(_M0L4selfS460);
  }
  _M0L6lengthS461 = _M0L4selfS460->$1;
  _M0L3bufS1405 = _M0L4selfS460->$0;
  _M0L6_2aoldS1949 = (struct _M0TUsiE*)_M0L3bufS1405[_M0L6lengthS461];
  if (_M0L6_2aoldS1949) {
    moonbit_decref(_M0L6_2aoldS1949);
  }
  _M0L3bufS1405[_M0L6lengthS461] = _M0L5valueS462;
  _M0L6_2atmpS1406 = _M0L6lengthS461 + 1;
  _M0L4selfS460->$1 = _M0L6_2atmpS1406;
  moonbit_decref(_M0L4selfS460);
  return 0;
}

int32_t _M0MPC15array5Array7reallocGsE(struct _M0TPB5ArrayGsE* _M0L4selfS452) {
  int32_t _M0L8old__capS451;
  int32_t _M0L8new__capS453;
  #line 182 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L8old__capS451 = _M0L4selfS452->$1;
  if (_M0L8old__capS451 == 0) {
    _M0L8new__capS453 = 8;
  } else {
    _M0L8new__capS453 = _M0L8old__capS451 * 2;
  }
  #line 185 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0MPC15array5Array14resize__bufferGsE(_M0L4selfS452, _M0L8new__capS453);
  return 0;
}

int32_t _M0MPC15array5Array7reallocGUsiEE(
  struct _M0TPB5ArrayGUsiEE* _M0L4selfS455
) {
  int32_t _M0L8old__capS454;
  int32_t _M0L8new__capS456;
  #line 182 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L8old__capS454 = _M0L4selfS455->$1;
  if (_M0L8old__capS454 == 0) {
    _M0L8new__capS456 = 8;
  } else {
    _M0L8new__capS456 = _M0L8old__capS454 * 2;
  }
  #line 185 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0MPC15array5Array14resize__bufferGUsiEE(_M0L4selfS455, _M0L8new__capS456);
  return 0;
}

int32_t _M0MPC15array5Array14resize__bufferGsE(
  struct _M0TPB5ArrayGsE* _M0L4selfS442,
  int32_t _M0L13new__capacityS440
) {
  moonbit_string_t* _M0L8new__bufS439;
  moonbit_string_t* _M0L8old__bufS441;
  int32_t _M0L8old__capS443;
  int32_t _M0L9copy__lenS444;
  moonbit_string_t* _M0L6_2aoldS1951;
  #line 129 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L8new__bufS439
  = (moonbit_string_t*)moonbit_make_ref_array(_M0L13new__capacityS440, (moonbit_string_t)moonbit_string_literal_0.data);
  _M0L8old__bufS441 = _M0L4selfS442->$0;
  _M0L8old__capS443 = Moonbit_array_length(_M0L8old__bufS441);
  if (_M0L8old__capS443 < _M0L13new__capacityS440) {
    _M0L9copy__lenS444 = _M0L8old__capS443;
  } else {
    _M0L9copy__lenS444 = _M0L13new__capacityS440;
  }
  moonbit_incref(_M0L8old__bufS441);
  moonbit_incref(_M0L8new__bufS439);
  #line 134 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0MPB18UninitializedArray12unsafe__blitGsE(_M0L8new__bufS439, 0, _M0L8old__bufS441, 0, _M0L9copy__lenS444);
  _M0L6_2aoldS1951 = _M0L4selfS442->$0;
  moonbit_decref(_M0L6_2aoldS1951);
  _M0L4selfS442->$0 = _M0L8new__bufS439;
  moonbit_decref(_M0L4selfS442);
  return 0;
}

int32_t _M0MPC15array5Array14resize__bufferGUsiEE(
  struct _M0TPB5ArrayGUsiEE* _M0L4selfS448,
  int32_t _M0L13new__capacityS446
) {
  struct _M0TUsiE** _M0L8new__bufS445;
  struct _M0TUsiE** _M0L8old__bufS447;
  int32_t _M0L8old__capS449;
  int32_t _M0L9copy__lenS450;
  struct _M0TUsiE** _M0L6_2aoldS1953;
  #line 129 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L8new__bufS445
  = (struct _M0TUsiE**)moonbit_make_ref_array(_M0L13new__capacityS446, 0);
  _M0L8old__bufS447 = _M0L4selfS448->$0;
  _M0L8old__capS449 = Moonbit_array_length(_M0L8old__bufS447);
  if (_M0L8old__capS449 < _M0L13new__capacityS446) {
    _M0L9copy__lenS450 = _M0L8old__capS449;
  } else {
    _M0L9copy__lenS450 = _M0L13new__capacityS446;
  }
  moonbit_incref(_M0L8old__bufS447);
  moonbit_incref(_M0L8new__bufS445);
  #line 134 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0MPB18UninitializedArray12unsafe__blitGUsiEE(_M0L8new__bufS445, 0, _M0L8old__bufS447, 0, _M0L9copy__lenS450);
  _M0L6_2aoldS1953 = _M0L4selfS448->$0;
  moonbit_decref(_M0L6_2aoldS1953);
  _M0L4selfS448->$0 = _M0L8new__bufS445;
  moonbit_decref(_M0L4selfS448);
  return 0;
}

moonbit_string_t* _M0MPC15array5Array6bufferGsE(
  struct _M0TPB5ArrayGsE* _M0L4selfS437
) {
  moonbit_string_t* _M0L8_2afieldS1955;
  int32_t _M0L6_2acntS2043;
  #line 124 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L8_2afieldS1955 = _M0L4selfS437->$0;
  _M0L6_2acntS2043 = Moonbit_object_header(_M0L4selfS437)->rc;
  if (_M0L6_2acntS2043 > 1) {
    int32_t _M0L11_2anew__cntS2044 = _M0L6_2acntS2043 - 1;
    Moonbit_object_header(_M0L4selfS437)->rc = _M0L11_2anew__cntS2044;
    moonbit_incref(_M0L8_2afieldS1955);
  } else if (_M0L6_2acntS2043 == 1) {
    #line 125 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
    moonbit_free(_M0L4selfS437);
  }
  return _M0L8_2afieldS1955;
}

struct _M0TUsiE** _M0MPC15array5Array6bufferGUsiEE(
  struct _M0TPB5ArrayGUsiEE* _M0L4selfS438
) {
  struct _M0TUsiE** _M0L8_2afieldS1956;
  int32_t _M0L6_2acntS2045;
  #line 124 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L8_2afieldS1956 = _M0L4selfS438->$0;
  _M0L6_2acntS2045 = Moonbit_object_header(_M0L4selfS438)->rc;
  if (_M0L6_2acntS2045 > 1) {
    int32_t _M0L11_2anew__cntS2046 = _M0L6_2acntS2045 - 1;
    Moonbit_object_header(_M0L4selfS438)->rc = _M0L11_2anew__cntS2046;
    moonbit_incref(_M0L8_2afieldS1956);
  } else if (_M0L6_2acntS2045 == 1) {
    #line 125 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
    moonbit_free(_M0L4selfS438);
  }
  return _M0L8_2afieldS1956;
}

struct _M0TPB5ArrayGsE* _M0MPC15array5Array11new_2einnerGsE(
  int32_t _M0L8capacityS436
) {
  #line 53 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  if (_M0L8capacityS436 == 0) {
    moonbit_string_t* _M0L6_2atmpS1395 =
      (moonbit_string_t*)moonbit_empty_ref_array;
    struct _M0TPB5ArrayGsE* _block_2150 =
      (struct _M0TPB5ArrayGsE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGsE));
    Moonbit_object_header(_block_2150)->meta
    = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGsE, $0) >> 2, 1, 0);
    _block_2150->$0 = _M0L6_2atmpS1395;
    _block_2150->$1 = 0;
    return _block_2150;
  } else {
    moonbit_string_t* _M0L6_2atmpS1396 =
      (moonbit_string_t*)moonbit_make_ref_array(_M0L8capacityS436, (moonbit_string_t)moonbit_string_literal_0.data);
    struct _M0TPB5ArrayGsE* _block_2151 =
      (struct _M0TPB5ArrayGsE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGsE));
    Moonbit_object_header(_block_2151)->meta
    = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGsE, $0) >> 2, 1, 0);
    _block_2151->$0 = _M0L6_2atmpS1396;
    _block_2151->$1 = 0;
    return _block_2151;
  }
}

moonbit_string_t _M0IPC16string6StringPB4Show10to__string(
  moonbit_string_t _M0L4selfS435
) {
  #line 262 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  return _M0L4selfS435;
}

int32_t _M0IPB13StringBuilderPB6Logger11write__view(
  struct _M0TPB13StringBuilder* _M0L4selfS434,
  struct _M0TPC16string10StringView _M0L3strS433
) {
  int32_t _M0L8str__lenS432;
  int32_t _M0L3lenS1388;
  int32_t _M0L6_2atmpS1387;
  uint16_t* _M0L4dataS1389;
  int32_t _M0L3lenS1390;
  moonbit_string_t _M0L6_2atmpS1391;
  int32_t _M0L6_2atmpS1392;
  int32_t _M0L3lenS1394;
  int32_t _M0L6_2atmpS1393;
  #line 126 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  moonbit_incref(_M0L3strS433.$0);
  #line 130 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L8str__lenS432 = _M0MPC16string10StringView6length(_M0L3strS433);
  _M0L3lenS1388 = _M0L4selfS434->$1;
  _M0L6_2atmpS1387 = _M0L3lenS1388 + _M0L8str__lenS432;
  moonbit_incref(_M0L4selfS434);
  #line 131 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0MPB13StringBuilder19grow__if__necessary(_M0L4selfS434, _M0L6_2atmpS1387);
  _M0L4dataS1389 = _M0L4selfS434->$0;
  _M0L3lenS1390 = _M0L4selfS434->$1;
  moonbit_incref(_M0L4dataS1389);
  moonbit_incref(_M0L3strS433.$0);
  #line 134 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L6_2atmpS1391 = _M0MPC16string10StringView4data(_M0L3strS433);
  #line 135 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L6_2atmpS1392 = _M0MPC16string10StringView13start__offset(_M0L3strS433);
  #line 132 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0MPC15array10FixedArray26unsafe__blit__from__string(_M0L4dataS1389, _M0L3lenS1390, _M0L6_2atmpS1391, _M0L6_2atmpS1392, _M0L8str__lenS432);
  _M0L3lenS1394 = _M0L4selfS434->$1;
  _M0L6_2atmpS1393 = _M0L3lenS1394 + _M0L8str__lenS432;
  _M0L4selfS434->$1 = _M0L6_2atmpS1393;
  moonbit_decref(_M0L4selfS434);
  return 0;
}

int32_t _M0MPC16string6String24char__length__ge_2einner(
  moonbit_string_t _M0L4selfS424,
  int32_t _M0L3lenS427,
  int32_t _M0L13start__offsetS431,
  int64_t _M0L11end__offsetS422
) {
  int32_t _M0L11end__offsetS421;
  int32_t _M0L5indexS425;
  int32_t _M0L5countS426;
  #line 441 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
  if (_M0L11end__offsetS422 == 4294967296ll) {
    _M0L11end__offsetS421 = Moonbit_array_length(_M0L4selfS424);
  } else {
    int64_t _M0L7_2aSomeS423 = _M0L11end__offsetS422;
    _M0L11end__offsetS421 = (int32_t)_M0L7_2aSomeS423;
  }
  _M0L5indexS425 = _M0L13start__offsetS431;
  _M0L5countS426 = 0;
  while (1) {
    int32_t _if__result_2153;
    if (_M0L5indexS425 < _M0L11end__offsetS421) {
      _if__result_2153 = _M0L5countS426 < _M0L3lenS427;
    } else {
      _if__result_2153 = 0;
    }
    if (_if__result_2153) {
      int32_t _M0L2c1S428 = _M0L4selfS424[_M0L5indexS425];
      int32_t _if__result_2154;
      int32_t _M0L6_2atmpS1385;
      int32_t _M0L6_2atmpS1386;
      #line 452 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
      if (_M0MPC16uint166UInt1622is__leading__surrogate(_M0L2c1S428)) {
        int32_t _M0L6_2atmpS1381 = _M0L5indexS425 + 1;
        _if__result_2154 = _M0L6_2atmpS1381 < _M0L11end__offsetS421;
      } else {
        _if__result_2154 = 0;
      }
      if (_if__result_2154) {
        int32_t _M0L6_2atmpS1384 = _M0L5indexS425 + 1;
        int32_t _M0L2c2S429 = _M0L4selfS424[_M0L6_2atmpS1384];
        #line 454 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
        if (_M0MPC16uint166UInt1623is__trailing__surrogate(_M0L2c2S429)) {
          int32_t _M0L6_2atmpS1382 = _M0L5indexS425 + 2;
          int32_t _M0L6_2atmpS1383 = _M0L5countS426 + 1;
          _M0L5indexS425 = _M0L6_2atmpS1382;
          _M0L5countS426 = _M0L6_2atmpS1383;
          continue;
        } else {
          #line 457 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
          _M0FPC15abort5abortGuE((moonbit_string_t)moonbit_string_literal_46.data);
        }
      }
      _M0L6_2atmpS1385 = _M0L5indexS425 + 1;
      _M0L6_2atmpS1386 = _M0L5countS426 + 1;
      _M0L5indexS425 = _M0L6_2atmpS1385;
      _M0L5countS426 = _M0L6_2atmpS1386;
      continue;
    } else {
      moonbit_decref(_M0L4selfS424);
      return _M0L5countS426 >= _M0L3lenS427;
    }
    break;
  }
}

int32_t _M0MPC15array9ArrayView6lengthGUsRPB3MapGiUWEuQRPC15error5ErrorNsEEEE(
  struct _M0TPB9ArrayViewGUsRPB3MapGiUWEuQRPC15error5ErrorNsEEEE _M0L4selfS418
) {
  int32_t _M0L3endS1375;
  int32_t _M0L5startS1376;
  #line 74 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arrayview.mbt"
  _M0L3endS1375 = _M0L4selfS418.$2;
  _M0L5startS1376 = _M0L4selfS418.$1;
  moonbit_decref(_M0L4selfS418.$0);
  return _M0L3endS1375 - _M0L5startS1376;
}

int32_t _M0MPC15array9ArrayView6lengthGUiUWEuQRPC15error5ErrorNsEEE(
  struct _M0TPB9ArrayViewGUiUWEuQRPC15error5ErrorNsEEE _M0L4selfS419
) {
  int32_t _M0L3endS1377;
  int32_t _M0L5startS1378;
  #line 74 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arrayview.mbt"
  _M0L3endS1377 = _M0L4selfS419.$2;
  _M0L5startS1378 = _M0L4selfS419.$1;
  moonbit_decref(_M0L4selfS419.$0);
  return _M0L3endS1377 - _M0L5startS1378;
}

int32_t _M0MPC15array9ArrayView6lengthGsE(
  struct _M0TPB9ArrayViewGsE _M0L4selfS420
) {
  int32_t _M0L3endS1379;
  int32_t _M0L5startS1380;
  #line 74 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arrayview.mbt"
  _M0L3endS1379 = _M0L4selfS420.$2;
  _M0L5startS1380 = _M0L4selfS420.$1;
  moonbit_decref(_M0L4selfS420.$0);
  return _M0L3endS1379 - _M0L5startS1380;
}

struct _M0TPC16string10StringView _M0MPC16string6String4view(
  moonbit_string_t _M0L4selfS416,
  int64_t _M0L19start__offset_2eoptS414,
  int64_t _M0L11end__offsetS417
) {
  int32_t _M0L13start__offsetS413;
  if (_M0L19start__offset_2eoptS414 == 4294967296ll) {
    _M0L13start__offsetS413 = 0;
  } else {
    int64_t _M0L7_2aSomeS415 = _M0L19start__offset_2eoptS414;
    _M0L13start__offsetS413 = (int32_t)_M0L7_2aSomeS415;
  }
  return _M0MPC16string6String12view_2einner(_M0L4selfS416, _M0L13start__offsetS413, _M0L11end__offsetS417);
}

struct _M0TPC16string10StringView _M0MPC16string6String12view_2einner(
  moonbit_string_t _M0L4selfS411,
  int32_t _M0L13start__offsetS412,
  int64_t _M0L11end__offsetS409
) {
  int32_t _M0L11end__offsetS408;
  int32_t _if__result_2155;
  #line 501 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  if (_M0L11end__offsetS409 == 4294967296ll) {
    _M0L11end__offsetS408 = Moonbit_array_length(_M0L4selfS411);
  } else {
    int64_t _M0L7_2aSomeS410 = _M0L11end__offsetS409;
    _M0L11end__offsetS408 = (int32_t)_M0L7_2aSomeS410;
  }
  if (_M0L13start__offsetS412 >= 0) {
    if (_M0L13start__offsetS412 <= _M0L11end__offsetS408) {
      int32_t _M0L6_2atmpS1374 = Moonbit_array_length(_M0L4selfS411);
      _if__result_2155 = _M0L11end__offsetS408 <= _M0L6_2atmpS1374;
    } else {
      _if__result_2155 = 0;
    }
  } else {
    _if__result_2155 = 0;
  }
  if (_if__result_2155) {
    return (struct _M0TPC16string10StringView){_M0L13start__offsetS412,
                                                 _M0L11end__offsetS408,
                                                 _M0L4selfS411};
  } else {
    moonbit_decref(_M0L4selfS411);
    #line 510 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
    return _M0FPC15abort5abortGRPC16string10StringViewE((moonbit_string_t)moonbit_string_literal_47.data);
  }
}

moonbit_string_t _M0IPC16string10StringViewPB4Show10to__string(
  struct _M0TPC16string10StringView _M0L4selfS407
) {
  moonbit_string_t _M0L3strS1371;
  int32_t _M0L5startS1372;
  int32_t _M0L3endS1373;
  #line 185 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  _M0L3strS1371 = _M0L4selfS407.$0;
  _M0L5startS1372 = _M0L4selfS407.$1;
  _M0L3endS1373 = _M0L4selfS407.$2;
  #line 187 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  return _M0MPC16string6String17unsafe__substring(_M0L3strS1371, _M0L5startS1372, _M0L3endS1373);
}

moonbit_string_t _M0MPC16string6String17unsafe__substring(
  moonbit_string_t _M0L3strS404,
  int32_t _M0L5startS402,
  int32_t _M0L3endS403
) {
  int32_t _if__result_2156;
  int32_t _M0L3lenS405;
  int32_t _M0L6_2atmpS1369;
  int32_t _M0L6_2atmpS1370;
  moonbit_bytes_t _M0L5bytesS406;
  moonbit_bytes_t _M0L6_2atmpS1368;
  #line 91 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
  if (_M0L5startS402 == 0) {
    int32_t _M0L6_2atmpS1367 = Moonbit_array_length(_M0L3strS404);
    _if__result_2156 = _M0L3endS403 == _M0L6_2atmpS1367;
  } else {
    _if__result_2156 = 0;
  }
  if (_if__result_2156) {
    return _M0L3strS404;
  }
  _M0L3lenS405 = _M0L3endS403 - _M0L5startS402;
  _M0L6_2atmpS1369 = _M0L3lenS405 * 2;
  #line 101 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
  _M0L6_2atmpS1370 = _M0IPC14byte4BytePB7Default7default();
  _M0L5bytesS406
  = (moonbit_bytes_t)moonbit_make_bytes(_M0L6_2atmpS1369, _M0L6_2atmpS1370);
  moonbit_incref(_M0L5bytesS406);
  #line 102 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
  _M0MPC15array10FixedArray18blit__from__string(_M0L5bytesS406, 0, _M0L3strS404, _M0L5startS402, _M0L3lenS405);
  _M0L6_2atmpS1368 = _M0L5bytesS406;
  #line 103 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
  return _M0MPC15bytes5Bytes29to__unchecked__string_2einner(_M0L6_2atmpS1368, 0, 4294967296ll);
}

int32_t _M0IPC14byte4BytePB7Default7default() {
  #line 231 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\byte.mbt"
  return 0;
}

moonbit_string_t _M0MPC15bytes5Bytes29to__unchecked__string_2einner(
  moonbit_bytes_t _M0L4selfS397,
  int32_t _M0L6offsetS401,
  int64_t _M0L6lengthS399
) {
  int32_t _M0L3lenS396;
  int32_t _M0L6lengthS398;
  int32_t _if__result_2157;
  #line 76 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
  _M0L3lenS396 = Moonbit_array_length(_M0L4selfS397);
  if (_M0L6lengthS399 == 4294967296ll) {
    _M0L6lengthS398 = _M0L3lenS396 - _M0L6offsetS401;
  } else {
    int64_t _M0L7_2aSomeS400 = _M0L6lengthS399;
    _M0L6lengthS398 = (int32_t)_M0L7_2aSomeS400;
  }
  if (_M0L6offsetS401 >= 0) {
    if (_M0L6lengthS398 >= 0) {
      int32_t _M0L6_2atmpS1366 = _M0L6offsetS401 + _M0L6lengthS398;
      _if__result_2157 = _M0L6_2atmpS1366 <= _M0L3lenS396;
    } else {
      _if__result_2157 = 0;
    }
  } else {
    _if__result_2157 = 0;
  }
  if (_if__result_2157) {
    #line 84 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
    return _M0FPB19unsafe__sub__string(_M0L4selfS397, _M0L6offsetS401, _M0L6lengthS398);
  } else {
    moonbit_decref(_M0L4selfS397);
    #line 83 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
    moonbit_panic();
  }
}

int32_t _M0MPC15array10FixedArray18blit__from__string(
  moonbit_bytes_t _M0L4selfS388,
  int32_t _M0L13bytes__offsetS383,
  moonbit_string_t _M0L3strS390,
  int32_t _M0L11str__offsetS386,
  int32_t _M0L6lengthS384
) {
  int32_t _M0L6_2atmpS1365;
  int32_t _M0L6_2atmpS1364;
  int32_t _M0L2e1S382;
  int32_t _M0L6_2atmpS1363;
  int32_t _M0L2e2S385;
  int32_t _M0L4len1S387;
  int32_t _M0L4len2S389;
  int32_t _if__result_2158;
  #line 124 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
  _M0L6_2atmpS1365 = _M0L6lengthS384 * 2;
  _M0L6_2atmpS1364 = _M0L13bytes__offsetS383 + _M0L6_2atmpS1365;
  _M0L2e1S382 = _M0L6_2atmpS1364 - 1;
  _M0L6_2atmpS1363 = _M0L11str__offsetS386 + _M0L6lengthS384;
  _M0L2e2S385 = _M0L6_2atmpS1363 - 1;
  _M0L4len1S387 = Moonbit_array_length(_M0L4selfS388);
  _M0L4len2S389 = Moonbit_array_length(_M0L3strS390);
  if (_M0L6lengthS384 >= 0) {
    if (_M0L13bytes__offsetS383 >= 0) {
      if (_M0L2e1S382 < _M0L4len1S387) {
        if (_M0L11str__offsetS386 >= 0) {
          _if__result_2158 = _M0L2e2S385 < _M0L4len2S389;
        } else {
          _if__result_2158 = 0;
        }
      } else {
        _if__result_2158 = 0;
      }
    } else {
      _if__result_2158 = 0;
    }
  } else {
    _if__result_2158 = 0;
  }
  if (_if__result_2158) {
    int32_t _M0L16end__str__offsetS391 =
      _M0L11str__offsetS386 + _M0L6lengthS384;
    int32_t _M0L1iS392 = _M0L11str__offsetS386;
    int32_t _M0L1jS393 = _M0L13bytes__offsetS383;
    while (1) {
      if (_M0L1iS392 < _M0L16end__str__offsetS391) {
        int32_t _M0L6_2atmpS1360 = _M0L3strS390[_M0L1iS392];
        int32_t _M0L6_2atmpS1359 = (int32_t)_M0L6_2atmpS1360;
        uint32_t _M0L1cS394 = *(uint32_t*)&_M0L6_2atmpS1359;
        uint32_t _M0L6_2atmpS1355 = _M0L1cS394 & 255u;
        int32_t _M0L6_2atmpS1354;
        int32_t _M0L6_2atmpS1356;
        uint32_t _M0L6_2atmpS1358;
        int32_t _M0L6_2atmpS1357;
        int32_t _M0L6_2atmpS1361;
        int32_t _M0L6_2atmpS1362;
        #line 141 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
        _M0L6_2atmpS1354 = _M0MPC14uint4UInt8to__byte(_M0L6_2atmpS1355);
        if (
          _M0L1jS393 < 0 || _M0L1jS393 >= Moonbit_array_length(_M0L4selfS388)
        ) {
          #line 141 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
          moonbit_panic();
        }
        _M0L4selfS388[_M0L1jS393] = _M0L6_2atmpS1354;
        _M0L6_2atmpS1356 = _M0L1jS393 + 1;
        _M0L6_2atmpS1358 = _M0L1cS394 >> 8;
        #line 142 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
        _M0L6_2atmpS1357 = _M0MPC14uint4UInt8to__byte(_M0L6_2atmpS1358);
        if (
          _M0L6_2atmpS1356 < 0
          || _M0L6_2atmpS1356 >= Moonbit_array_length(_M0L4selfS388)
        ) {
          #line 142 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
          moonbit_panic();
        }
        _M0L4selfS388[_M0L6_2atmpS1356] = _M0L6_2atmpS1357;
        _M0L6_2atmpS1361 = _M0L1iS392 + 1;
        _M0L6_2atmpS1362 = _M0L1jS393 + 2;
        _M0L1iS392 = _M0L6_2atmpS1361;
        _M0L1jS393 = _M0L6_2atmpS1362;
        continue;
      } else {
        moonbit_decref(_M0L3strS390);
        moonbit_decref(_M0L4selfS388);
      }
      break;
    }
  } else {
    moonbit_decref(_M0L3strS390);
    moonbit_decref(_M0L4selfS388);
    #line 137 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
    moonbit_panic();
  }
  return 0;
}

int32_t _M0MPC14uint4UInt8to__byte(uint32_t _M0L4selfS381) {
  int32_t _M0L6_2atmpS1353;
  #line 2518 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\intrinsics.mbt"
  _M0L6_2atmpS1353 = *(int32_t*)&_M0L4selfS381;
  return _M0L6_2atmpS1353 & 0xff;
}

int32_t _M0IPC16string10StringViewPB4Show6output(
  struct _M0TPC16string10StringView _M0L4selfS379,
  struct _M0TPB6Logger _M0L6loggerS380
) {
  #line 166 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  #line 167 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  _M0MPC16string10StringView18escape__to_2einner(_M0L4selfS379, _M0L6loggerS380, 1);
  return 0;
}

struct _M0TWEOs* _M0MPB4Iter3newGsE(struct _M0TWEOs* _M0L1fS378) {
  #line 205 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\iterator.mbt"
  return _M0L1fS378;
}

struct moonbit_result_0 _M0FPB10assert__eqGiE(
  int32_t _M0L1aS372,
  int32_t _M0L1bS373,
  moonbit_string_t _M0L3msgS375,
  moonbit_string_t _M0L3locS377
) {
  #line 45 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
  if (_M0L1aS372 != _M0L1bS373) {
    moonbit_string_t _M0L9fail__msgS374;
    if (_M0L3msgS375 == 0) {
      moonbit_string_t _M0L6_2atmpS1351;
      moonbit_string_t _M0L6_2atmpS1350;
      moonbit_string_t _M0L6_2atmpS1349;
      moonbit_string_t _M0L6_2atmpS1346;
      moonbit_string_t _M0L6_2atmpS1348;
      moonbit_string_t _M0L6_2atmpS1347;
      moonbit_string_t _M0L6_2atmpS1345;
      if (_M0L3msgS375) {
        moonbit_decref(_M0L3msgS375);
      }
      #line 57 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
      _M0L6_2atmpS1351 = _M0FPB13debug__stringGiE(_M0L1aS372);
      #line 57 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
      _M0L6_2atmpS1350
      = _M0IPC16string6StringPB4Show10to__string(_M0L6_2atmpS1351);
      #line 55 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
      _M0L6_2atmpS1349
      = moonbit_add_string((moonbit_string_t)moonbit_string_literal_41.data, _M0L6_2atmpS1350);
      moonbit_decref(_M0L6_2atmpS1350);
      #line 55 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
      _M0L6_2atmpS1346
      = moonbit_add_string(_M0L6_2atmpS1349, (moonbit_string_t)moonbit_string_literal_48.data);
      moonbit_decref(_M0L6_2atmpS1349);
      #line 57 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
      _M0L6_2atmpS1348 = _M0FPB13debug__stringGiE(_M0L1bS373);
      #line 57 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
      _M0L6_2atmpS1347
      = _M0IPC16string6StringPB4Show10to__string(_M0L6_2atmpS1348);
      #line 55 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
      _M0L6_2atmpS1345
      = moonbit_add_string(_M0L6_2atmpS1346, _M0L6_2atmpS1347);
      moonbit_decref(_M0L6_2atmpS1347);
      moonbit_decref(_M0L6_2atmpS1346);
      #line 55 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
      _M0L9fail__msgS374
      = moonbit_add_string(_M0L6_2atmpS1345, (moonbit_string_t)moonbit_string_literal_41.data);
      moonbit_decref(_M0L6_2atmpS1345);
    } else {
      moonbit_string_t _M0L7_2aSomeS376 = _M0L3msgS375;
      _M0L9fail__msgS374 = _M0L7_2aSomeS376;
    }
    #line 59 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
    return _M0FPB4failGuE(_M0L9fail__msgS374, _M0L3locS377);
  } else {
    int32_t _M0L6_2atmpS1352;
    struct moonbit_result_0 _result_2160;
    moonbit_decref(_M0L3locS377);
    if (_M0L3msgS375) {
      moonbit_decref(_M0L3msgS375);
    }
    _M0L6_2atmpS1352 = 0;
    _result_2160.tag = 1;
    _result_2160.data.ok = _M0L6_2atmpS1352;
    return _result_2160;
  }
}

struct moonbit_result_0 _M0FPB4failGuE(
  moonbit_string_t _M0L3msgS371,
  moonbit_string_t _M0L3locS370
) {
  moonbit_string_t _M0L6_2atmpS1344;
  moonbit_string_t _M0L6_2atmpS1342;
  moonbit_string_t _M0L6_2atmpS1343;
  moonbit_string_t _M0L6_2atmpS1341;
  void* _M0L48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailureS1340;
  struct moonbit_result_0 _result_2161;
  #line 56 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
  #line 58 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
  _M0L6_2atmpS1344 = _M0IPB9SourceLocPB4Show10to__string(_M0L3locS370);
  #line 58 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
  _M0L6_2atmpS1342
  = moonbit_add_string(_M0L6_2atmpS1344, (moonbit_string_t)moonbit_string_literal_49.data);
  moonbit_decref(_M0L6_2atmpS1344);
  #line 58 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
  _M0L6_2atmpS1343 = _M0IPC16string6StringPB4Show10to__string(_M0L3msgS371);
  #line 58 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
  _M0L6_2atmpS1341 = moonbit_add_string(_M0L6_2atmpS1342, _M0L6_2atmpS1343);
  moonbit_decref(_M0L6_2atmpS1343);
  moonbit_decref(_M0L6_2atmpS1342);
  _M0L48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailureS1340
  = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure));
  Moonbit_object_header(_M0L48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailureS1340)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure, $0) >> 2, 1, 0);
  ((struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure*)_M0L48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailureS1340)->$0
  = _M0L6_2atmpS1341;
  _result_2161.tag = 0;
  _result_2161.data.err
  = _M0L48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailureS1340;
  return _result_2161;
}

moonbit_string_t _M0FPB13debug__stringGiE(int32_t _M0L1tS369) {
  struct _M0TPB13StringBuilder* _M0L3bufS368;
  struct _M0TPB6Logger _M0L6_2atmpS1339;
  #line 16 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
  #line 17 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
  _M0L3bufS368 = _M0MPB13StringBuilder11new_2einner(50);
  moonbit_incref(_M0L3bufS368);
  _M0L6_2atmpS1339
  = (struct _M0TPB6Logger){
    _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id,
      _M0L3bufS368
  };
  #line 18 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
  _M0IPC13int3IntPB4Show6output(_M0L1tS369, _M0L6_2atmpS1339);
  #line 19 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\assert.mbt"
  return _M0MPB13StringBuilder10to__string(_M0L3bufS368);
}

moonbit_string_t _M0MPC13int3Int18to__string_2einner(
  int32_t _M0L4selfS352,
  int32_t _M0L5radixS351
) {
  int32_t _if__result_2162;
  int32_t _M0L12is__negativeS353;
  uint32_t _M0L3numS354;
  uint16_t* _M0L6bufferS355;
  #line 209 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
  if (_M0L5radixS351 < 2) {
    _if__result_2162 = 1;
  } else {
    _if__result_2162 = _M0L5radixS351 > 36;
  }
  if (_if__result_2162) {
    #line 213 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
    _M0FPC15abort5abortGuE((moonbit_string_t)moonbit_string_literal_50.data);
  }
  if (_M0L4selfS352 == 0) {
    return (moonbit_string_t)moonbit_string_literal_51.data;
  }
  _M0L12is__negativeS353 = _M0L4selfS352 < 0;
  if (_M0L12is__negativeS353) {
    int32_t _M0L6_2atmpS1338 = -_M0L4selfS352;
    _M0L3numS354 = *(uint32_t*)&_M0L6_2atmpS1338;
  } else {
    _M0L3numS354 = *(uint32_t*)&_M0L4selfS352;
  }
  switch (_M0L5radixS351) {
    case 10: {
      int32_t _M0L10digit__lenS356;
      int32_t _M0L6_2atmpS1335;
      int32_t _M0L10total__lenS357;
      uint16_t* _M0L6bufferS358;
      int32_t _M0L12digit__startS359;
      #line 235 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
      _M0L10digit__lenS356 = _M0FPB12dec__count32(_M0L3numS354);
      if (_M0L12is__negativeS353) {
        _M0L6_2atmpS1335 = 1;
      } else {
        _M0L6_2atmpS1335 = 0;
      }
      _M0L10total__lenS357 = _M0L10digit__lenS356 + _M0L6_2atmpS1335;
      _M0L6bufferS358
      = (uint16_t*)moonbit_make_string(_M0L10total__lenS357, 0);
      if (_M0L12is__negativeS353) {
        _M0L12digit__startS359 = 1;
      } else {
        _M0L12digit__startS359 = 0;
      }
      moonbit_incref(_M0L6bufferS358);
      #line 239 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
      _M0FPB20int__to__string__dec(_M0L6bufferS358, _M0L3numS354, _M0L12digit__startS359, _M0L10total__lenS357);
      _M0L6bufferS355 = _M0L6bufferS358;
      break;
    }
    
    case 16: {
      int32_t _M0L10digit__lenS360;
      int32_t _M0L6_2atmpS1336;
      int32_t _M0L10total__lenS361;
      uint16_t* _M0L6bufferS362;
      int32_t _M0L12digit__startS363;
      #line 243 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
      _M0L10digit__lenS360 = _M0FPB12hex__count32(_M0L3numS354);
      if (_M0L12is__negativeS353) {
        _M0L6_2atmpS1336 = 1;
      } else {
        _M0L6_2atmpS1336 = 0;
      }
      _M0L10total__lenS361 = _M0L10digit__lenS360 + _M0L6_2atmpS1336;
      _M0L6bufferS362
      = (uint16_t*)moonbit_make_string(_M0L10total__lenS361, 0);
      if (_M0L12is__negativeS353) {
        _M0L12digit__startS363 = 1;
      } else {
        _M0L12digit__startS363 = 0;
      }
      moonbit_incref(_M0L6bufferS362);
      #line 247 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
      _M0FPB20int__to__string__hex(_M0L6bufferS362, _M0L3numS354, _M0L12digit__startS363, _M0L10total__lenS361);
      _M0L6bufferS355 = _M0L6bufferS362;
      break;
    }
    default: {
      int32_t _M0L10digit__lenS364;
      int32_t _M0L6_2atmpS1337;
      int32_t _M0L10total__lenS365;
      uint16_t* _M0L6bufferS366;
      int32_t _M0L12digit__startS367;
      #line 251 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
      _M0L10digit__lenS364
      = _M0FPB14radix__count32(_M0L3numS354, _M0L5radixS351);
      if (_M0L12is__negativeS353) {
        _M0L6_2atmpS1337 = 1;
      } else {
        _M0L6_2atmpS1337 = 0;
      }
      _M0L10total__lenS365 = _M0L10digit__lenS364 + _M0L6_2atmpS1337;
      _M0L6bufferS366
      = (uint16_t*)moonbit_make_string(_M0L10total__lenS365, 0);
      if (_M0L12is__negativeS353) {
        _M0L12digit__startS367 = 1;
      } else {
        _M0L12digit__startS367 = 0;
      }
      moonbit_incref(_M0L6bufferS366);
      #line 255 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
      _M0FPB24int__to__string__generic(_M0L6bufferS366, _M0L3numS354, _M0L12digit__startS367, _M0L10total__lenS365, _M0L5radixS351);
      _M0L6bufferS355 = _M0L6bufferS366;
      break;
    }
  }
  if (_M0L12is__negativeS353) {
    _M0L6bufferS355[0] = 45;
  }
  return _M0L6bufferS355;
}

int32_t _M0FPB14radix__count32(
  uint32_t _M0L5valueS345,
  int32_t _M0L5radixS347
) {
  uint32_t _M0L4baseS346;
  uint32_t _M0L3numS348;
  int32_t _M0L5countS349;
  #line 189 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
  if (_M0L5valueS345 == 0u) {
    return 1;
  }
  _M0L4baseS346 = *(uint32_t*)&_M0L5radixS347;
  _M0L3numS348 = _M0L5valueS345;
  _M0L5countS349 = 0;
  while (1) {
    if (_M0L3numS348 > 0u) {
      uint32_t _M0L6_2atmpS1333 = _M0L3numS348 / _M0L4baseS346;
      int32_t _M0L6_2atmpS1334 = _M0L5countS349 + 1;
      _M0L3numS348 = _M0L6_2atmpS1333;
      _M0L5countS349 = _M0L6_2atmpS1334;
      continue;
    } else {
      return _M0L5countS349;
    }
    break;
  }
}

int32_t _M0FPB12hex__count32(uint32_t _M0L5valueS343) {
  #line 177 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
  if (_M0L5valueS343 == 0u) {
    return 1;
  } else {
    int32_t _M0L14leading__zerosS344;
    int32_t _M0L6_2atmpS1332;
    int32_t _M0L6_2atmpS1331;
    #line 182 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
    _M0L14leading__zerosS344 = moonbit_clz32(_M0L5valueS343);
    _M0L6_2atmpS1332 = 31 - _M0L14leading__zerosS344;
    _M0L6_2atmpS1331 = _M0L6_2atmpS1332 / 4;
    return _M0L6_2atmpS1331 + 1;
  }
}

int32_t _M0FPB12dec__count32(uint32_t _M0L5valueS342) {
  #line 143 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
  if (_M0L5valueS342 >= 100000u) {
    if (_M0L5valueS342 >= 10000000u) {
      if (_M0L5valueS342 >= 1000000000u) {
        return 10;
      } else if (_M0L5valueS342 >= 100000000u) {
        return 9;
      } else {
        return 8;
      }
    } else if (_M0L5valueS342 >= 1000000u) {
      return 7;
    } else {
      return 6;
    }
  } else if (_M0L5valueS342 >= 1000u) {
    if (_M0L5valueS342 >= 10000u) {
      return 5;
    } else {
      return 4;
    }
  } else if (_M0L5valueS342 >= 100u) {
    return 3;
  } else if (_M0L5valueS342 >= 10u) {
    return 2;
  } else {
    return 1;
  }
}

int32_t _M0FPB20int__to__string__dec(
  uint16_t* _M0L6bufferS328,
  uint32_t _M0L3numS340,
  int32_t _M0L12digit__startS329,
  int32_t _M0L10total__lenS341
) {
  int32_t _M0L6_2atmpS1330;
  uint32_t _M0L3numS318;
  int32_t _M0L6offsetS319;
  #line 88 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
  _M0L6_2atmpS1330 = _M0L10total__lenS341 - _M0L12digit__startS329;
  _M0L3numS318 = _M0L3numS340;
  _M0L6offsetS319 = _M0L6_2atmpS1330;
  while (1) {
    if (_M0L3numS318 >= 10000u) {
      uint32_t _M0L1tS320 = _M0L3numS318 / 10000u;
      uint32_t _M0L6_2atmpS1307 = _M0L3numS318 % 10000u;
      int32_t _M0L1rS321 = *(int32_t*)&_M0L6_2atmpS1307;
      int32_t _M0L2d1S322 = _M0L1rS321 / 100;
      int32_t _M0L2d2S323 = _M0L1rS321 % 100;
      int32_t _M0L6_2atmpS1306 = _M0L2d1S322 / 10;
      int32_t _M0L6_2atmpS1305 = 48 + _M0L6_2atmpS1306;
      int32_t _M0L6d1__hiS324 = (uint16_t)_M0L6_2atmpS1305;
      int32_t _M0L6_2atmpS1304 = _M0L2d1S322 % 10;
      int32_t _M0L6_2atmpS1303 = 48 + _M0L6_2atmpS1304;
      int32_t _M0L6d1__loS325 = (uint16_t)_M0L6_2atmpS1303;
      int32_t _M0L6_2atmpS1302 = _M0L2d2S323 / 10;
      int32_t _M0L6_2atmpS1301 = 48 + _M0L6_2atmpS1302;
      int32_t _M0L6d2__hiS326 = (uint16_t)_M0L6_2atmpS1301;
      int32_t _M0L6_2atmpS1300 = _M0L2d2S323 % 10;
      int32_t _M0L6_2atmpS1299 = 48 + _M0L6_2atmpS1300;
      int32_t _M0L6d2__loS327 = (uint16_t)_M0L6_2atmpS1299;
      int32_t _M0L6_2atmpS1291 = _M0L12digit__startS329 + _M0L6offsetS319;
      int32_t _M0L6_2atmpS1290 = _M0L6_2atmpS1291 - 4;
      int32_t _M0L6_2atmpS1293;
      int32_t _M0L6_2atmpS1292;
      int32_t _M0L6_2atmpS1295;
      int32_t _M0L6_2atmpS1294;
      int32_t _M0L6_2atmpS1297;
      int32_t _M0L6_2atmpS1296;
      int32_t _M0L6_2atmpS1298;
      _M0L6bufferS328[_M0L6_2atmpS1290] = _M0L6d1__hiS324;
      _M0L6_2atmpS1293 = _M0L12digit__startS329 + _M0L6offsetS319;
      _M0L6_2atmpS1292 = _M0L6_2atmpS1293 - 3;
      _M0L6bufferS328[_M0L6_2atmpS1292] = _M0L6d1__loS325;
      _M0L6_2atmpS1295 = _M0L12digit__startS329 + _M0L6offsetS319;
      _M0L6_2atmpS1294 = _M0L6_2atmpS1295 - 2;
      _M0L6bufferS328[_M0L6_2atmpS1294] = _M0L6d2__hiS326;
      _M0L6_2atmpS1297 = _M0L12digit__startS329 + _M0L6offsetS319;
      _M0L6_2atmpS1296 = _M0L6_2atmpS1297 - 1;
      _M0L6bufferS328[_M0L6_2atmpS1296] = _M0L6d2__loS327;
      _M0L6_2atmpS1298 = _M0L6offsetS319 - 4;
      _M0L3numS318 = _M0L1tS320;
      _M0L6offsetS319 = _M0L6_2atmpS1298;
      continue;
    } else {
      int32_t _M0L6_2atmpS1329 = *(int32_t*)&_M0L3numS318;
      int32_t _M0L9remainingS331 = _M0L6_2atmpS1329;
      int32_t _M0L6offsetS332 = _M0L6offsetS319;
      while (1) {
        if (_M0L9remainingS331 >= 100) {
          int32_t _M0L1tS333 = _M0L9remainingS331 / 100;
          int32_t _M0L1dS334 = _M0L9remainingS331 % 100;
          int32_t _M0L6_2atmpS1316 = _M0L1dS334 / 10;
          int32_t _M0L6_2atmpS1315 = 48 + _M0L6_2atmpS1316;
          int32_t _M0L5d__hiS335 = (uint16_t)_M0L6_2atmpS1315;
          int32_t _M0L6_2atmpS1314 = _M0L1dS334 % 10;
          int32_t _M0L6_2atmpS1313 = 48 + _M0L6_2atmpS1314;
          int32_t _M0L5d__loS336 = (uint16_t)_M0L6_2atmpS1313;
          int32_t _M0L6_2atmpS1309 = _M0L12digit__startS329 + _M0L6offsetS332;
          int32_t _M0L6_2atmpS1308 = _M0L6_2atmpS1309 - 2;
          int32_t _M0L6_2atmpS1311;
          int32_t _M0L6_2atmpS1310;
          int32_t _M0L6_2atmpS1312;
          _M0L6bufferS328[_M0L6_2atmpS1308] = _M0L5d__hiS335;
          _M0L6_2atmpS1311 = _M0L12digit__startS329 + _M0L6offsetS332;
          _M0L6_2atmpS1310 = _M0L6_2atmpS1311 - 1;
          _M0L6bufferS328[_M0L6_2atmpS1310] = _M0L5d__loS336;
          _M0L6_2atmpS1312 = _M0L6offsetS332 - 2;
          _M0L9remainingS331 = _M0L1tS333;
          _M0L6offsetS332 = _M0L6_2atmpS1312;
          continue;
        } else if (_M0L9remainingS331 >= 10) {
          int32_t _M0L6_2atmpS1324 = _M0L9remainingS331 / 10;
          int32_t _M0L6_2atmpS1323 = 48 + _M0L6_2atmpS1324;
          int32_t _M0L5d__hiS338 = (uint16_t)_M0L6_2atmpS1323;
          int32_t _M0L6_2atmpS1322 = _M0L9remainingS331 % 10;
          int32_t _M0L6_2atmpS1321 = 48 + _M0L6_2atmpS1322;
          int32_t _M0L5d__loS339 = (uint16_t)_M0L6_2atmpS1321;
          int32_t _M0L6_2atmpS1318 = _M0L12digit__startS329 + _M0L6offsetS332;
          int32_t _M0L6_2atmpS1317 = _M0L6_2atmpS1318 - 2;
          int32_t _M0L6_2atmpS1320;
          int32_t _M0L6_2atmpS1319;
          _M0L6bufferS328[_M0L6_2atmpS1317] = _M0L5d__hiS338;
          _M0L6_2atmpS1320 = _M0L12digit__startS329 + _M0L6offsetS332;
          _M0L6_2atmpS1319 = _M0L6_2atmpS1320 - 1;
          _M0L6bufferS328[_M0L6_2atmpS1319] = _M0L5d__loS339;
          moonbit_decref(_M0L6bufferS328);
        } else {
          int32_t _M0L6_2atmpS1328 = _M0L12digit__startS329 + _M0L6offsetS332;
          int32_t _M0L6_2atmpS1325 = _M0L6_2atmpS1328 - 1;
          int32_t _M0L6_2atmpS1327 = 48 + _M0L9remainingS331;
          int32_t _M0L6_2atmpS1326 = (uint16_t)_M0L6_2atmpS1327;
          _M0L6bufferS328[_M0L6_2atmpS1325] = _M0L6_2atmpS1326;
          moonbit_decref(_M0L6bufferS328);
        }
        break;
      }
    }
    break;
  }
  return 0;
}

int32_t _M0FPB24int__to__string__generic(
  uint16_t* _M0L6bufferS308,
  uint32_t _M0L3numS312,
  int32_t _M0L12digit__startS309,
  int32_t _M0L10total__lenS311,
  int32_t _M0L5radixS302
) {
  uint32_t _M0L4baseS301;
  int32_t _M0L6_2atmpS1275;
  int32_t _M0L6_2atmpS1274;
  #line 57 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
  _M0L4baseS301 = *(uint32_t*)&_M0L5radixS302;
  _M0L6_2atmpS1275 = _M0L5radixS302 - 1;
  _M0L6_2atmpS1274 = _M0L5radixS302 & _M0L6_2atmpS1275;
  if (_M0L6_2atmpS1274 == 0) {
    int32_t _M0L5shiftS303;
    uint32_t _M0L4maskS304;
    int32_t _M0L6_2atmpS1282;
    int32_t _M0L6offsetS305;
    uint32_t _M0L1nS306;
    #line 68 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
    _M0L5shiftS303 = moonbit_ctz32(_M0L5radixS302);
    _M0L4maskS304 = _M0L4baseS301 - 1u;
    _M0L6_2atmpS1282 = _M0L10total__lenS311 - _M0L12digit__startS309;
    _M0L6offsetS305 = _M0L6_2atmpS1282;
    _M0L1nS306 = _M0L3numS312;
    while (1) {
      if (_M0L1nS306 > 0u) {
        uint32_t _M0L6_2atmpS1281 = _M0L1nS306 & _M0L4maskS304;
        int32_t _M0L5digitS307 = *(int32_t*)&_M0L6_2atmpS1281;
        int32_t _M0L6_2atmpS1278 = _M0L12digit__startS309 + _M0L6offsetS305;
        int32_t _M0L6_2atmpS1276 = _M0L6_2atmpS1278 - 1;
        int32_t _M0L6_2atmpS1277 =
          ((moonbit_string_t)moonbit_string_literal_52.data)[_M0L5digitS307];
        int32_t _M0L6_2atmpS1279;
        uint32_t _M0L6_2atmpS1280;
        _M0L6bufferS308[_M0L6_2atmpS1276] = _M0L6_2atmpS1277;
        _M0L6_2atmpS1279 = _M0L6offsetS305 - 1;
        _M0L6_2atmpS1280 = _M0L1nS306 >> (_M0L5shiftS303 & 31);
        _M0L6offsetS305 = _M0L6_2atmpS1279;
        _M0L1nS306 = _M0L6_2atmpS1280;
        continue;
      } else {
        moonbit_decref(_M0L6bufferS308);
      }
      break;
    }
  } else {
    int32_t _M0L6_2atmpS1289 = _M0L10total__lenS311 - _M0L12digit__startS309;
    int32_t _M0L6offsetS313 = _M0L6_2atmpS1289;
    uint32_t _M0L1nS314 = _M0L3numS312;
    while (1) {
      if (_M0L1nS314 > 0u) {
        uint32_t _M0L1qS315 = _M0L1nS314 / _M0L4baseS301;
        uint32_t _M0L6_2atmpS1288 = _M0L1qS315 * _M0L4baseS301;
        uint32_t _M0L6_2atmpS1287 = _M0L1nS314 - _M0L6_2atmpS1288;
        int32_t _M0L5digitS316 = *(int32_t*)&_M0L6_2atmpS1287;
        int32_t _M0L6_2atmpS1285 = _M0L12digit__startS309 + _M0L6offsetS313;
        int32_t _M0L6_2atmpS1283 = _M0L6_2atmpS1285 - 1;
        int32_t _M0L6_2atmpS1284 =
          ((moonbit_string_t)moonbit_string_literal_52.data)[_M0L5digitS316];
        int32_t _M0L6_2atmpS1286;
        _M0L6bufferS308[_M0L6_2atmpS1283] = _M0L6_2atmpS1284;
        _M0L6_2atmpS1286 = _M0L6offsetS313 - 1;
        _M0L6offsetS313 = _M0L6_2atmpS1286;
        _M0L1nS314 = _M0L1qS315;
        continue;
      } else {
        moonbit_decref(_M0L6bufferS308);
      }
      break;
    }
  }
  return 0;
}

int32_t _M0FPB20int__to__string__hex(
  uint16_t* _M0L6bufferS295,
  uint32_t _M0L3numS300,
  int32_t _M0L12digit__startS296,
  int32_t _M0L10total__lenS299
) {
  int32_t _M0L6_2atmpS1273;
  int32_t _M0L6offsetS290;
  uint32_t _M0L1nS291;
  #line 29 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
  _M0L6_2atmpS1273 = _M0L10total__lenS299 - _M0L12digit__startS296;
  _M0L6offsetS290 = _M0L6_2atmpS1273;
  _M0L1nS291 = _M0L3numS300;
  while (1) {
    if (_M0L6offsetS290 >= 2) {
      uint32_t _M0L6_2atmpS1270 = _M0L1nS291 & 255u;
      int32_t _M0L9byte__valS292 = *(int32_t*)&_M0L6_2atmpS1270;
      int32_t _M0L2hiS293 = _M0L9byte__valS292 / 16;
      int32_t _M0L2loS294 = _M0L9byte__valS292 % 16;
      int32_t _M0L6_2atmpS1264 = _M0L12digit__startS296 + _M0L6offsetS290;
      int32_t _M0L6_2atmpS1262 = _M0L6_2atmpS1264 - 2;
      int32_t _M0L6_2atmpS1263 =
        ((moonbit_string_t)moonbit_string_literal_52.data)[_M0L2hiS293];
      int32_t _M0L6_2atmpS1267;
      int32_t _M0L6_2atmpS1265;
      int32_t _M0L6_2atmpS1266;
      int32_t _M0L6_2atmpS1268;
      uint32_t _M0L6_2atmpS1269;
      _M0L6bufferS295[_M0L6_2atmpS1262] = _M0L6_2atmpS1263;
      _M0L6_2atmpS1267 = _M0L12digit__startS296 + _M0L6offsetS290;
      _M0L6_2atmpS1265 = _M0L6_2atmpS1267 - 1;
      _M0L6_2atmpS1266
      = ((moonbit_string_t)moonbit_string_literal_52.data)[
        _M0L2loS294
      ];
      _M0L6bufferS295[_M0L6_2atmpS1265] = _M0L6_2atmpS1266;
      _M0L6_2atmpS1268 = _M0L6offsetS290 - 2;
      _M0L6_2atmpS1269 = _M0L1nS291 >> 8;
      _M0L6offsetS290 = _M0L6_2atmpS1268;
      _M0L1nS291 = _M0L6_2atmpS1269;
      continue;
    } else if (_M0L6offsetS290 == 1) {
      uint32_t _M0L6_2atmpS1272 = _M0L1nS291 & 15u;
      int32_t _M0L6nibbleS298 = *(int32_t*)&_M0L6_2atmpS1272;
      int32_t _M0L6_2atmpS1271 =
        ((moonbit_string_t)moonbit_string_literal_52.data)[_M0L6nibbleS298];
      _M0L6bufferS295[_M0L12digit__startS296] = _M0L6_2atmpS1271;
      moonbit_decref(_M0L6bufferS295);
    } else {
      moonbit_decref(_M0L6bufferS295);
    }
    break;
  }
  return 0;
}

moonbit_string_t _M0MPB4Iter4nextGsE(struct _M0TWEOs* _M0L4selfS289) {
  struct _M0TWEOs* _M0L7_2afuncS288;
  #line 28 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\iterator.mbt"
  _M0L7_2afuncS288 = _M0L4selfS289;
  #line 31 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\iterator.mbt"
  return _M0L7_2afuncS288->code(_M0L7_2afuncS288);
}

moonbit_string_t _M0IP016_24default__implPB4Show10to__stringGRPB7FailureE(
  void* _M0L4selfS287
) {
  struct _M0TPB13StringBuilder* _M0L6loggerS286;
  struct _M0TPB6Logger _M0L6_2atmpS1261;
  #line 140 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  #line 141 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0L6loggerS286 = _M0MPB13StringBuilder11new_2einner(0);
  moonbit_incref(_M0L6loggerS286);
  _M0L6_2atmpS1261
  = (struct _M0TPB6Logger){
    _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id,
      _M0L6loggerS286
  };
  #line 142 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0IPB7FailurePB4Show6output(_M0L4selfS287, _M0L6_2atmpS1261);
  #line 143 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  return _M0MPB13StringBuilder10to__string(_M0L6loggerS286);
}

int32_t _M0MPC16string10StringView13start__offset(
  struct _M0TPC16string10StringView _M0L4selfS285
) {
  int32_t _result_2169;
  #line 98 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  _result_2169 = _M0L4selfS285.$1;
  moonbit_decref(_M0L4selfS285.$0);
  return _result_2169;
}

moonbit_string_t _M0MPC16string10StringView4data(
  struct _M0TPC16string10StringView _M0L4selfS284
) {
  #line 91 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  return _M0L4selfS284.$0;
}

int32_t _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE(
  struct _M0TPB13StringBuilder* _M0L4selfS280,
  moonbit_string_t _M0L5valueS281,
  int32_t _M0L5startS282,
  int32_t _M0L3lenS283
) {
  int32_t _M0L6_2atmpS1260;
  int64_t _M0L6_2atmpS1259;
  struct _M0TPC16string10StringView _M0L6_2atmpS1258;
  #line 102 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0L6_2atmpS1260 = _M0L5startS282 + _M0L3lenS283;
  _M0L6_2atmpS1259 = (int64_t)_M0L6_2atmpS1260;
  #line 103 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0L6_2atmpS1258
  = _M0MPC16string6String11sub_2einner(_M0L5valueS281, _M0L5startS282, _M0L6_2atmpS1259);
  #line 103 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0IPB13StringBuilderPB6Logger11write__view(_M0L4selfS280, _M0L6_2atmpS1258);
  return 0;
}

struct _M0TPC16string10StringView _M0MPC16string6String11sub_2einner(
  moonbit_string_t _M0L4selfS273,
  int32_t _M0L5startS279,
  int64_t _M0L3endS275
) {
  int32_t _M0L3lenS272;
  int32_t _M0L3endS274;
  int32_t _M0L5startS278;
  int32_t _if__result_2170;
  #line 639 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  _M0L3lenS272 = Moonbit_array_length(_M0L4selfS273);
  if (_M0L3endS275 == 4294967296ll) {
    _M0L3endS274 = _M0L3lenS272;
  } else {
    int64_t _M0L7_2aSomeS276 = _M0L3endS275;
    int32_t _M0L6_2aendS277 = (int32_t)_M0L7_2aSomeS276;
    if (_M0L6_2aendS277 < 0) {
      _M0L3endS274 = _M0L3lenS272 + _M0L6_2aendS277;
    } else {
      _M0L3endS274 = _M0L6_2aendS277;
    }
  }
  if (_M0L5startS279 < 0) {
    _M0L5startS278 = _M0L3lenS272 + _M0L5startS279;
  } else {
    _M0L5startS278 = _M0L5startS279;
  }
  if (_M0L5startS278 >= 0) {
    if (_M0L5startS278 <= _M0L3endS274) {
      _if__result_2170 = _M0L3endS274 <= _M0L3lenS272;
    } else {
      _if__result_2170 = 0;
    }
  } else {
    _if__result_2170 = 0;
  }
  if (_if__result_2170) {
    if (_M0L5startS278 < _M0L3lenS272) {
      int32_t _M0L6_2atmpS1255 = _M0L4selfS273[_M0L5startS278];
      int32_t _M0L6_2atmpS1254;
      #line 649 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
      _M0L6_2atmpS1254
      = _M0MPC16uint166UInt1623is__trailing__surrogate(_M0L6_2atmpS1255);
      if (!_M0L6_2atmpS1254) {
        
      } else {
        #line 649 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
        moonbit_panic();
      }
    }
    if (_M0L3endS274 < _M0L3lenS272) {
      int32_t _M0L6_2atmpS1257 = _M0L4selfS273[_M0L3endS274];
      int32_t _M0L6_2atmpS1256;
      #line 652 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
      _M0L6_2atmpS1256
      = _M0MPC16uint166UInt1623is__trailing__surrogate(_M0L6_2atmpS1257);
      if (!_M0L6_2atmpS1256) {
        
      } else {
        #line 652 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
        moonbit_panic();
      }
    }
    return (struct _M0TPC16string10StringView){_M0L5startS278,
                                                 _M0L3endS274,
                                                 _M0L4selfS273};
  } else {
    moonbit_decref(_M0L4selfS273);
    #line 647 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
    moonbit_panic();
  }
}

int32_t _M0IP016_24default__implPB4Hash4hashGiE(int32_t _M0L4selfS269) {
  struct _M0TPB6Hasher* _M0L1hS268;
  #line 79 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  #line 80 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0L1hS268 = _M0MPB6Hasher3new(4294967296ll);
  moonbit_incref(_M0L1hS268);
  #line 81 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0MPB6Hasher7combineGiE(_M0L1hS268, _M0L4selfS269);
  #line 82 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  return _M0MPB6Hasher8finalize(_M0L1hS268);
}

int32_t _M0IP016_24default__implPB4Hash4hashGsE(
  moonbit_string_t _M0L4selfS271
) {
  struct _M0TPB6Hasher* _M0L1hS270;
  #line 79 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  #line 80 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0L1hS270 = _M0MPB6Hasher3new(4294967296ll);
  moonbit_incref(_M0L1hS270);
  #line 81 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0MPB6Hasher7combineGsE(_M0L1hS270, _M0L4selfS271);
  #line 82 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  return _M0MPB6Hasher8finalize(_M0L1hS270);
}

struct _M0TPB6Hasher* _M0MPB6Hasher3new(int64_t _M0L10seed_2eoptS266) {
  int32_t _M0L4seedS265;
  if (_M0L10seed_2eoptS266 == 4294967296ll) {
    _M0L4seedS265 = 0;
  } else {
    int64_t _M0L7_2aSomeS267 = _M0L10seed_2eoptS266;
    _M0L4seedS265 = (int32_t)_M0L7_2aSomeS267;
  }
  return _M0MPB6Hasher11new_2einner(_M0L4seedS265);
}

struct _M0TPB6Hasher* _M0MPB6Hasher11new_2einner(int32_t _M0L4seedS264) {
  uint32_t _M0L6_2atmpS1253;
  uint32_t _M0L6_2atmpS1252;
  struct _M0TPB6Hasher* _block_2171;
  #line 75 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0L6_2atmpS1253 = *(uint32_t*)&_M0L4seedS264;
  _M0L6_2atmpS1252 = _M0L6_2atmpS1253 + 374761393u;
  _block_2171
  = (struct _M0TPB6Hasher*)moonbit_malloc(sizeof(struct _M0TPB6Hasher));
  Moonbit_object_header(_block_2171)->meta
  = Moonbit_make_regular_object_header(sizeof(struct _M0TPB6Hasher) >> 2, 0, 0);
  _block_2171->$0 = _M0L6_2atmpS1252;
  return _block_2171;
}

int32_t _M0MPB6Hasher8finalize(struct _M0TPB6Hasher* _M0L4selfS263) {
  uint32_t _M0L6_2atmpS1251;
  #line 435 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  #line 436 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0L6_2atmpS1251 = _M0MPB6Hasher9avalanche(_M0L4selfS263);
  return *(int32_t*)&_M0L6_2atmpS1251;
}

uint32_t _M0MPB6Hasher9avalanche(struct _M0TPB6Hasher* _M0L4selfS262) {
  uint32_t _M0Lm3accS261;
  uint32_t _M0L6_2atmpS1240;
  uint32_t _M0L6_2atmpS1242;
  uint32_t _M0L6_2atmpS1241;
  uint32_t _M0L6_2atmpS1243;
  uint32_t _M0L6_2atmpS1244;
  uint32_t _M0L6_2atmpS1246;
  uint32_t _M0L6_2atmpS1245;
  uint32_t _M0L6_2atmpS1247;
  uint32_t _M0L6_2atmpS1248;
  uint32_t _M0L6_2atmpS1250;
  uint32_t _M0L6_2atmpS1249;
  #line 440 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0Lm3accS261 = _M0L4selfS262->$0;
  moonbit_decref(_M0L4selfS262);
  _M0L6_2atmpS1240 = _M0Lm3accS261;
  _M0L6_2atmpS1242 = _M0Lm3accS261;
  _M0L6_2atmpS1241 = _M0L6_2atmpS1242 >> 15;
  _M0Lm3accS261 = _M0L6_2atmpS1240 ^ _M0L6_2atmpS1241;
  _M0L6_2atmpS1243 = _M0Lm3accS261;
  _M0Lm3accS261 = _M0L6_2atmpS1243 * 2246822519u;
  _M0L6_2atmpS1244 = _M0Lm3accS261;
  _M0L6_2atmpS1246 = _M0Lm3accS261;
  _M0L6_2atmpS1245 = _M0L6_2atmpS1246 >> 13;
  _M0Lm3accS261 = _M0L6_2atmpS1244 ^ _M0L6_2atmpS1245;
  _M0L6_2atmpS1247 = _M0Lm3accS261;
  _M0Lm3accS261 = _M0L6_2atmpS1247 * 3266489917u;
  _M0L6_2atmpS1248 = _M0Lm3accS261;
  _M0L6_2atmpS1250 = _M0Lm3accS261;
  _M0L6_2atmpS1249 = _M0L6_2atmpS1250 >> 16;
  _M0Lm3accS261 = _M0L6_2atmpS1248 ^ _M0L6_2atmpS1249;
  return _M0Lm3accS261;
}

int32_t _M0IP016_24default__implPB2Eq10not__equalGsE(
  moonbit_string_t _M0L1xS259,
  moonbit_string_t _M0L1yS260
) {
  int32_t _M0L6_2atmpS1239;
  #line 23 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  #line 24 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0L6_2atmpS1239 = moonbit_val_array_equal(_M0L1xS259, _M0L1yS260);
  moonbit_decref(_M0L1yS260);
  moonbit_decref(_M0L1xS259);
  return !_M0L6_2atmpS1239;
}

int32_t _M0MPB6Hasher7combineGiE(
  struct _M0TPB6Hasher* _M0L4selfS256,
  int32_t _M0L5valueS255
) {
  #line 120 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  #line 121 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0IPC13int3IntPB4Hash13hash__combine(_M0L5valueS255, _M0L4selfS256);
  return 0;
}

int32_t _M0MPB6Hasher7combineGsE(
  struct _M0TPB6Hasher* _M0L4selfS258,
  moonbit_string_t _M0L5valueS257
) {
  #line 120 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  #line 121 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0IPC16string6StringPB4Hash13hash__combine(_M0L5valueS257, _M0L4selfS258);
  return 0;
}

int32_t _M0MPB6Hasher12combine__int(
  struct _M0TPB6Hasher* _M0L4selfS253,
  int32_t _M0L5valueS254
) {
  uint32_t _M0L6_2atmpS1238;
  #line 187 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0L6_2atmpS1238 = *(uint32_t*)&_M0L5valueS254;
  #line 188 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0MPB6Hasher13combine__uint(_M0L4selfS253, _M0L6_2atmpS1238);
  return 0;
}

struct moonbit_result_0 _M0FPB15inspect_2einner(
  struct _M0TPB4Show _M0L3objS243,
  moonbit_string_t _M0L7contentS244,
  moonbit_string_t _M0L3locS246,
  struct _M0TPB5ArrayGORPB9SourceLocE* _M0L9args__locS248
) {
  moonbit_string_t _M0L6actualS242;
  #line 184 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  #line 191 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  _M0L6actualS242 = _M0L3objS243.$0->$method_1(_M0L3objS243.$1);
  moonbit_incref(_M0L7contentS244);
  moonbit_incref(_M0L6actualS242);
  #line 192 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  if (
    _M0IP016_24default__implPB2Eq10not__equalGsE(_M0L6actualS242, _M0L7contentS244)
  ) {
    moonbit_string_t _M0L3locS245;
    moonbit_string_t _M0L9args__locS247;
    moonbit_string_t _M0L15expect__escapedS249;
    moonbit_string_t _M0L15actual__escapedS250;
    moonbit_string_t _M0L6_2atmpS1236;
    moonbit_string_t _M0L6_2atmpS1235;
    moonbit_string_t _M0L6_2atmpS1234;
    moonbit_string_t _M0L14expect__base64S251;
    moonbit_string_t _M0L6_2atmpS1233;
    moonbit_string_t _M0L6_2atmpS1232;
    moonbit_string_t _M0L6_2atmpS1231;
    moonbit_string_t _M0L14actual__base64S252;
    moonbit_string_t _M0L6_2atmpS1230;
    moonbit_string_t _M0L6_2atmpS1229;
    moonbit_string_t _M0L6_2atmpS1227;
    moonbit_string_t _M0L6_2atmpS1228;
    moonbit_string_t _M0L6_2atmpS1226;
    moonbit_string_t _M0L6_2atmpS1224;
    moonbit_string_t _M0L6_2atmpS1225;
    moonbit_string_t _M0L6_2atmpS1223;
    moonbit_string_t _M0L6_2atmpS1221;
    moonbit_string_t _M0L6_2atmpS1222;
    moonbit_string_t _M0L6_2atmpS1220;
    moonbit_string_t _M0L6_2atmpS1218;
    moonbit_string_t _M0L6_2atmpS1219;
    moonbit_string_t _M0L6_2atmpS1217;
    moonbit_string_t _M0L6_2atmpS1215;
    moonbit_string_t _M0L6_2atmpS1216;
    moonbit_string_t _M0L6_2atmpS1214;
    moonbit_string_t _M0L6_2atmpS1213;
    void* _M0L58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectErrorS1212;
    struct moonbit_result_0 _result_2172;
    #line 193 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L3locS245 = _M0MPB9SourceLoc16to__json__string(_M0L3locS246);
    #line 194 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L9args__locS247 = _M0MPB7ArgsLoc8to__json(_M0L9args__locS248);
    moonbit_incref(_M0L7contentS244);
    #line 195 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L15expect__escapedS249
    = _M0MPC16string6String14escape_2einner(_M0L7contentS244, 1);
    moonbit_incref(_M0L6actualS242);
    #line 196 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L15actual__escapedS250
    = _M0MPC16string6String14escape_2einner(_M0L6actualS242, 1);
    #line 197 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1236
    = _M0FPB33base64__encode__string__codepoint(_M0L7contentS244);
    #line 197 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1235
    = _M0IPC16string6StringPB4Show10to__string(_M0L6_2atmpS1236);
    #line 197 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1234
    = moonbit_add_string((moonbit_string_t)moonbit_string_literal_53.data, _M0L6_2atmpS1235);
    moonbit_decref(_M0L6_2atmpS1235);
    #line 197 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L14expect__base64S251
    = moonbit_add_string(_M0L6_2atmpS1234, (moonbit_string_t)moonbit_string_literal_53.data);
    moonbit_decref(_M0L6_2atmpS1234);
    #line 198 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1233
    = _M0FPB33base64__encode__string__codepoint(_M0L6actualS242);
    #line 198 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1232
    = _M0IPC16string6StringPB4Show10to__string(_M0L6_2atmpS1233);
    #line 198 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1231
    = moonbit_add_string((moonbit_string_t)moonbit_string_literal_53.data, _M0L6_2atmpS1232);
    moonbit_decref(_M0L6_2atmpS1232);
    #line 198 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L14actual__base64S252
    = moonbit_add_string(_M0L6_2atmpS1231, (moonbit_string_t)moonbit_string_literal_53.data);
    moonbit_decref(_M0L6_2atmpS1231);
    #line 200 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1230 = _M0IPC16string6StringPB4Show10to__string(_M0L3locS245);
    #line 199 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1229
    = moonbit_add_string((moonbit_string_t)moonbit_string_literal_54.data, _M0L6_2atmpS1230);
    moonbit_decref(_M0L6_2atmpS1230);
    #line 199 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1227
    = moonbit_add_string(_M0L6_2atmpS1229, (moonbit_string_t)moonbit_string_literal_55.data);
    moonbit_decref(_M0L6_2atmpS1229);
    #line 200 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1228
    = _M0IPC16string6StringPB4Show10to__string(_M0L9args__locS247);
    #line 199 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1226 = moonbit_add_string(_M0L6_2atmpS1227, _M0L6_2atmpS1228);
    moonbit_decref(_M0L6_2atmpS1228);
    moonbit_decref(_M0L6_2atmpS1227);
    #line 199 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1224
    = moonbit_add_string(_M0L6_2atmpS1226, (moonbit_string_t)moonbit_string_literal_56.data);
    moonbit_decref(_M0L6_2atmpS1226);
    #line 200 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1225
    = _M0IPC16string6StringPB4Show10to__string(_M0L15expect__escapedS249);
    #line 199 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1223 = moonbit_add_string(_M0L6_2atmpS1224, _M0L6_2atmpS1225);
    moonbit_decref(_M0L6_2atmpS1225);
    moonbit_decref(_M0L6_2atmpS1224);
    #line 199 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1221
    = moonbit_add_string(_M0L6_2atmpS1223, (moonbit_string_t)moonbit_string_literal_57.data);
    moonbit_decref(_M0L6_2atmpS1223);
    #line 200 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1222
    = _M0IPC16string6StringPB4Show10to__string(_M0L15actual__escapedS250);
    #line 199 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1220 = moonbit_add_string(_M0L6_2atmpS1221, _M0L6_2atmpS1222);
    moonbit_decref(_M0L6_2atmpS1222);
    moonbit_decref(_M0L6_2atmpS1221);
    #line 199 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1218
    = moonbit_add_string(_M0L6_2atmpS1220, (moonbit_string_t)moonbit_string_literal_58.data);
    moonbit_decref(_M0L6_2atmpS1220);
    #line 200 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1219
    = _M0IPC16string6StringPB4Show10to__string(_M0L14expect__base64S251);
    #line 199 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1217 = moonbit_add_string(_M0L6_2atmpS1218, _M0L6_2atmpS1219);
    moonbit_decref(_M0L6_2atmpS1219);
    moonbit_decref(_M0L6_2atmpS1218);
    #line 199 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1215
    = moonbit_add_string(_M0L6_2atmpS1217, (moonbit_string_t)moonbit_string_literal_59.data);
    moonbit_decref(_M0L6_2atmpS1217);
    #line 200 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1216
    = _M0IPC16string6StringPB4Show10to__string(_M0L14actual__base64S252);
    #line 199 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1214 = moonbit_add_string(_M0L6_2atmpS1215, _M0L6_2atmpS1216);
    moonbit_decref(_M0L6_2atmpS1216);
    moonbit_decref(_M0L6_2atmpS1215);
    #line 199 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS1213
    = moonbit_add_string(_M0L6_2atmpS1214, (moonbit_string_t)moonbit_string_literal_7.data);
    moonbit_decref(_M0L6_2atmpS1214);
    _M0L58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectErrorS1212
    = (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectError));
    Moonbit_object_header(_M0L58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectErrorS1212)->meta
    = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectError, $0) >> 2, 1, 1);
    ((struct _M0DTPC15error5Error58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectError*)_M0L58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectErrorS1212)->$0
    = _M0L6_2atmpS1213;
    _result_2172.tag = 0;
    _result_2172.data.err
    = _M0L58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectErrorS1212;
    return _result_2172;
  } else {
    int32_t _M0L6_2atmpS1237;
    struct moonbit_result_0 _result_2173;
    moonbit_decref(_M0L9args__locS248);
    moonbit_decref(_M0L3locS246);
    moonbit_decref(_M0L7contentS244);
    moonbit_decref(_M0L6actualS242);
    _M0L6_2atmpS1237 = 0;
    _result_2173.tag = 1;
    _result_2173.data.ok = _M0L6_2atmpS1237;
    return _result_2173;
  }
}

moonbit_string_t _M0MPB7ArgsLoc8to__json(
  struct _M0TPB5ArrayGORPB9SourceLocE* _M0L4selfS235
) {
  struct _M0TPB13StringBuilder* _M0L3bufS233;
  struct _M0TPB5ArrayGORPB9SourceLocE* _M0L7_2aselfS234;
  int32_t _M0L7_2abindS236;
  int32_t _M0L1iS237;
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  #line 119 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L3bufS233 = _M0MPB13StringBuilder11new_2einner(10);
  _M0L7_2aselfS234 = _M0L4selfS235;
  moonbit_incref(_M0L3bufS233);
  #line 121 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0IPB13StringBuilderPB6Logger11write__char(_M0L3bufS233, 91);
  _M0L7_2abindS236 = _M0L7_2aselfS234->$1;
  _M0L1iS237 = 0;
  while (1) {
    if (_M0L1iS237 < _M0L7_2abindS236) {
      moonbit_string_t* _M0L3bufS1211 = _M0L7_2aselfS234->$0;
      moonbit_string_t _M0L4itemS238 =
        (moonbit_string_t)_M0L3bufS1211[_M0L1iS237];
      int32_t _M0L6_2atmpS1210;
      if (_M0L1iS237 != 0) {
        if (_M0L4itemS238) {
          moonbit_incref(_M0L4itemS238);
        }
        moonbit_incref(_M0L3bufS233);
        #line 124 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
        _M0IPB13StringBuilderPB6Logger13write__string(_M0L3bufS233, (moonbit_string_t)moonbit_string_literal_60.data);
      } else if (_M0L4itemS238) {
        moonbit_incref(_M0L4itemS238);
      }
      if (_M0L4itemS238 == 0) {
        if (_M0L4itemS238) {
          moonbit_decref(_M0L4itemS238);
        }
        moonbit_incref(_M0L3bufS233);
        #line 127 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
        _M0IPB13StringBuilderPB6Logger13write__string(_M0L3bufS233, (moonbit_string_t)moonbit_string_literal_61.data);
      } else {
        moonbit_string_t _M0L7_2aSomeS239 = _M0L4itemS238;
        moonbit_string_t _M0L6_2alocS240 = _M0L7_2aSomeS239;
        moonbit_string_t _M0L6_2atmpS1209;
        #line 128 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
        _M0L6_2atmpS1209
        = _M0MPB9SourceLoc16to__json__string(_M0L6_2alocS240);
        moonbit_incref(_M0L3bufS233);
        #line 128 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
        _M0IPB13StringBuilderPB6Logger13write__string(_M0L3bufS233, _M0L6_2atmpS1209);
      }
      _M0L6_2atmpS1210 = _M0L1iS237 + 1;
      _M0L1iS237 = _M0L6_2atmpS1210;
      continue;
    } else {
      moonbit_decref(_M0L7_2aselfS234);
    }
    break;
  }
  moonbit_incref(_M0L3bufS233);
  #line 131 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0IPB13StringBuilderPB6Logger11write__char(_M0L3bufS233, 93);
  #line 132 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  return _M0MPB13StringBuilder10to__string(_M0L3bufS233);
}

moonbit_string_t _M0MPB9SourceLoc16to__json__string(
  moonbit_string_t _M0L4selfS232
) {
  moonbit_string_t _M0L6_2atmpS1208;
  struct _M0TPB13SourceLocRepr* _M0L6_2atmpS1207;
  #line 95 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L6_2atmpS1208 = _M0L4selfS232;
  #line 96 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L6_2atmpS1207 = _M0MPB13SourceLocRepr5parse(_M0L6_2atmpS1208);
  #line 96 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  return _M0MPB13SourceLocRepr16to__json__string(_M0L6_2atmpS1207);
}

moonbit_string_t _M0MPB13SourceLocRepr16to__json__string(
  struct _M0TPB13SourceLocRepr* _M0L4selfS231
) {
  struct _M0TPB13StringBuilder* _M0L2sbS230;
  struct _M0TPC16string10StringView _M0L8filenameS1193;
  struct _M0TPC16string10StringView _M0L11start__lineS1196;
  moonbit_string_t _M0L6_2atmpS1195;
  moonbit_string_t _M0L6_2atmpS1194;
  struct _M0TPC16string10StringView _M0L13start__columnS1199;
  moonbit_string_t _M0L6_2atmpS1198;
  moonbit_string_t _M0L6_2atmpS1197;
  struct _M0TPC16string10StringView _M0L9end__lineS1202;
  moonbit_string_t _M0L6_2atmpS1201;
  moonbit_string_t _M0L6_2atmpS1200;
  struct _M0TPC16string10StringView _M0L8_2afieldS1962;
  int32_t _M0L6_2acntS2047;
  struct _M0TPC16string10StringView _M0L11end__columnS1206;
  moonbit_string_t _M0L6_2atmpS1205;
  moonbit_string_t _M0L6_2atmpS1204;
  moonbit_string_t _M0L6_2atmpS1203;
  #line 82 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  #line 83 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L2sbS230 = _M0MPB13StringBuilder11new_2einner(0);
  moonbit_incref(_M0L2sbS230);
  #line 84 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0IPB13StringBuilderPB6Logger13write__string(_M0L2sbS230, (moonbit_string_t)moonbit_string_literal_62.data);
  _M0L8filenameS1193
  = (struct _M0TPC16string10StringView){
    _M0L4selfS231->$0_1, _M0L4selfS231->$0_2, _M0L4selfS231->$0_0
  };
  moonbit_incref(_M0L8filenameS1193.$0);
  moonbit_incref(_M0L2sbS230);
  #line 85 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0MPB13StringBuilder13write__objectGRPC16string10StringViewE(_M0L2sbS230, _M0L8filenameS1193);
  _M0L11start__lineS1196
  = (struct _M0TPC16string10StringView){
    _M0L4selfS231->$1_1, _M0L4selfS231->$1_2, _M0L4selfS231->$1_0
  };
  moonbit_incref(_M0L11start__lineS1196.$0);
  #line 86 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L6_2atmpS1195
  = _M0IPC16string10StringViewPB4Show10to__string(_M0L11start__lineS1196);
  #line 86 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L6_2atmpS1194
  = moonbit_add_string((moonbit_string_t)moonbit_string_literal_63.data, _M0L6_2atmpS1195);
  moonbit_decref(_M0L6_2atmpS1195);
  moonbit_incref(_M0L2sbS230);
  #line 86 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0IPB13StringBuilderPB6Logger13write__string(_M0L2sbS230, _M0L6_2atmpS1194);
  _M0L13start__columnS1199
  = (struct _M0TPC16string10StringView){
    _M0L4selfS231->$2_1, _M0L4selfS231->$2_2, _M0L4selfS231->$2_0
  };
  moonbit_incref(_M0L13start__columnS1199.$0);
  #line 87 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L6_2atmpS1198
  = _M0IPC16string10StringViewPB4Show10to__string(_M0L13start__columnS1199);
  #line 87 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L6_2atmpS1197
  = moonbit_add_string((moonbit_string_t)moonbit_string_literal_64.data, _M0L6_2atmpS1198);
  moonbit_decref(_M0L6_2atmpS1198);
  moonbit_incref(_M0L2sbS230);
  #line 87 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0IPB13StringBuilderPB6Logger13write__string(_M0L2sbS230, _M0L6_2atmpS1197);
  _M0L9end__lineS1202
  = (struct _M0TPC16string10StringView){
    _M0L4selfS231->$3_1, _M0L4selfS231->$3_2, _M0L4selfS231->$3_0
  };
  moonbit_incref(_M0L9end__lineS1202.$0);
  #line 88 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L6_2atmpS1201
  = _M0IPC16string10StringViewPB4Show10to__string(_M0L9end__lineS1202);
  #line 88 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L6_2atmpS1200
  = moonbit_add_string((moonbit_string_t)moonbit_string_literal_65.data, _M0L6_2atmpS1201);
  moonbit_decref(_M0L6_2atmpS1201);
  moonbit_incref(_M0L2sbS230);
  #line 88 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0IPB13StringBuilderPB6Logger13write__string(_M0L2sbS230, _M0L6_2atmpS1200);
  _M0L8_2afieldS1962
  = (struct _M0TPC16string10StringView){
    _M0L4selfS231->$4_1, _M0L4selfS231->$4_2, _M0L4selfS231->$4_0
  };
  _M0L6_2acntS2047 = Moonbit_object_header(_M0L4selfS231)->rc;
  if (_M0L6_2acntS2047 > 1) {
    int32_t _M0L11_2anew__cntS2052 = _M0L6_2acntS2047 - 1;
    Moonbit_object_header(_M0L4selfS231)->rc = _M0L11_2anew__cntS2052;
    moonbit_incref(_M0L8_2afieldS1962.$0);
  } else if (_M0L6_2acntS2047 == 1) {
    struct _M0TPC16string10StringView _M0L8_2afieldS2051 =
      (struct _M0TPC16string10StringView){_M0L4selfS231->$3_1,
                                            _M0L4selfS231->$3_2,
                                            _M0L4selfS231->$3_0};
    struct _M0TPC16string10StringView _M0L8_2afieldS2050;
    struct _M0TPC16string10StringView _M0L8_2afieldS2049;
    struct _M0TPC16string10StringView _M0L8_2afieldS2048;
    moonbit_decref(_M0L8_2afieldS2051.$0);
    _M0L8_2afieldS2050
    = (struct _M0TPC16string10StringView){
      _M0L4selfS231->$2_1, _M0L4selfS231->$2_2, _M0L4selfS231->$2_0
    };
    moonbit_decref(_M0L8_2afieldS2050.$0);
    _M0L8_2afieldS2049
    = (struct _M0TPC16string10StringView){
      _M0L4selfS231->$1_1, _M0L4selfS231->$1_2, _M0L4selfS231->$1_0
    };
    moonbit_decref(_M0L8_2afieldS2049.$0);
    _M0L8_2afieldS2048
    = (struct _M0TPC16string10StringView){
      _M0L4selfS231->$0_1, _M0L4selfS231->$0_2, _M0L4selfS231->$0_0
    };
    moonbit_decref(_M0L8_2afieldS2048.$0);
    #line 89 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
    moonbit_free(_M0L4selfS231);
  }
  _M0L11end__columnS1206 = _M0L8_2afieldS1962;
  #line 89 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L6_2atmpS1205
  = _M0IPC16string10StringViewPB4Show10to__string(_M0L11end__columnS1206);
  #line 89 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L6_2atmpS1204
  = moonbit_add_string((moonbit_string_t)moonbit_string_literal_66.data, _M0L6_2atmpS1205);
  moonbit_decref(_M0L6_2atmpS1205);
  #line 89 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L6_2atmpS1203
  = moonbit_add_string(_M0L6_2atmpS1204, (moonbit_string_t)moonbit_string_literal_7.data);
  moonbit_decref(_M0L6_2atmpS1204);
  moonbit_incref(_M0L2sbS230);
  #line 89 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0IPB13StringBuilderPB6Logger13write__string(_M0L2sbS230, _M0L6_2atmpS1203);
  #line 90 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  return _M0MPB13StringBuilder10to__string(_M0L2sbS230);
}

int32_t _M0IPB13StringBuilderPB6Logger13write__string(
  struct _M0TPB13StringBuilder* _M0L4selfS229,
  moonbit_string_t _M0L3strS228
) {
  int32_t _M0L8str__lenS227;
  int32_t _M0L3lenS1188;
  int32_t _M0L6_2atmpS1187;
  uint16_t* _M0L4dataS1189;
  int32_t _M0L3lenS1190;
  int32_t _M0L3lenS1192;
  int32_t _M0L6_2atmpS1191;
  #line 81 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L8str__lenS227 = Moonbit_array_length(_M0L3strS228);
  _M0L3lenS1188 = _M0L4selfS229->$1;
  _M0L6_2atmpS1187 = _M0L3lenS1188 + _M0L8str__lenS227;
  moonbit_incref(_M0L4selfS229);
  #line 83 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0MPB13StringBuilder19grow__if__necessary(_M0L4selfS229, _M0L6_2atmpS1187);
  _M0L4dataS1189 = _M0L4selfS229->$0;
  _M0L3lenS1190 = _M0L4selfS229->$1;
  moonbit_incref(_M0L4dataS1189);
  #line 84 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0MPC15array10FixedArray26unsafe__blit__from__string(_M0L4dataS1189, _M0L3lenS1190, _M0L3strS228, 0, _M0L8str__lenS227);
  _M0L3lenS1192 = _M0L4selfS229->$1;
  _M0L6_2atmpS1191 = _M0L3lenS1192 + _M0L8str__lenS227;
  _M0L4selfS229->$1 = _M0L6_2atmpS1191;
  moonbit_decref(_M0L4selfS229);
  return 0;
}

int32_t _M0MPC15array10FixedArray26unsafe__blit__from__string(
  uint16_t* _M0L4selfS223,
  int32_t _M0L11dst__offsetS226,
  moonbit_string_t _M0L3strS224,
  int32_t _M0L11str__offsetS219,
  int32_t _M0L3lenS220
) {
  int32_t _M0L16end__str__offsetS218;
  int32_t _M0L1iS221;
  int32_t _M0L1jS222;
  #line 66 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L16end__str__offsetS218 = _M0L11str__offsetS219 + _M0L3lenS220;
  _M0L1iS221 = _M0L11str__offsetS219;
  _M0L1jS222 = _M0L11dst__offsetS226;
  while (1) {
    if (_M0L1iS221 < _M0L16end__str__offsetS218) {
      int32_t _M0L6_2atmpS1184 = _M0L3strS224[_M0L1iS221];
      int32_t _M0L6_2atmpS1185;
      int32_t _M0L6_2atmpS1186;
      if (
        _M0L1jS222 < 0 || _M0L1jS222 >= Moonbit_array_length(_M0L4selfS223)
      ) {
        #line 75 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
        moonbit_panic();
      }
      _M0L4selfS223[_M0L1jS222] = _M0L6_2atmpS1184;
      _M0L6_2atmpS1185 = _M0L1iS221 + 1;
      _M0L6_2atmpS1186 = _M0L1jS222 + 1;
      _M0L1iS221 = _M0L6_2atmpS1185;
      _M0L1jS222 = _M0L6_2atmpS1186;
      continue;
    } else {
      moonbit_decref(_M0L3strS224);
      moonbit_decref(_M0L4selfS223);
    }
    break;
  }
  return 0;
}

int32_t _M0MPB13StringBuilder13write__objectGRPC16string10StringViewE(
  struct _M0TPB13StringBuilder* _M0L4selfS217,
  struct _M0TPC16string10StringView _M0L3objS216
) {
  struct _M0TPB6Logger _M0L6_2atmpS1183;
  #line 17 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder.mbt"
  _M0L6_2atmpS1183
  = (struct _M0TPB6Logger){
    _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id,
      _M0L4selfS217
  };
  #line 21 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder.mbt"
  _M0IPC16string10StringViewPB4Show6output(_M0L3objS216, _M0L6_2atmpS1183);
  return 0;
}

struct _M0TPB13SourceLocRepr* _M0MPB13SourceLocRepr5parse(
  moonbit_string_t _M0L4reprS161
) {
  int32_t _M0L6_2atmpS1182;
  struct _M0TPC16string10StringView _M0L7_2abindS160;
  moonbit_string_t _M0L7_2adataS162;
  int32_t _M0L8_2astartS163;
  int32_t _M0L6_2atmpS1181;
  int32_t _M0L6_2aendS164;
  int32_t _M0Lm9_2acursorS165;
  int32_t _M0Lm13accept__stateS166;
  int32_t _M0Lm10match__endS167;
  int32_t _M0Lm20match__tag__saver__0S168;
  int32_t _M0Lm20match__tag__saver__1S169;
  int32_t _M0Lm20match__tag__saver__2S170;
  int32_t _M0Lm20match__tag__saver__3S171;
  int32_t _M0Lm20match__tag__saver__4S172;
  int32_t _M0Lm6tag__0S173;
  int32_t _M0Lm9tag__0__1S174;
  int32_t _M0Lm9tag__0__2S175;
  int32_t _M0Lm6tag__2S176;
  int32_t _M0Lm6tag__1S177;
  int32_t _M0Lm9tag__1__1S178;
  int32_t _M0Lm6tag__4S179;
  int32_t _M0Lm6tag__3S180;
  int32_t _M0L6_2atmpS1140;
  #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L6_2atmpS1182 = Moonbit_array_length(_M0L4reprS161);
  _M0L7_2abindS160
  = (struct _M0TPC16string10StringView){
    0, _M0L6_2atmpS1182, _M0L4reprS161
  };
  moonbit_incref(_M0L7_2abindS160.$0);
  #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L7_2adataS162 = _M0MPC16string10StringView4data(_M0L7_2abindS160);
  moonbit_incref(_M0L7_2abindS160.$0);
  #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L8_2astartS163
  = _M0MPC16string10StringView13start__offset(_M0L7_2abindS160);
  #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
  _M0L6_2atmpS1181 = _M0MPC16string10StringView6length(_M0L7_2abindS160);
  _M0L6_2aendS164 = _M0L8_2astartS163 + _M0L6_2atmpS1181;
  _M0Lm9_2acursorS165 = _M0L8_2astartS163;
  _M0Lm13accept__stateS166 = -1;
  _M0Lm10match__endS167 = -1;
  _M0Lm20match__tag__saver__0S168 = -1;
  _M0Lm20match__tag__saver__1S169 = -1;
  _M0Lm20match__tag__saver__2S170 = -1;
  _M0Lm20match__tag__saver__3S171 = -1;
  _M0Lm20match__tag__saver__4S172 = -1;
  _M0Lm6tag__0S173 = -1;
  _M0Lm9tag__0__1S174 = -1;
  _M0Lm9tag__0__2S175 = -1;
  _M0Lm6tag__2S176 = -1;
  _M0Lm6tag__1S177 = -1;
  _M0Lm9tag__1__1S178 = -1;
  _M0Lm6tag__4S179 = -1;
  _M0Lm6tag__3S180 = -1;
  _M0L6_2atmpS1140 = _M0Lm9_2acursorS165;
  if (_M0L6_2atmpS1140 < _M0L6_2aendS164) {
    int32_t _M0L6_2atmpS1141 = _M0Lm9_2acursorS165;
    int32_t _M0L12dispatch__15S188;
    _M0Lm9_2acursorS165 = _M0L6_2atmpS1141 + 1;
    _M0L12dispatch__15S188 = 0;
    loop__label__15_191:;
    while (1) {
      int32_t _M0L6_2atmpS1145;
      int32_t _M0L6_2atmpS1142;
      switch (_M0L12dispatch__15S188) {
        case 6: {
          int32_t _M0L6_2atmpS1148;
          _M0Lm6tag__0S173 = _M0Lm9_2acursorS165;
          _M0L6_2atmpS1148 = _M0Lm9_2acursorS165;
          if (_M0L6_2atmpS1148 < _M0L6_2aendS164) {
            int32_t _M0L6_2atmpS1150 = _M0Lm9_2acursorS165;
            int32_t _M0L10next__charS196;
            int32_t _M0L6_2atmpS1149;
            moonbit_incref(_M0L7_2adataS162);
            #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
            _M0L10next__charS196
            = _M0MPC16string6String20unsafe__charcode__at(_M0L7_2adataS162, _M0L6_2atmpS1150);
            _M0L6_2atmpS1149 = _M0Lm9_2acursorS165;
            _M0Lm9_2acursorS165 = _M0L6_2atmpS1149 + 1;
            if (_M0L10next__charS196 == 58) {
              _M0L12dispatch__15S188 = 1;
              goto loop__label__15_191;
            } else {
              _M0L12dispatch__15S188 = 6;
              goto loop__label__15_191;
            }
          } else {
            goto join_193;
          }
          break;
        }
        
        case 3: {
          int32_t _M0L6_2atmpS1151;
          _M0Lm9tag__0__2S175 = _M0Lm9tag__0__1S174;
          _M0Lm9tag__0__1S174 = _M0Lm6tag__0S173;
          _M0Lm6tag__0S173 = _M0Lm9_2acursorS165;
          _M0L6_2atmpS1151 = _M0Lm9_2acursorS165;
          if (_M0L6_2atmpS1151 < _M0L6_2aendS164) {
            int32_t _M0L6_2atmpS1156 = _M0Lm9_2acursorS165;
            int32_t _M0L10next__charS198;
            int32_t _M0L6_2atmpS1152;
            moonbit_incref(_M0L7_2adataS162);
            #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
            _M0L10next__charS198
            = _M0MPC16string6String20unsafe__charcode__at(_M0L7_2adataS162, _M0L6_2atmpS1156);
            _M0L6_2atmpS1152 = _M0Lm9_2acursorS165;
            _M0Lm9_2acursorS165 = _M0L6_2atmpS1152 + 1;
            if (_M0L10next__charS198 < 58) {
              if (_M0L10next__charS198 < 48) {
                goto join_197;
              } else {
                int32_t _M0L6_2atmpS1153;
                _M0Lm6tag__0S173 = _M0Lm9_2acursorS165;
                _M0Lm9tag__1__1S178 = _M0Lm6tag__1S177;
                _M0Lm6tag__1S177 = _M0Lm9_2acursorS165;
                _M0Lm6tag__2S176 = _M0Lm9_2acursorS165;
                _M0L6_2atmpS1153 = _M0Lm9_2acursorS165;
                if (_M0L6_2atmpS1153 < _M0L6_2aendS164) {
                  int32_t _M0L6_2atmpS1155 = _M0Lm9_2acursorS165;
                  int32_t _M0L10next__charS200;
                  int32_t _M0L6_2atmpS1154;
                  moonbit_incref(_M0L7_2adataS162);
                  #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
                  _M0L10next__charS200
                  = _M0MPC16string6String20unsafe__charcode__at(_M0L7_2adataS162, _M0L6_2atmpS1155);
                  _M0L6_2atmpS1154 = _M0Lm9_2acursorS165;
                  _M0Lm9_2acursorS165 = _M0L6_2atmpS1154 + 1;
                  if (_M0L10next__charS200 < 48) {
                    if (_M0L10next__charS200 == 45) {
                      goto join_189;
                    } else {
                      goto join_199;
                    }
                  } else if (_M0L10next__charS200 > 57) {
                    if (_M0L10next__charS200 < 59) {
                      _M0L12dispatch__15S188 = 3;
                      goto loop__label__15_191;
                    } else {
                      goto join_199;
                    }
                  } else {
                    _M0L12dispatch__15S188 = 7;
                    goto loop__label__15_191;
                  }
                  join_199:;
                  _M0L12dispatch__15S188 = 0;
                  goto loop__label__15_191;
                } else {
                  goto join_181;
                }
              }
            } else if (_M0L10next__charS198 > 58) {
              goto join_197;
            } else {
              _M0L12dispatch__15S188 = 1;
              goto loop__label__15_191;
            }
            join_197:;
            _M0L12dispatch__15S188 = 0;
            goto loop__label__15_191;
          } else {
            goto join_181;
          }
          break;
        }
        
        case 7: {
          int32_t _M0L6_2atmpS1157;
          _M0Lm6tag__0S173 = _M0Lm9_2acursorS165;
          _M0Lm6tag__1S177 = _M0Lm9_2acursorS165;
          _M0Lm6tag__2S176 = _M0Lm9_2acursorS165;
          _M0L6_2atmpS1157 = _M0Lm9_2acursorS165;
          if (_M0L6_2atmpS1157 < _M0L6_2aendS164) {
            int32_t _M0L6_2atmpS1159 = _M0Lm9_2acursorS165;
            int32_t _M0L10next__charS202;
            int32_t _M0L6_2atmpS1158;
            moonbit_incref(_M0L7_2adataS162);
            #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
            _M0L10next__charS202
            = _M0MPC16string6String20unsafe__charcode__at(_M0L7_2adataS162, _M0L6_2atmpS1159);
            _M0L6_2atmpS1158 = _M0Lm9_2acursorS165;
            _M0Lm9_2acursorS165 = _M0L6_2atmpS1158 + 1;
            if (_M0L10next__charS202 < 48) {
              if (_M0L10next__charS202 == 45) {
                goto join_189;
              } else {
                goto join_201;
              }
            } else if (_M0L10next__charS202 > 57) {
              if (_M0L10next__charS202 < 59) {
                _M0L12dispatch__15S188 = 3;
                goto loop__label__15_191;
              } else {
                goto join_201;
              }
            } else {
              _M0L12dispatch__15S188 = 7;
              goto loop__label__15_191;
            }
            join_201:;
            _M0L12dispatch__15S188 = 0;
            goto loop__label__15_191;
          } else {
            goto join_181;
          }
          break;
        }
        
        case 5: {
          int32_t _M0L6_2atmpS1160;
          _M0Lm6tag__0S173 = _M0Lm9_2acursorS165;
          _M0Lm6tag__1S177 = _M0Lm9_2acursorS165;
          _M0Lm6tag__4S179 = _M0Lm9_2acursorS165;
          _M0L6_2atmpS1160 = _M0Lm9_2acursorS165;
          if (_M0L6_2atmpS1160 < _M0L6_2aendS164) {
            int32_t _M0L6_2atmpS1162 = _M0Lm9_2acursorS165;
            int32_t _M0L10next__charS204;
            int32_t _M0L6_2atmpS1161;
            moonbit_incref(_M0L7_2adataS162);
            #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
            _M0L10next__charS204
            = _M0MPC16string6String20unsafe__charcode__at(_M0L7_2adataS162, _M0L6_2atmpS1162);
            _M0L6_2atmpS1161 = _M0Lm9_2acursorS165;
            _M0Lm9_2acursorS165 = _M0L6_2atmpS1161 + 1;
            if (_M0L10next__charS204 < 59) {
              if (_M0L10next__charS204 < 48) {
                goto join_203;
              } else if (_M0L10next__charS204 > 57) {
                _M0L12dispatch__15S188 = 3;
                goto loop__label__15_191;
              } else {
                _M0L12dispatch__15S188 = 5;
                goto loop__label__15_191;
              }
            } else if (_M0L10next__charS204 > 63) {
              if (_M0L10next__charS204 < 65) {
                goto join_194;
              } else {
                goto join_203;
              }
            } else {
              goto join_203;
            }
            join_203:;
            _M0L12dispatch__15S188 = 0;
            goto loop__label__15_191;
          } else {
            goto join_181;
          }
          break;
        }
        
        case 1: {
          int32_t _M0L6_2atmpS1163;
          _M0Lm9tag__0__1S174 = _M0Lm6tag__0S173;
          _M0Lm6tag__0S173 = _M0Lm9_2acursorS165;
          _M0L6_2atmpS1163 = _M0Lm9_2acursorS165;
          if (_M0L6_2atmpS1163 < _M0L6_2aendS164) {
            int32_t _M0L6_2atmpS1165 = _M0Lm9_2acursorS165;
            int32_t _M0L10next__charS206;
            int32_t _M0L6_2atmpS1164;
            moonbit_incref(_M0L7_2adataS162);
            #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
            _M0L10next__charS206
            = _M0MPC16string6String20unsafe__charcode__at(_M0L7_2adataS162, _M0L6_2atmpS1165);
            _M0L6_2atmpS1164 = _M0Lm9_2acursorS165;
            _M0Lm9_2acursorS165 = _M0L6_2atmpS1164 + 1;
            if (_M0L10next__charS206 < 58) {
              if (_M0L10next__charS206 < 48) {
                goto join_205;
              } else {
                _M0L12dispatch__15S188 = 2;
                goto loop__label__15_191;
              }
            } else if (_M0L10next__charS206 > 58) {
              goto join_205;
            } else {
              _M0L12dispatch__15S188 = 1;
              goto loop__label__15_191;
            }
            join_205:;
            _M0L12dispatch__15S188 = 0;
            goto loop__label__15_191;
          } else {
            goto join_181;
          }
          break;
        }
        
        case 4: {
          int32_t _M0L6_2atmpS1166;
          _M0Lm6tag__0S173 = _M0Lm9_2acursorS165;
          _M0Lm6tag__3S180 = _M0Lm9_2acursorS165;
          _M0L6_2atmpS1166 = _M0Lm9_2acursorS165;
          if (_M0L6_2atmpS1166 < _M0L6_2aendS164) {
            int32_t _M0L6_2atmpS1174 = _M0Lm9_2acursorS165;
            int32_t _M0L10next__charS208;
            int32_t _M0L6_2atmpS1167;
            moonbit_incref(_M0L7_2adataS162);
            #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
            _M0L10next__charS208
            = _M0MPC16string6String20unsafe__charcode__at(_M0L7_2adataS162, _M0L6_2atmpS1174);
            _M0L6_2atmpS1167 = _M0Lm9_2acursorS165;
            _M0Lm9_2acursorS165 = _M0L6_2atmpS1167 + 1;
            if (_M0L10next__charS208 < 58) {
              if (_M0L10next__charS208 < 48) {
                goto join_207;
              } else {
                _M0L12dispatch__15S188 = 4;
                goto loop__label__15_191;
              }
            } else if (_M0L10next__charS208 > 58) {
              goto join_207;
            } else {
              int32_t _M0L6_2atmpS1168;
              _M0Lm9tag__0__2S175 = _M0Lm9tag__0__1S174;
              _M0Lm9tag__0__1S174 = _M0Lm6tag__0S173;
              _M0Lm6tag__0S173 = _M0Lm9_2acursorS165;
              _M0L6_2atmpS1168 = _M0Lm9_2acursorS165;
              if (_M0L6_2atmpS1168 < _M0L6_2aendS164) {
                int32_t _M0L6_2atmpS1173 = _M0Lm9_2acursorS165;
                int32_t _M0L10next__charS210;
                int32_t _M0L6_2atmpS1169;
                moonbit_incref(_M0L7_2adataS162);
                #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
                _M0L10next__charS210
                = _M0MPC16string6String20unsafe__charcode__at(_M0L7_2adataS162, _M0L6_2atmpS1173);
                _M0L6_2atmpS1169 = _M0Lm9_2acursorS165;
                _M0Lm9_2acursorS165 = _M0L6_2atmpS1169 + 1;
                if (_M0L10next__charS210 < 58) {
                  if (_M0L10next__charS210 < 48) {
                    goto join_209;
                  } else {
                    int32_t _M0L6_2atmpS1170;
                    _M0Lm6tag__0S173 = _M0Lm9_2acursorS165;
                    _M0Lm9tag__1__1S178 = _M0Lm6tag__1S177;
                    _M0Lm6tag__1S177 = _M0Lm9_2acursorS165;
                    _M0Lm6tag__4S179 = _M0Lm9_2acursorS165;
                    _M0L6_2atmpS1170 = _M0Lm9_2acursorS165;
                    if (_M0L6_2atmpS1170 < _M0L6_2aendS164) {
                      int32_t _M0L6_2atmpS1172 = _M0Lm9_2acursorS165;
                      int32_t _M0L10next__charS212;
                      int32_t _M0L6_2atmpS1171;
                      moonbit_incref(_M0L7_2adataS162);
                      #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
                      _M0L10next__charS212
                      = _M0MPC16string6String20unsafe__charcode__at(_M0L7_2adataS162, _M0L6_2atmpS1172);
                      _M0L6_2atmpS1171 = _M0Lm9_2acursorS165;
                      _M0Lm9_2acursorS165 = _M0L6_2atmpS1171 + 1;
                      if (_M0L10next__charS212 < 59) {
                        if (_M0L10next__charS212 < 48) {
                          goto join_211;
                        } else if (_M0L10next__charS212 > 57) {
                          _M0L12dispatch__15S188 = 3;
                          goto loop__label__15_191;
                        } else {
                          _M0L12dispatch__15S188 = 5;
                          goto loop__label__15_191;
                        }
                      } else if (_M0L10next__charS212 > 63) {
                        if (_M0L10next__charS212 < 65) {
                          goto join_194;
                        } else {
                          goto join_211;
                        }
                      } else {
                        goto join_211;
                      }
                      join_211:;
                      _M0L12dispatch__15S188 = 0;
                      goto loop__label__15_191;
                    } else {
                      goto join_181;
                    }
                  }
                } else if (_M0L10next__charS210 > 58) {
                  goto join_209;
                } else {
                  _M0L12dispatch__15S188 = 1;
                  goto loop__label__15_191;
                }
                join_209:;
                _M0L12dispatch__15S188 = 0;
                goto loop__label__15_191;
              } else {
                goto join_181;
              }
            }
            join_207:;
            _M0L12dispatch__15S188 = 0;
            goto loop__label__15_191;
          } else {
            goto join_181;
          }
          break;
        }
        
        case 2: {
          int32_t _M0L6_2atmpS1175;
          _M0Lm6tag__0S173 = _M0Lm9_2acursorS165;
          _M0Lm6tag__1S177 = _M0Lm9_2acursorS165;
          _M0L6_2atmpS1175 = _M0Lm9_2acursorS165;
          if (_M0L6_2atmpS1175 < _M0L6_2aendS164) {
            int32_t _M0L6_2atmpS1177 = _M0Lm9_2acursorS165;
            int32_t _M0L10next__charS214;
            int32_t _M0L6_2atmpS1176;
            moonbit_incref(_M0L7_2adataS162);
            #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
            _M0L10next__charS214
            = _M0MPC16string6String20unsafe__charcode__at(_M0L7_2adataS162, _M0L6_2atmpS1177);
            _M0L6_2atmpS1176 = _M0Lm9_2acursorS165;
            _M0Lm9_2acursorS165 = _M0L6_2atmpS1176 + 1;
            if (_M0L10next__charS214 < 58) {
              if (_M0L10next__charS214 < 48) {
                goto join_213;
              } else {
                _M0L12dispatch__15S188 = 2;
                goto loop__label__15_191;
              }
            } else if (_M0L10next__charS214 > 58) {
              goto join_213;
            } else {
              _M0L12dispatch__15S188 = 3;
              goto loop__label__15_191;
            }
            join_213:;
            _M0L12dispatch__15S188 = 0;
            goto loop__label__15_191;
          } else {
            goto join_181;
          }
          break;
        }
        
        case 0: {
          int32_t _M0L6_2atmpS1178;
          _M0Lm6tag__0S173 = _M0Lm9_2acursorS165;
          _M0L6_2atmpS1178 = _M0Lm9_2acursorS165;
          if (_M0L6_2atmpS1178 < _M0L6_2aendS164) {
            int32_t _M0L6_2atmpS1180 = _M0Lm9_2acursorS165;
            int32_t _M0L10next__charS215;
            int32_t _M0L6_2atmpS1179;
            moonbit_incref(_M0L7_2adataS162);
            #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
            _M0L10next__charS215
            = _M0MPC16string6String20unsafe__charcode__at(_M0L7_2adataS162, _M0L6_2atmpS1180);
            _M0L6_2atmpS1179 = _M0Lm9_2acursorS165;
            _M0Lm9_2acursorS165 = _M0L6_2atmpS1179 + 1;
            if (_M0L10next__charS215 == 58) {
              _M0L12dispatch__15S188 = 1;
              goto loop__label__15_191;
            } else {
              _M0L12dispatch__15S188 = 0;
              goto loop__label__15_191;
            }
          } else {
            goto join_181;
          }
          break;
        }
        default: {
          goto join_181;
          break;
        }
      }
      join_194:;
      _M0Lm9tag__0__1S174 = _M0Lm9tag__0__2S175;
      _M0Lm6tag__0S173 = _M0Lm9_2acursorS165;
      _M0Lm6tag__1S177 = _M0Lm9tag__1__1S178;
      _M0L6_2atmpS1145 = _M0Lm9_2acursorS165;
      if (_M0L6_2atmpS1145 < _M0L6_2aendS164) {
        int32_t _M0L6_2atmpS1147 = _M0Lm9_2acursorS165;
        int32_t _M0L10next__charS195;
        int32_t _M0L6_2atmpS1146;
        moonbit_incref(_M0L7_2adataS162);
        #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
        _M0L10next__charS195
        = _M0MPC16string6String20unsafe__charcode__at(_M0L7_2adataS162, _M0L6_2atmpS1147);
        _M0L6_2atmpS1146 = _M0Lm9_2acursorS165;
        _M0Lm9_2acursorS165 = _M0L6_2atmpS1146 + 1;
        if (_M0L10next__charS195 == 58) {
          _M0L12dispatch__15S188 = 1;
          continue;
        } else {
          _M0L12dispatch__15S188 = 6;
          continue;
        }
      } else {
        goto join_193;
      }
      join_193:;
      _M0Lm6tag__0S173 = _M0Lm9tag__0__1S174;
      _M0Lm20match__tag__saver__0S168 = _M0Lm6tag__0S173;
      _M0Lm20match__tag__saver__1S169 = _M0Lm6tag__1S177;
      _M0Lm20match__tag__saver__2S170 = _M0Lm6tag__2S176;
      _M0Lm20match__tag__saver__3S171 = _M0Lm6tag__3S180;
      _M0Lm20match__tag__saver__4S172 = _M0Lm6tag__4S179;
      _M0Lm13accept__stateS166 = 0;
      _M0Lm10match__endS167 = _M0Lm9_2acursorS165;
      goto join_181;
      join_189:;
      _M0Lm9tag__0__1S174 = _M0Lm9tag__0__2S175;
      _M0Lm6tag__0S173 = _M0Lm9_2acursorS165;
      _M0Lm6tag__1S177 = _M0Lm9tag__1__1S178;
      _M0L6_2atmpS1142 = _M0Lm9_2acursorS165;
      if (_M0L6_2atmpS1142 < _M0L6_2aendS164) {
        int32_t _M0L6_2atmpS1144 = _M0Lm9_2acursorS165;
        int32_t _M0L10next__charS192;
        int32_t _M0L6_2atmpS1143;
        moonbit_incref(_M0L7_2adataS162);
        #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
        _M0L10next__charS192
        = _M0MPC16string6String20unsafe__charcode__at(_M0L7_2adataS162, _M0L6_2atmpS1144);
        _M0L6_2atmpS1143 = _M0Lm9_2acursorS165;
        _M0Lm9_2acursorS165 = _M0L6_2atmpS1143 + 1;
        if (_M0L10next__charS192 < 58) {
          if (_M0L10next__charS192 < 48) {
            goto join_190;
          } else {
            _M0L12dispatch__15S188 = 4;
            continue;
          }
        } else if (_M0L10next__charS192 > 58) {
          goto join_190;
        } else {
          _M0L12dispatch__15S188 = 1;
          continue;
        }
        join_190:;
        _M0L12dispatch__15S188 = 0;
        continue;
      } else {
        goto join_181;
      }
      break;
    }
  } else {
    goto join_181;
  }
  join_181:;
  switch (_M0Lm13accept__stateS166) {
    case 0: {
      int32_t _M0L6_2atmpS1139 = _M0Lm20match__tag__saver__0S168;
      int32_t _M0L6_2atmpS1138 = _M0L6_2atmpS1139 + 1;
      int64_t _M0L6_2atmpS1135 = (int64_t)_M0L6_2atmpS1138;
      int32_t _M0L6_2atmpS1137 = _M0Lm20match__tag__saver__1S169;
      int64_t _M0L6_2atmpS1136 = (int64_t)_M0L6_2atmpS1137;
      struct _M0TPC16string10StringView _M0L11start__lineS182;
      int32_t _M0L6_2atmpS1134;
      int32_t _M0L6_2atmpS1133;
      int64_t _M0L6_2atmpS1130;
      int32_t _M0L6_2atmpS1132;
      int64_t _M0L6_2atmpS1131;
      struct _M0TPC16string10StringView _M0L13start__columnS183;
      int64_t _M0L6_2atmpS1127;
      int32_t _M0L6_2atmpS1129;
      int64_t _M0L6_2atmpS1128;
      struct _M0TPC16string10StringView _M0L8filenameS184;
      int32_t _M0L6_2atmpS1126;
      int32_t _M0L6_2atmpS1125;
      int64_t _M0L6_2atmpS1122;
      int32_t _M0L6_2atmpS1124;
      int64_t _M0L6_2atmpS1123;
      struct _M0TPC16string10StringView _M0L9end__lineS185;
      int32_t _M0L6_2atmpS1121;
      int32_t _M0L6_2atmpS1120;
      int64_t _M0L6_2atmpS1117;
      int32_t _M0L6_2atmpS1119;
      int64_t _M0L6_2atmpS1118;
      struct _M0TPC16string10StringView _M0L11end__columnS186;
      int32_t _M0L6_2atmpS1116;
      int32_t _M0L6_2atmpS1115;
      int64_t _M0L6_2atmpS1112;
      int32_t _M0L6_2atmpS1114;
      int64_t _M0L6_2atmpS1113;
      struct _M0TPC16string10StringView _M0L6_2atmpS1968;
      struct _M0TPB13SourceLocRepr* _block_2191;
      moonbit_incref(_M0L7_2adataS162);
      #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
      _M0L11start__lineS182
      = _M0MPC16string6String4view(_M0L7_2adataS162, _M0L6_2atmpS1135, _M0L6_2atmpS1136);
      _M0L6_2atmpS1134 = _M0Lm20match__tag__saver__1S169;
      _M0L6_2atmpS1133 = _M0L6_2atmpS1134 + 1;
      _M0L6_2atmpS1130 = (int64_t)_M0L6_2atmpS1133;
      _M0L6_2atmpS1132 = _M0Lm20match__tag__saver__2S170;
      _M0L6_2atmpS1131 = (int64_t)_M0L6_2atmpS1132;
      moonbit_incref(_M0L7_2adataS162);
      #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
      _M0L13start__columnS183
      = _M0MPC16string6String4view(_M0L7_2adataS162, _M0L6_2atmpS1130, _M0L6_2atmpS1131);
      _M0L6_2atmpS1127 = (int64_t)_M0L8_2astartS163;
      _M0L6_2atmpS1129 = _M0Lm20match__tag__saver__0S168;
      _M0L6_2atmpS1128 = (int64_t)_M0L6_2atmpS1129;
      moonbit_incref(_M0L7_2adataS162);
      #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
      _M0L8filenameS184
      = _M0MPC16string6String4view(_M0L7_2adataS162, _M0L6_2atmpS1127, _M0L6_2atmpS1128);
      _M0L6_2atmpS1126 = _M0Lm20match__tag__saver__2S170;
      _M0L6_2atmpS1125 = _M0L6_2atmpS1126 + 1;
      _M0L6_2atmpS1122 = (int64_t)_M0L6_2atmpS1125;
      _M0L6_2atmpS1124 = _M0Lm20match__tag__saver__3S171;
      _M0L6_2atmpS1123 = (int64_t)_M0L6_2atmpS1124;
      moonbit_incref(_M0L7_2adataS162);
      #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
      _M0L9end__lineS185
      = _M0MPC16string6String4view(_M0L7_2adataS162, _M0L6_2atmpS1122, _M0L6_2atmpS1123);
      _M0L6_2atmpS1121 = _M0Lm20match__tag__saver__3S171;
      _M0L6_2atmpS1120 = _M0L6_2atmpS1121 + 1;
      _M0L6_2atmpS1117 = (int64_t)_M0L6_2atmpS1120;
      _M0L6_2atmpS1119 = _M0Lm20match__tag__saver__4S172;
      _M0L6_2atmpS1118 = (int64_t)_M0L6_2atmpS1119;
      moonbit_incref(_M0L7_2adataS162);
      #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
      _M0L11end__columnS186
      = _M0MPC16string6String4view(_M0L7_2adataS162, _M0L6_2atmpS1117, _M0L6_2atmpS1118);
      _M0L6_2atmpS1116 = _M0Lm20match__tag__saver__4S172;
      _M0L6_2atmpS1115 = _M0L6_2atmpS1116 + 1;
      _M0L6_2atmpS1112 = (int64_t)_M0L6_2atmpS1115;
      _M0L6_2atmpS1114 = _M0Lm10match__endS167;
      _M0L6_2atmpS1113 = (int64_t)_M0L6_2atmpS1114;
      #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
      _M0L6_2atmpS1968
      = _M0MPC16string6String4view(_M0L7_2adataS162, _M0L6_2atmpS1112, _M0L6_2atmpS1113);
      moonbit_decref(_M0L6_2atmpS1968.$0);
      _block_2191
      = (struct _M0TPB13SourceLocRepr*)moonbit_malloc(sizeof(struct _M0TPB13SourceLocRepr));
      Moonbit_object_header(_block_2191)->meta
      = Moonbit_make_regular_object_header(offsetof(struct _M0TPB13SourceLocRepr, $0_0) >> 2, 5, 0);
      _block_2191->$0_0 = _M0L8filenameS184.$0;
      _block_2191->$0_1 = _M0L8filenameS184.$1;
      _block_2191->$0_2 = _M0L8filenameS184.$2;
      _block_2191->$1_0 = _M0L11start__lineS182.$0;
      _block_2191->$1_1 = _M0L11start__lineS182.$1;
      _block_2191->$1_2 = _M0L11start__lineS182.$2;
      _block_2191->$2_0 = _M0L13start__columnS183.$0;
      _block_2191->$2_1 = _M0L13start__columnS183.$1;
      _block_2191->$2_2 = _M0L13start__columnS183.$2;
      _block_2191->$3_0 = _M0L9end__lineS185.$0;
      _block_2191->$3_1 = _M0L9end__lineS185.$1;
      _block_2191->$3_2 = _M0L9end__lineS185.$2;
      _block_2191->$4_0 = _M0L11end__columnS186.$0;
      _block_2191->$4_1 = _M0L11end__columnS186.$1;
      _block_2191->$4_2 = _M0L11end__columnS186.$2;
      return _block_2191;
      break;
    }
    default: {
      moonbit_decref(_M0L7_2adataS162);
      #line 77 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\autoloc.mbt"
      moonbit_panic();
      break;
    }
  }
}

moonbit_string_t _M0MPC16string6String14escape_2einner(
  moonbit_string_t _M0L4selfS158,
  int32_t _M0L5quoteS159
) {
  struct _M0TPB13StringBuilder* _M0L3bufS157;
  int32_t _M0L6_2atmpS1111;
  struct _M0TPC16string10StringView _M0L6_2atmpS1109;
  struct _M0TPB6Logger _M0L6_2atmpS1110;
  #line 145 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  #line 146 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L3bufS157 = _M0MPB13StringBuilder11new_2einner(0);
  _M0L6_2atmpS1111 = Moonbit_array_length(_M0L4selfS158);
  _M0L6_2atmpS1109
  = (struct _M0TPC16string10StringView){
    0, _M0L6_2atmpS1111, _M0L4selfS158
  };
  moonbit_incref(_M0L3bufS157);
  _M0L6_2atmpS1110
  = (struct _M0TPB6Logger){
    _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id,
      _M0L3bufS157
  };
  #line 147 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0MPC16string10StringView18escape__to_2einner(_M0L6_2atmpS1109, _M0L6_2atmpS1110, _M0L5quoteS159);
  #line 148 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  return _M0MPB13StringBuilder10to__string(_M0L3bufS157);
}

int32_t _M0MPC16string10StringView18escape__to_2einner(
  struct _M0TPC16string10StringView _M0L4selfS149,
  struct _M0TPB6Logger _M0L6loggerS147,
  int32_t _M0L5quoteS146
) {
  int32_t _M0L3lenS148;
  struct _M0TURPB6LoggerRPC16string10StringViewE* _M0L6_2aenvS150;
  int32_t _M0L1iS151;
  int32_t _M0L3segS152;
  #line 179 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  if (_M0L5quoteS146) {
    if (_M0L6loggerS147.$1) {
      moonbit_incref(_M0L6loggerS147.$1);
    }
    #line 185 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6loggerS147.$0->$method_3(_M0L6loggerS147.$1, 34);
  }
  moonbit_incref(_M0L4selfS149.$0);
  #line 187 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L3lenS148 = _M0MPC16string10StringView6length(_M0L4selfS149);
  if (_M0L6loggerS147.$1) {
    moonbit_incref(_M0L6loggerS147.$1);
  }
  moonbit_incref(_M0L4selfS149.$0);
  _M0L6_2aenvS150
  = (struct _M0TURPB6LoggerRPC16string10StringViewE*)moonbit_malloc(sizeof(struct _M0TURPB6LoggerRPC16string10StringViewE));
  Moonbit_object_header(_M0L6_2aenvS150)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TURPB6LoggerRPC16string10StringViewE, $0_0) >> 2, 3, 0);
  _M0L6_2aenvS150->$0_0 = _M0L6loggerS147.$0;
  _M0L6_2aenvS150->$0_1 = _M0L6loggerS147.$1;
  _M0L6_2aenvS150->$1_0 = _M0L4selfS149.$0;
  _M0L6_2aenvS150->$1_1 = _M0L4selfS149.$1;
  _M0L6_2aenvS150->$1_2 = _M0L4selfS149.$2;
  _M0L1iS151 = 0;
  _M0L3segS152 = 0;
  _2afor_153:;
  while (1) {
    int32_t _M0L4codeS154;
    int32_t _M0L1cS156;
    int32_t _M0L6_2atmpS1093;
    int32_t _M0L6_2atmpS1094;
    int32_t _M0L6_2atmpS1095;
    int32_t _tmp_2195;
    int32_t _tmp_2196;
    if (_M0L1iS151 >= _M0L3lenS148) {
      moonbit_decref(_M0L4selfS149.$0);
      #line 195 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
      _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(_M0L6_2aenvS150, _M0L3segS152, _M0L1iS151);
      break;
    }
    moonbit_incref(_M0L4selfS149.$0);
    #line 198 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L4codeS154
    = _M0MPC16string10StringView11unsafe__get(_M0L4selfS149, _M0L1iS151);
    switch (_M0L4codeS154) {
      case 34: {
        _M0L1cS156 = _M0L4codeS154;
        goto join_155;
        break;
      }
      
      case 92: {
        _M0L1cS156 = _M0L4codeS154;
        goto join_155;
        break;
      }
      
      case 10: {
        int32_t _M0L6_2atmpS1096;
        int32_t _M0L6_2atmpS1097;
        moonbit_incref(_M0L6_2aenvS150);
        #line 207 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(_M0L6_2aenvS150, _M0L3segS152, _M0L1iS151);
        if (_M0L6loggerS147.$1) {
          moonbit_incref(_M0L6loggerS147.$1);
        }
        #line 208 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0L6loggerS147.$0->$method_0(_M0L6loggerS147.$1, (moonbit_string_t)moonbit_string_literal_67.data);
        _M0L6_2atmpS1096 = _M0L1iS151 + 1;
        _M0L6_2atmpS1097 = _M0L1iS151 + 1;
        _M0L1iS151 = _M0L6_2atmpS1096;
        _M0L3segS152 = _M0L6_2atmpS1097;
        goto _2afor_153;
        break;
      }
      
      case 13: {
        int32_t _M0L6_2atmpS1098;
        int32_t _M0L6_2atmpS1099;
        moonbit_incref(_M0L6_2aenvS150);
        #line 212 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(_M0L6_2aenvS150, _M0L3segS152, _M0L1iS151);
        if (_M0L6loggerS147.$1) {
          moonbit_incref(_M0L6loggerS147.$1);
        }
        #line 213 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0L6loggerS147.$0->$method_0(_M0L6loggerS147.$1, (moonbit_string_t)moonbit_string_literal_68.data);
        _M0L6_2atmpS1098 = _M0L1iS151 + 1;
        _M0L6_2atmpS1099 = _M0L1iS151 + 1;
        _M0L1iS151 = _M0L6_2atmpS1098;
        _M0L3segS152 = _M0L6_2atmpS1099;
        goto _2afor_153;
        break;
      }
      
      case 8: {
        int32_t _M0L6_2atmpS1100;
        int32_t _M0L6_2atmpS1101;
        moonbit_incref(_M0L6_2aenvS150);
        #line 217 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(_M0L6_2aenvS150, _M0L3segS152, _M0L1iS151);
        if (_M0L6loggerS147.$1) {
          moonbit_incref(_M0L6loggerS147.$1);
        }
        #line 218 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0L6loggerS147.$0->$method_0(_M0L6loggerS147.$1, (moonbit_string_t)moonbit_string_literal_69.data);
        _M0L6_2atmpS1100 = _M0L1iS151 + 1;
        _M0L6_2atmpS1101 = _M0L1iS151 + 1;
        _M0L1iS151 = _M0L6_2atmpS1100;
        _M0L3segS152 = _M0L6_2atmpS1101;
        goto _2afor_153;
        break;
      }
      
      case 9: {
        int32_t _M0L6_2atmpS1102;
        int32_t _M0L6_2atmpS1103;
        moonbit_incref(_M0L6_2aenvS150);
        #line 222 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(_M0L6_2aenvS150, _M0L3segS152, _M0L1iS151);
        if (_M0L6loggerS147.$1) {
          moonbit_incref(_M0L6loggerS147.$1);
        }
        #line 223 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0L6loggerS147.$0->$method_0(_M0L6loggerS147.$1, (moonbit_string_t)moonbit_string_literal_70.data);
        _M0L6_2atmpS1102 = _M0L1iS151 + 1;
        _M0L6_2atmpS1103 = _M0L1iS151 + 1;
        _M0L1iS151 = _M0L6_2atmpS1102;
        _M0L3segS152 = _M0L6_2atmpS1103;
        goto _2afor_153;
        break;
      }
      default: {
        if (_M0L4codeS154 < 32) {
          int32_t _M0L6_2atmpS1105;
          moonbit_string_t _M0L6_2atmpS1104;
          int32_t _M0L6_2atmpS1106;
          int32_t _M0L6_2atmpS1107;
          moonbit_incref(_M0L6_2aenvS150);
          #line 228 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
          _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(_M0L6_2aenvS150, _M0L3segS152, _M0L1iS151);
          if (_M0L6loggerS147.$1) {
            moonbit_incref(_M0L6loggerS147.$1);
          }
          #line 229 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
          _M0L6loggerS147.$0->$method_0(_M0L6loggerS147.$1, (moonbit_string_t)moonbit_string_literal_71.data);
          _M0L6_2atmpS1105 = _M0L4codeS154 & 0xff;
          #line 230 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
          _M0L6_2atmpS1104 = _M0MPC14byte4Byte7to__hex(_M0L6_2atmpS1105);
          if (_M0L6loggerS147.$1) {
            moonbit_incref(_M0L6loggerS147.$1);
          }
          #line 230 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
          _M0L6loggerS147.$0->$method_0(_M0L6loggerS147.$1, _M0L6_2atmpS1104);
          if (_M0L6loggerS147.$1) {
            moonbit_incref(_M0L6loggerS147.$1);
          }
          #line 231 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
          _M0L6loggerS147.$0->$method_3(_M0L6loggerS147.$1, 125);
          _M0L6_2atmpS1106 = _M0L1iS151 + 1;
          _M0L6_2atmpS1107 = _M0L1iS151 + 1;
          _M0L1iS151 = _M0L6_2atmpS1106;
          _M0L3segS152 = _M0L6_2atmpS1107;
          goto _2afor_153;
        } else {
          int32_t _M0L6_2atmpS1108 = _M0L1iS151 + 1;
          int32_t _tmp_2194 = _M0L3segS152;
          _M0L1iS151 = _M0L6_2atmpS1108;
          _M0L3segS152 = _tmp_2194;
          goto _2afor_153;
        }
        break;
      }
    }
    goto joinlet_2193;
    join_155:;
    moonbit_incref(_M0L6_2aenvS150);
    #line 201 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(_M0L6_2aenvS150, _M0L3segS152, _M0L1iS151);
    if (_M0L6loggerS147.$1) {
      moonbit_incref(_M0L6loggerS147.$1);
    }
    #line 202 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6loggerS147.$0->$method_3(_M0L6loggerS147.$1, 92);
    #line 203 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6_2atmpS1093 = _M0MPC16uint166UInt1616unsafe__to__char(_M0L1cS156);
    if (_M0L6loggerS147.$1) {
      moonbit_incref(_M0L6loggerS147.$1);
    }
    #line 203 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6loggerS147.$0->$method_3(_M0L6loggerS147.$1, _M0L6_2atmpS1093);
    _M0L6_2atmpS1094 = _M0L1iS151 + 1;
    _M0L6_2atmpS1095 = _M0L1iS151 + 1;
    _M0L1iS151 = _M0L6_2atmpS1094;
    _M0L3segS152 = _M0L6_2atmpS1095;
    continue;
    joinlet_2193:;
    _tmp_2195 = _M0L1iS151;
    _tmp_2196 = _M0L3segS152;
    _M0L1iS151 = _tmp_2195;
    _M0L3segS152 = _tmp_2196;
    continue;
    break;
  }
  if (_M0L5quoteS146) {
    #line 239 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6loggerS147.$0->$method_3(_M0L6loggerS147.$1, 34);
  } else if (_M0L6loggerS147.$1) {
    moonbit_decref(_M0L6loggerS147.$1);
  }
  return 0;
}

int32_t _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(
  struct _M0TURPB6LoggerRPC16string10StringViewE* _M0L6_2aenvS142,
  int32_t _M0L3segS145,
  int32_t _M0L1iS144
) {
  struct _M0TPC16string10StringView _M0L4selfS141;
  struct _M0TPB6Logger _M0L8_2afieldS1969;
  int32_t _M0L6_2acntS2053;
  struct _M0TPB6Logger _M0L6loggerS143;
  #line 188 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L4selfS141
  = (struct _M0TPC16string10StringView){
    _M0L6_2aenvS142->$1_1, _M0L6_2aenvS142->$1_2, _M0L6_2aenvS142->$1_0
  };
  _M0L8_2afieldS1969
  = (struct _M0TPB6Logger){
    _M0L6_2aenvS142->$0_0, _M0L6_2aenvS142->$0_1
  };
  _M0L6_2acntS2053 = Moonbit_object_header(_M0L6_2aenvS142)->rc;
  if (_M0L6_2acntS2053 > 1) {
    int32_t _M0L11_2anew__cntS2054 = _M0L6_2acntS2053 - 1;
    Moonbit_object_header(_M0L6_2aenvS142)->rc = _M0L11_2anew__cntS2054;
    moonbit_incref(_M0L4selfS141.$0);
    if (_M0L8_2afieldS1969.$1) {
      moonbit_incref(_M0L8_2afieldS1969.$1);
    }
  } else if (_M0L6_2acntS2053 == 1) {
    #line 188 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    moonbit_free(_M0L6_2aenvS142);
  }
  _M0L6loggerS143 = _M0L8_2afieldS1969;
  if (_M0L1iS144 > _M0L3segS145) {
    int64_t _M0L6_2atmpS1092 = (int64_t)_M0L1iS144;
    struct _M0TPC16string10StringView _M0L6_2atmpS1091;
    #line 190 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6_2atmpS1091
    = _M0MPC16string10StringView11sub_2einner(_M0L4selfS141, _M0L3segS145, _M0L6_2atmpS1092);
    #line 190 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6loggerS143.$0->$method_2(_M0L6loggerS143.$1, _M0L6_2atmpS1091);
  } else {
    if (_M0L6loggerS143.$1) {
      moonbit_decref(_M0L6loggerS143.$1);
    }
    moonbit_decref(_M0L4selfS141.$0);
  }
  return 0;
}

int32_t _M0MPC16string10StringView11unsafe__get(
  struct _M0TPC16string10StringView _M0L4selfS139,
  int32_t _M0L5indexS140
) {
  moonbit_string_t _M0L3strS1088;
  int32_t _M0L5startS1090;
  int32_t _M0L6_2atmpS1089;
  int32_t _result_2197;
  #line 127 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  _M0L3strS1088 = _M0L4selfS139.$0;
  _M0L5startS1090 = _M0L4selfS139.$1;
  _M0L6_2atmpS1089 = _M0L5startS1090 + _M0L5indexS140;
  _result_2197 = _M0L3strS1088[_M0L6_2atmpS1089];
  moonbit_decref(_M0L3strS1088);
  return _result_2197;
}

struct _M0TPC16string10StringView _M0MPC16string10StringView11sub_2einner(
  struct _M0TPC16string10StringView _M0L4selfS132,
  int32_t _M0L5startS138,
  int64_t _M0L3endS134
) {
  moonbit_string_t _M0L3strS1087;
  int32_t _M0L8str__lenS131;
  int32_t _M0L8abs__endS133;
  int32_t _M0L10abs__startS137;
  int32_t _M0L5startS1075;
  int32_t _if__result_2198;
  #line 698 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  _M0L3strS1087 = _M0L4selfS132.$0;
  _M0L8str__lenS131 = Moonbit_array_length(_M0L3strS1087);
  if (_M0L3endS134 == 4294967296ll) {
    _M0L8abs__endS133 = _M0L4selfS132.$2;
  } else {
    int64_t _M0L7_2aSomeS135 = _M0L3endS134;
    int32_t _M0L6_2aendS136 = (int32_t)_M0L7_2aSomeS135;
    if (_M0L6_2aendS136 < 0) {
      int32_t _M0L3endS1085 = _M0L4selfS132.$2;
      _M0L8abs__endS133 = _M0L3endS1085 + _M0L6_2aendS136;
    } else {
      int32_t _M0L5startS1086 = _M0L4selfS132.$1;
      _M0L8abs__endS133 = _M0L5startS1086 + _M0L6_2aendS136;
    }
  }
  if (_M0L5startS138 < 0) {
    int32_t _M0L3endS1083 = _M0L4selfS132.$2;
    _M0L10abs__startS137 = _M0L3endS1083 + _M0L5startS138;
  } else {
    int32_t _M0L5startS1084 = _M0L4selfS132.$1;
    _M0L10abs__startS137 = _M0L5startS1084 + _M0L5startS138;
  }
  _M0L5startS1075 = _M0L4selfS132.$1;
  if (_M0L10abs__startS137 >= _M0L5startS1075) {
    if (_M0L10abs__startS137 <= _M0L8abs__endS133) {
      int32_t _M0L3endS1074 = _M0L4selfS132.$2;
      _if__result_2198 = _M0L8abs__endS133 <= _M0L3endS1074;
    } else {
      _if__result_2198 = 0;
    }
  } else {
    _if__result_2198 = 0;
  }
  if (_if__result_2198) {
    moonbit_string_t _M0L3strS1082;
    if (_M0L10abs__startS137 < _M0L8str__lenS131) {
      moonbit_string_t _M0L3strS1078 = _M0L4selfS132.$0;
      int32_t _M0L6_2atmpS1077 = _M0L3strS1078[_M0L10abs__startS137];
      int32_t _M0L6_2atmpS1076;
      #line 724 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
      _M0L6_2atmpS1076
      = _M0MPC16uint166UInt1623is__trailing__surrogate(_M0L6_2atmpS1077);
      if (!_M0L6_2atmpS1076) {
        
      } else {
        #line 724 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
        moonbit_panic();
      }
    }
    if (_M0L8abs__endS133 < _M0L8str__lenS131) {
      moonbit_string_t _M0L3strS1081 = _M0L4selfS132.$0;
      int32_t _M0L6_2atmpS1080 = _M0L3strS1081[_M0L8abs__endS133];
      int32_t _M0L6_2atmpS1079;
      #line 727 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
      _M0L6_2atmpS1079
      = _M0MPC16uint166UInt1623is__trailing__surrogate(_M0L6_2atmpS1080);
      if (!_M0L6_2atmpS1079) {
        
      } else {
        #line 727 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
        moonbit_panic();
      }
    }
    _M0L3strS1082 = _M0L4selfS132.$0;
    return (struct _M0TPC16string10StringView){_M0L10abs__startS137,
                                                 _M0L8abs__endS133,
                                                 _M0L3strS1082};
  } else {
    moonbit_decref(_M0L4selfS132.$0);
    #line 718 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
    moonbit_panic();
  }
}

int32_t _M0MPC16string10StringView6length(
  struct _M0TPC16string10StringView _M0L4selfS130
) {
  int32_t _M0L3endS1072;
  int32_t _M0L5startS1073;
  #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  _M0L3endS1072 = _M0L4selfS130.$2;
  _M0L5startS1073 = _M0L4selfS130.$1;
  moonbit_decref(_M0L4selfS130.$0);
  return _M0L3endS1072 - _M0L5startS1073;
}

moonbit_string_t _M0MPC14byte4Byte7to__hex(int32_t _M0L1bS129) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS128;
  int32_t _M0L6_2atmpS1069;
  int32_t _M0L6_2atmpS1068;
  int32_t _M0L6_2atmpS1071;
  int32_t _M0L6_2atmpS1070;
  struct _M0TPB13StringBuilder* _M0L6_2atmpS1067;
  #line 109 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L7_2aselfS128 = _M0MPB13StringBuilder11new_2einner(0);
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L6_2atmpS1069 = _M0IPC14byte4BytePB3Div3div(_M0L1bS129, 16);
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L6_2atmpS1068
  = _M0MPC14byte4Byte7to__hexN14to__hex__digitS3630(_M0L6_2atmpS1069);
  moonbit_incref(_M0L7_2aselfS128);
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0IPB13StringBuilderPB6Logger11write__char(_M0L7_2aselfS128, _M0L6_2atmpS1068);
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L6_2atmpS1071 = _M0IPC14byte4BytePB3Mod3mod(_M0L1bS129, 16);
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L6_2atmpS1070
  = _M0MPC14byte4Byte7to__hexN14to__hex__digitS3630(_M0L6_2atmpS1071);
  moonbit_incref(_M0L7_2aselfS128);
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0IPB13StringBuilderPB6Logger11write__char(_M0L7_2aselfS128, _M0L6_2atmpS1070);
  _M0L6_2atmpS1067 = _M0L7_2aselfS128;
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  return _M0MPB13StringBuilder10to__string(_M0L6_2atmpS1067);
}

int32_t _M0MPC14byte4Byte7to__hexN14to__hex__digitS3630(int32_t _M0L1iS127) {
  #line 110 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  if (_M0L1iS127 < 10) {
    int32_t _M0L6_2atmpS1064;
    #line 112 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6_2atmpS1064 = _M0IPC14byte4BytePB3Add3add(_M0L1iS127, 48);
    #line 112 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    return _M0MPC14byte4Byte8to__char(_M0L6_2atmpS1064);
  } else {
    int32_t _M0L6_2atmpS1066;
    int32_t _M0L6_2atmpS1065;
    #line 114 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6_2atmpS1066 = _M0IPC14byte4BytePB3Add3add(_M0L1iS127, 97);
    #line 114 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6_2atmpS1065 = _M0IPC14byte4BytePB3Sub3sub(_M0L6_2atmpS1066, 10);
    #line 114 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    return _M0MPC14byte4Byte8to__char(_M0L6_2atmpS1065);
  }
}

int32_t _M0IPC14byte4BytePB3Sub3sub(
  int32_t _M0L4selfS125,
  int32_t _M0L4thatS126
) {
  int32_t _M0L6_2atmpS1062;
  int32_t _M0L6_2atmpS1063;
  int32_t _M0L6_2atmpS1061;
  #line 120 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\byte.mbt"
  _M0L6_2atmpS1062 = (int32_t)_M0L4selfS125;
  _M0L6_2atmpS1063 = (int32_t)_M0L4thatS126;
  _M0L6_2atmpS1061 = _M0L6_2atmpS1062 - _M0L6_2atmpS1063;
  return _M0L6_2atmpS1061 & 0xff;
}

int32_t _M0IPC14byte4BytePB3Mod3mod(
  int32_t _M0L4selfS123,
  int32_t _M0L4thatS124
) {
  int32_t _M0L6_2atmpS1059;
  int32_t _M0L6_2atmpS1060;
  int32_t _M0L6_2atmpS1058;
  #line 67 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\byte.mbt"
  _M0L6_2atmpS1059 = (int32_t)_M0L4selfS123;
  _M0L6_2atmpS1060 = (int32_t)_M0L4thatS124;
  _M0L6_2atmpS1058 = _M0L6_2atmpS1059 % _M0L6_2atmpS1060;
  return _M0L6_2atmpS1058 & 0xff;
}

int32_t _M0IPC14byte4BytePB3Div3div(
  int32_t _M0L4selfS121,
  int32_t _M0L4thatS122
) {
  int32_t _M0L6_2atmpS1056;
  int32_t _M0L6_2atmpS1057;
  int32_t _M0L6_2atmpS1055;
  #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\byte.mbt"
  _M0L6_2atmpS1056 = (int32_t)_M0L4selfS121;
  _M0L6_2atmpS1057 = (int32_t)_M0L4thatS122;
  _M0L6_2atmpS1055 = _M0L6_2atmpS1056 / _M0L6_2atmpS1057;
  return _M0L6_2atmpS1055 & 0xff;
}

int32_t _M0IPC14byte4BytePB3Add3add(
  int32_t _M0L4selfS119,
  int32_t _M0L4thatS120
) {
  int32_t _M0L6_2atmpS1053;
  int32_t _M0L6_2atmpS1054;
  int32_t _M0L6_2atmpS1052;
  #line 106 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\byte.mbt"
  _M0L6_2atmpS1053 = (int32_t)_M0L4selfS119;
  _M0L6_2atmpS1054 = (int32_t)_M0L4thatS120;
  _M0L6_2atmpS1052 = _M0L6_2atmpS1053 + _M0L6_2atmpS1054;
  return _M0L6_2atmpS1052 & 0xff;
}

moonbit_string_t _M0FPB33base64__encode__string__codepoint(
  moonbit_string_t _M0L1sS113
) {
  int32_t _M0L17codepoint__lengthS112;
  int32_t _M0L6_2atmpS1051;
  moonbit_bytes_t _M0L4dataS114;
  int32_t _M0L1iS115;
  int32_t _M0L12utf16__indexS116;
  #line 102 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  moonbit_incref(_M0L1sS113);
  #line 104 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  _M0L17codepoint__lengthS112
  = _M0MPC16string6String20char__length_2einner(_M0L1sS113, 0, 4294967296ll);
  _M0L6_2atmpS1051 = _M0L17codepoint__lengthS112 * 4;
  _M0L4dataS114 = (moonbit_bytes_t)moonbit_make_bytes(_M0L6_2atmpS1051, 0);
  _M0L1iS115 = 0;
  _M0L12utf16__indexS116 = 0;
  while (1) {
    if (_M0L1iS115 < _M0L17codepoint__lengthS112) {
      int32_t _M0L6_2atmpS1048;
      int32_t _M0L1cS117;
      int32_t _M0L6_2atmpS1049;
      int32_t _M0L6_2atmpS1050;
      moonbit_incref(_M0L1sS113);
      #line 109 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      _M0L6_2atmpS1048
      = _M0MPC16string6String16unsafe__char__at(_M0L1sS113, _M0L12utf16__indexS116);
      _M0L1cS117 = _M0L6_2atmpS1048;
      if (_M0L1cS117 > 65535) {
        int32_t _M0L6_2atmpS1016 = _M0L1iS115 * 4;
        int32_t _M0L6_2atmpS1018 = _M0L1cS117 & 255;
        int32_t _M0L6_2atmpS1017 = _M0L6_2atmpS1018 & 0xff;
        int32_t _M0L6_2atmpS1023;
        int32_t _M0L6_2atmpS1019;
        int32_t _M0L6_2atmpS1022;
        int32_t _M0L6_2atmpS1021;
        int32_t _M0L6_2atmpS1020;
        int32_t _M0L6_2atmpS1028;
        int32_t _M0L6_2atmpS1024;
        int32_t _M0L6_2atmpS1027;
        int32_t _M0L6_2atmpS1026;
        int32_t _M0L6_2atmpS1025;
        int32_t _M0L6_2atmpS1033;
        int32_t _M0L6_2atmpS1029;
        int32_t _M0L6_2atmpS1032;
        int32_t _M0L6_2atmpS1031;
        int32_t _M0L6_2atmpS1030;
        int32_t _M0L6_2atmpS1034;
        int32_t _M0L6_2atmpS1035;
        if (
          _M0L6_2atmpS1016 < 0
          || _M0L6_2atmpS1016 >= Moonbit_array_length(_M0L4dataS114)
        ) {
          #line 111 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
          moonbit_panic();
        }
        _M0L4dataS114[_M0L6_2atmpS1016] = _M0L6_2atmpS1017;
        _M0L6_2atmpS1023 = _M0L1iS115 * 4;
        _M0L6_2atmpS1019 = _M0L6_2atmpS1023 + 1;
        _M0L6_2atmpS1022 = _M0L1cS117 >> 8;
        _M0L6_2atmpS1021 = _M0L6_2atmpS1022 & 255;
        _M0L6_2atmpS1020 = _M0L6_2atmpS1021 & 0xff;
        if (
          _M0L6_2atmpS1019 < 0
          || _M0L6_2atmpS1019 >= Moonbit_array_length(_M0L4dataS114)
        ) {
          #line 112 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
          moonbit_panic();
        }
        _M0L4dataS114[_M0L6_2atmpS1019] = _M0L6_2atmpS1020;
        _M0L6_2atmpS1028 = _M0L1iS115 * 4;
        _M0L6_2atmpS1024 = _M0L6_2atmpS1028 + 2;
        _M0L6_2atmpS1027 = _M0L1cS117 >> 16;
        _M0L6_2atmpS1026 = _M0L6_2atmpS1027 & 255;
        _M0L6_2atmpS1025 = _M0L6_2atmpS1026 & 0xff;
        if (
          _M0L6_2atmpS1024 < 0
          || _M0L6_2atmpS1024 >= Moonbit_array_length(_M0L4dataS114)
        ) {
          #line 113 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
          moonbit_panic();
        }
        _M0L4dataS114[_M0L6_2atmpS1024] = _M0L6_2atmpS1025;
        _M0L6_2atmpS1033 = _M0L1iS115 * 4;
        _M0L6_2atmpS1029 = _M0L6_2atmpS1033 + 3;
        _M0L6_2atmpS1032 = _M0L1cS117 >> 24;
        _M0L6_2atmpS1031 = _M0L6_2atmpS1032 & 255;
        _M0L6_2atmpS1030 = _M0L6_2atmpS1031 & 0xff;
        if (
          _M0L6_2atmpS1029 < 0
          || _M0L6_2atmpS1029 >= Moonbit_array_length(_M0L4dataS114)
        ) {
          #line 114 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
          moonbit_panic();
        }
        _M0L4dataS114[_M0L6_2atmpS1029] = _M0L6_2atmpS1030;
        _M0L6_2atmpS1034 = _M0L1iS115 + 1;
        _M0L6_2atmpS1035 = _M0L12utf16__indexS116 + 2;
        _M0L1iS115 = _M0L6_2atmpS1034;
        _M0L12utf16__indexS116 = _M0L6_2atmpS1035;
        continue;
      } else {
        int32_t _M0L6_2atmpS1036 = _M0L1iS115 * 4;
        int32_t _M0L6_2atmpS1038 = _M0L1cS117 & 255;
        int32_t _M0L6_2atmpS1037 = _M0L6_2atmpS1038 & 0xff;
        int32_t _M0L6_2atmpS1043;
        int32_t _M0L6_2atmpS1039;
        int32_t _M0L6_2atmpS1042;
        int32_t _M0L6_2atmpS1041;
        int32_t _M0L6_2atmpS1040;
        int32_t _M0L6_2atmpS1045;
        int32_t _M0L6_2atmpS1044;
        int32_t _M0L6_2atmpS1047;
        int32_t _M0L6_2atmpS1046;
        if (
          _M0L6_2atmpS1036 < 0
          || _M0L6_2atmpS1036 >= Moonbit_array_length(_M0L4dataS114)
        ) {
          #line 117 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
          moonbit_panic();
        }
        _M0L4dataS114[_M0L6_2atmpS1036] = _M0L6_2atmpS1037;
        _M0L6_2atmpS1043 = _M0L1iS115 * 4;
        _M0L6_2atmpS1039 = _M0L6_2atmpS1043 + 1;
        _M0L6_2atmpS1042 = _M0L1cS117 >> 8;
        _M0L6_2atmpS1041 = _M0L6_2atmpS1042 & 255;
        _M0L6_2atmpS1040 = _M0L6_2atmpS1041 & 0xff;
        if (
          _M0L6_2atmpS1039 < 0
          || _M0L6_2atmpS1039 >= Moonbit_array_length(_M0L4dataS114)
        ) {
          #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
          moonbit_panic();
        }
        _M0L4dataS114[_M0L6_2atmpS1039] = _M0L6_2atmpS1040;
        _M0L6_2atmpS1045 = _M0L1iS115 * 4;
        _M0L6_2atmpS1044 = _M0L6_2atmpS1045 + 2;
        if (
          _M0L6_2atmpS1044 < 0
          || _M0L6_2atmpS1044 >= Moonbit_array_length(_M0L4dataS114)
        ) {
          #line 119 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
          moonbit_panic();
        }
        _M0L4dataS114[_M0L6_2atmpS1044] = 0;
        _M0L6_2atmpS1047 = _M0L1iS115 * 4;
        _M0L6_2atmpS1046 = _M0L6_2atmpS1047 + 3;
        if (
          _M0L6_2atmpS1046 < 0
          || _M0L6_2atmpS1046 >= Moonbit_array_length(_M0L4dataS114)
        ) {
          #line 120 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
          moonbit_panic();
        }
        _M0L4dataS114[_M0L6_2atmpS1046] = 0;
      }
      _M0L6_2atmpS1049 = _M0L1iS115 + 1;
      _M0L6_2atmpS1050 = _M0L12utf16__indexS116 + 1;
      _M0L1iS115 = _M0L6_2atmpS1049;
      _M0L12utf16__indexS116 = _M0L6_2atmpS1050;
      continue;
    } else {
      moonbit_decref(_M0L1sS113);
    }
    break;
  }
  #line 123 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  return _M0FPB14base64__encode(_M0L4dataS114);
}

int32_t _M0MPC16string6String16unsafe__char__at(
  moonbit_string_t _M0L4selfS109,
  int32_t _M0L5indexS110
) {
  int32_t _M0L2c1S108;
  #line 91 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\deprecated.mbt"
  _M0L2c1S108 = _M0L4selfS109[_M0L5indexS110];
  #line 94 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\deprecated.mbt"
  if (_M0MPC16uint166UInt1622is__leading__surrogate(_M0L2c1S108)) {
    int32_t _M0L6_2atmpS1015 = _M0L5indexS110 + 1;
    int32_t _M0L2c2S111 = _M0L4selfS109[_M0L6_2atmpS1015];
    int32_t _M0L6_2atmpS1013;
    int32_t _M0L6_2atmpS1014;
    moonbit_decref(_M0L4selfS109);
    _M0L6_2atmpS1013 = (int32_t)_M0L2c1S108;
    _M0L6_2atmpS1014 = (int32_t)_M0L2c2S111;
    #line 96 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\deprecated.mbt"
    return _M0FPB32code__point__of__surrogate__pair(_M0L6_2atmpS1013, _M0L6_2atmpS1014);
  } else {
    moonbit_decref(_M0L4selfS109);
    #line 98 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\deprecated.mbt"
    return _M0MPC16uint166UInt1616unsafe__to__char(_M0L2c1S108);
  }
}

int32_t _M0MPC16uint166UInt1616unsafe__to__char(int32_t _M0L4selfS107) {
  int32_t _M0L6_2atmpS1012;
  #line 68 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uint16_char.mbt"
  _M0L6_2atmpS1012 = (int32_t)_M0L4selfS107;
  return _M0L6_2atmpS1012;
}

int32_t _M0FPB32code__point__of__surrogate__pair(
  int32_t _M0L7leadingS105,
  int32_t _M0L8trailingS106
) {
  int32_t _M0L6_2atmpS1011;
  int32_t _M0L6_2atmpS1010;
  int32_t _M0L6_2atmpS1009;
  int32_t _M0L6_2atmpS1008;
  int32_t _M0L6_2atmpS1007;
  #line 40 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
  _M0L6_2atmpS1011 = _M0L7leadingS105 - 55296;
  _M0L6_2atmpS1010 = _M0L6_2atmpS1011 * 1024;
  _M0L6_2atmpS1009 = _M0L6_2atmpS1010 + _M0L8trailingS106;
  _M0L6_2atmpS1008 = _M0L6_2atmpS1009 - 56320;
  _M0L6_2atmpS1007 = _M0L6_2atmpS1008 + 65536;
  return _M0L6_2atmpS1007;
}

int32_t _M0MPC16string6String20char__length_2einner(
  moonbit_string_t _M0L4selfS98,
  int32_t _M0L13start__offsetS99,
  int64_t _M0L11end__offsetS96
) {
  int32_t _M0L11end__offsetS95;
  int32_t _if__result_2200;
  #line 60 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
  if (_M0L11end__offsetS96 == 4294967296ll) {
    _M0L11end__offsetS95 = Moonbit_array_length(_M0L4selfS98);
  } else {
    int64_t _M0L7_2aSomeS97 = _M0L11end__offsetS96;
    _M0L11end__offsetS95 = (int32_t)_M0L7_2aSomeS97;
  }
  if (_M0L13start__offsetS99 >= 0) {
    if (_M0L13start__offsetS99 <= _M0L11end__offsetS95) {
      int32_t _M0L6_2atmpS1000 = Moonbit_array_length(_M0L4selfS98);
      _if__result_2200 = _M0L11end__offsetS95 <= _M0L6_2atmpS1000;
    } else {
      _if__result_2200 = 0;
    }
  } else {
    _if__result_2200 = 0;
  }
  if (_if__result_2200) {
    int32_t _M0L12utf16__indexS100 = _M0L13start__offsetS99;
    int32_t _M0L11char__countS101 = 0;
    while (1) {
      if (_M0L12utf16__indexS100 < _M0L11end__offsetS95) {
        int32_t _M0L2c1S102 = _M0L4selfS98[_M0L12utf16__indexS100];
        int32_t _if__result_2202;
        int32_t _M0L6_2atmpS1005;
        int32_t _M0L6_2atmpS1006;
        #line 76 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
        if (_M0MPC16uint166UInt1622is__leading__surrogate(_M0L2c1S102)) {
          int32_t _M0L6_2atmpS1001 = _M0L12utf16__indexS100 + 1;
          _if__result_2202 = _M0L6_2atmpS1001 < _M0L11end__offsetS95;
        } else {
          _if__result_2202 = 0;
        }
        if (_if__result_2202) {
          int32_t _M0L6_2atmpS1004 = _M0L12utf16__indexS100 + 1;
          int32_t _M0L2c2S103 = _M0L4selfS98[_M0L6_2atmpS1004];
          #line 78 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
          if (_M0MPC16uint166UInt1623is__trailing__surrogate(_M0L2c2S103)) {
            int32_t _M0L6_2atmpS1002 = _M0L12utf16__indexS100 + 2;
            int32_t _M0L6_2atmpS1003 = _M0L11char__countS101 + 1;
            _M0L12utf16__indexS100 = _M0L6_2atmpS1002;
            _M0L11char__countS101 = _M0L6_2atmpS1003;
            continue;
          } else {
            #line 81 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
            _M0FPC15abort5abortGuE((moonbit_string_t)moonbit_string_literal_46.data);
          }
        }
        _M0L6_2atmpS1005 = _M0L12utf16__indexS100 + 1;
        _M0L6_2atmpS1006 = _M0L11char__countS101 + 1;
        _M0L12utf16__indexS100 = _M0L6_2atmpS1005;
        _M0L11char__countS101 = _M0L6_2atmpS1006;
        continue;
      } else {
        moonbit_decref(_M0L4selfS98);
        return _M0L11char__countS101;
      }
      break;
    }
  } else {
    moonbit_decref(_M0L4selfS98);
    #line 70 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
    return _M0FPC15abort5abortGiE((moonbit_string_t)moonbit_string_literal_72.data);
  }
}

int32_t _M0MPC16uint166UInt1623is__trailing__surrogate(int32_t _M0L4selfS94) {
  #line 45 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uint16_char.mbt"
  if (_M0L4selfS94 >= 56320) {
    return _M0L4selfS94 <= 57343;
  } else {
    return 0;
  }
}

int32_t _M0MPC16uint166UInt1622is__leading__surrogate(int32_t _M0L4selfS93) {
  #line 28 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uint16_char.mbt"
  if (_M0L4selfS93 >= 55296) {
    return _M0L4selfS93 <= 56319;
  } else {
    return 0;
  }
}

moonbit_string_t _M0FPB14base64__encode(moonbit_bytes_t _M0L4dataS74) {
  struct _M0TPB13StringBuilder* _M0L3bufS72;
  int32_t _M0L3lenS73;
  int32_t _M0L3remS75;
  int32_t _M0L1iS76;
  #line 61 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  #line 63 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  _M0L3bufS72 = _M0MPB13StringBuilder11new_2einner(0);
  _M0L3lenS73 = Moonbit_array_length(_M0L4dataS74);
  _M0L3remS75 = _M0L3lenS73 % 3;
  _M0L1iS76 = 0;
  while (1) {
    int32_t _M0L6_2atmpS952 = _M0L3lenS73 - _M0L3remS75;
    if (_M0L1iS76 < _M0L6_2atmpS952) {
      int32_t _M0L6_2atmpS974;
      int32_t _M0L2b0S77;
      int32_t _M0L6_2atmpS973;
      int32_t _M0L6_2atmpS972;
      int32_t _M0L2b1S78;
      int32_t _M0L6_2atmpS971;
      int32_t _M0L6_2atmpS970;
      int32_t _M0L2b2S79;
      int32_t _M0L6_2atmpS969;
      int32_t _M0L6_2atmpS968;
      int32_t _M0L2x0S80;
      int32_t _M0L6_2atmpS967;
      int32_t _M0L6_2atmpS964;
      int32_t _M0L6_2atmpS966;
      int32_t _M0L6_2atmpS965;
      int32_t _M0L6_2atmpS963;
      int32_t _M0L2x1S81;
      int32_t _M0L6_2atmpS962;
      int32_t _M0L6_2atmpS959;
      int32_t _M0L6_2atmpS961;
      int32_t _M0L6_2atmpS960;
      int32_t _M0L6_2atmpS958;
      int32_t _M0L2x2S82;
      int32_t _M0L6_2atmpS957;
      int32_t _M0L2x3S83;
      int32_t _M0L6_2atmpS953;
      int32_t _M0L6_2atmpS954;
      int32_t _M0L6_2atmpS955;
      int32_t _M0L6_2atmpS956;
      int32_t _M0L6_2atmpS975;
      if (_M0L1iS76 < 0 || _M0L1iS76 >= Moonbit_array_length(_M0L4dataS74)) {
        #line 67 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
        moonbit_panic();
      }
      _M0L6_2atmpS974 = (int32_t)_M0L4dataS74[_M0L1iS76];
      _M0L2b0S77 = (int32_t)_M0L6_2atmpS974;
      _M0L6_2atmpS973 = _M0L1iS76 + 1;
      if (
        _M0L6_2atmpS973 < 0
        || _M0L6_2atmpS973 >= Moonbit_array_length(_M0L4dataS74)
      ) {
        #line 68 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
        moonbit_panic();
      }
      _M0L6_2atmpS972 = (int32_t)_M0L4dataS74[_M0L6_2atmpS973];
      _M0L2b1S78 = (int32_t)_M0L6_2atmpS972;
      _M0L6_2atmpS971 = _M0L1iS76 + 2;
      if (
        _M0L6_2atmpS971 < 0
        || _M0L6_2atmpS971 >= Moonbit_array_length(_M0L4dataS74)
      ) {
        #line 69 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
        moonbit_panic();
      }
      _M0L6_2atmpS970 = (int32_t)_M0L4dataS74[_M0L6_2atmpS971];
      _M0L2b2S79 = (int32_t)_M0L6_2atmpS970;
      _M0L6_2atmpS969 = _M0L2b0S77 & 252;
      _M0L6_2atmpS968 = _M0L6_2atmpS969 >> 2;
      if (
        _M0L6_2atmpS968 < 0
        || _M0L6_2atmpS968
           >= Moonbit_array_length(_M0FPB14base64__encodeN6base64S1741)
      ) {
        #line 70 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
        moonbit_panic();
      }
      _M0L2x0S80 = _M0FPB14base64__encodeN6base64S1741[_M0L6_2atmpS968];
      _M0L6_2atmpS967 = _M0L2b0S77 & 3;
      _M0L6_2atmpS964 = _M0L6_2atmpS967 << 4;
      _M0L6_2atmpS966 = _M0L2b1S78 & 240;
      _M0L6_2atmpS965 = _M0L6_2atmpS966 >> 4;
      _M0L6_2atmpS963 = _M0L6_2atmpS964 | _M0L6_2atmpS965;
      if (
        _M0L6_2atmpS963 < 0
        || _M0L6_2atmpS963
           >= Moonbit_array_length(_M0FPB14base64__encodeN6base64S1741)
      ) {
        #line 71 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
        moonbit_panic();
      }
      _M0L2x1S81 = _M0FPB14base64__encodeN6base64S1741[_M0L6_2atmpS963];
      _M0L6_2atmpS962 = _M0L2b1S78 & 15;
      _M0L6_2atmpS959 = _M0L6_2atmpS962 << 2;
      _M0L6_2atmpS961 = _M0L2b2S79 & 192;
      _M0L6_2atmpS960 = _M0L6_2atmpS961 >> 6;
      _M0L6_2atmpS958 = _M0L6_2atmpS959 | _M0L6_2atmpS960;
      if (
        _M0L6_2atmpS958 < 0
        || _M0L6_2atmpS958
           >= Moonbit_array_length(_M0FPB14base64__encodeN6base64S1741)
      ) {
        #line 72 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
        moonbit_panic();
      }
      _M0L2x2S82 = _M0FPB14base64__encodeN6base64S1741[_M0L6_2atmpS958];
      _M0L6_2atmpS957 = _M0L2b2S79 & 63;
      if (
        _M0L6_2atmpS957 < 0
        || _M0L6_2atmpS957
           >= Moonbit_array_length(_M0FPB14base64__encodeN6base64S1741)
      ) {
        #line 73 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
        moonbit_panic();
      }
      _M0L2x3S83 = _M0FPB14base64__encodeN6base64S1741[_M0L6_2atmpS957];
      #line 74 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      _M0L6_2atmpS953 = _M0MPC14byte4Byte8to__char(_M0L2x0S80);
      moonbit_incref(_M0L3bufS72);
      #line 74 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      _M0IPB13StringBuilderPB6Logger11write__char(_M0L3bufS72, _M0L6_2atmpS953);
      #line 75 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      _M0L6_2atmpS954 = _M0MPC14byte4Byte8to__char(_M0L2x1S81);
      moonbit_incref(_M0L3bufS72);
      #line 75 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      _M0IPB13StringBuilderPB6Logger11write__char(_M0L3bufS72, _M0L6_2atmpS954);
      #line 76 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      _M0L6_2atmpS955 = _M0MPC14byte4Byte8to__char(_M0L2x2S82);
      moonbit_incref(_M0L3bufS72);
      #line 76 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      _M0IPB13StringBuilderPB6Logger11write__char(_M0L3bufS72, _M0L6_2atmpS955);
      #line 77 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      _M0L6_2atmpS956 = _M0MPC14byte4Byte8to__char(_M0L2x3S83);
      moonbit_incref(_M0L3bufS72);
      #line 77 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      _M0IPB13StringBuilderPB6Logger11write__char(_M0L3bufS72, _M0L6_2atmpS956);
      _M0L6_2atmpS975 = _M0L1iS76 + 3;
      _M0L1iS76 = _M0L6_2atmpS975;
      continue;
    }
    break;
  }
  if (_M0L3remS75 == 1) {
    int32_t _M0L6_2atmpS983 = _M0L3lenS73 - 1;
    int32_t _M0L6_2atmpS982;
    int32_t _M0L2b0S85;
    int32_t _M0L6_2atmpS981;
    int32_t _M0L6_2atmpS980;
    int32_t _M0L2x0S86;
    int32_t _M0L6_2atmpS979;
    int32_t _M0L6_2atmpS978;
    int32_t _M0L2x1S87;
    int32_t _M0L6_2atmpS976;
    int32_t _M0L6_2atmpS977;
    if (
      _M0L6_2atmpS983 < 0
      || _M0L6_2atmpS983 >= Moonbit_array_length(_M0L4dataS74)
    ) {
      #line 80 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      moonbit_panic();
    }
    _M0L6_2atmpS982 = (int32_t)_M0L4dataS74[_M0L6_2atmpS983];
    moonbit_decref(_M0L4dataS74);
    _M0L2b0S85 = (int32_t)_M0L6_2atmpS982;
    _M0L6_2atmpS981 = _M0L2b0S85 & 252;
    _M0L6_2atmpS980 = _M0L6_2atmpS981 >> 2;
    if (
      _M0L6_2atmpS980 < 0
      || _M0L6_2atmpS980
         >= Moonbit_array_length(_M0FPB14base64__encodeN6base64S1741)
    ) {
      #line 81 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      moonbit_panic();
    }
    _M0L2x0S86 = _M0FPB14base64__encodeN6base64S1741[_M0L6_2atmpS980];
    _M0L6_2atmpS979 = _M0L2b0S85 & 3;
    _M0L6_2atmpS978 = _M0L6_2atmpS979 << 4;
    if (
      _M0L6_2atmpS978 < 0
      || _M0L6_2atmpS978
         >= Moonbit_array_length(_M0FPB14base64__encodeN6base64S1741)
    ) {
      #line 82 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      moonbit_panic();
    }
    _M0L2x1S87 = _M0FPB14base64__encodeN6base64S1741[_M0L6_2atmpS978];
    #line 83 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS976 = _M0MPC14byte4Byte8to__char(_M0L2x0S86);
    moonbit_incref(_M0L3bufS72);
    #line 83 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0IPB13StringBuilderPB6Logger11write__char(_M0L3bufS72, _M0L6_2atmpS976);
    #line 84 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS977 = _M0MPC14byte4Byte8to__char(_M0L2x1S87);
    moonbit_incref(_M0L3bufS72);
    #line 84 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0IPB13StringBuilderPB6Logger11write__char(_M0L3bufS72, _M0L6_2atmpS977);
    moonbit_incref(_M0L3bufS72);
    #line 85 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0IPB13StringBuilderPB6Logger11write__char(_M0L3bufS72, 61);
    moonbit_incref(_M0L3bufS72);
    #line 86 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0IPB13StringBuilderPB6Logger11write__char(_M0L3bufS72, 61);
  } else if (_M0L3remS75 == 2) {
    int32_t _M0L6_2atmpS999 = _M0L3lenS73 - 2;
    int32_t _M0L6_2atmpS998;
    int32_t _M0L2b0S88;
    int32_t _M0L6_2atmpS997;
    int32_t _M0L6_2atmpS996;
    int32_t _M0L2b1S89;
    int32_t _M0L6_2atmpS995;
    int32_t _M0L6_2atmpS994;
    int32_t _M0L2x0S90;
    int32_t _M0L6_2atmpS993;
    int32_t _M0L6_2atmpS990;
    int32_t _M0L6_2atmpS992;
    int32_t _M0L6_2atmpS991;
    int32_t _M0L6_2atmpS989;
    int32_t _M0L2x1S91;
    int32_t _M0L6_2atmpS988;
    int32_t _M0L6_2atmpS987;
    int32_t _M0L2x2S92;
    int32_t _M0L6_2atmpS984;
    int32_t _M0L6_2atmpS985;
    int32_t _M0L6_2atmpS986;
    if (
      _M0L6_2atmpS999 < 0
      || _M0L6_2atmpS999 >= Moonbit_array_length(_M0L4dataS74)
    ) {
      #line 88 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      moonbit_panic();
    }
    _M0L6_2atmpS998 = (int32_t)_M0L4dataS74[_M0L6_2atmpS999];
    _M0L2b0S88 = (int32_t)_M0L6_2atmpS998;
    _M0L6_2atmpS997 = _M0L3lenS73 - 1;
    if (
      _M0L6_2atmpS997 < 0
      || _M0L6_2atmpS997 >= Moonbit_array_length(_M0L4dataS74)
    ) {
      #line 89 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      moonbit_panic();
    }
    _M0L6_2atmpS996 = (int32_t)_M0L4dataS74[_M0L6_2atmpS997];
    moonbit_decref(_M0L4dataS74);
    _M0L2b1S89 = (int32_t)_M0L6_2atmpS996;
    _M0L6_2atmpS995 = _M0L2b0S88 & 252;
    _M0L6_2atmpS994 = _M0L6_2atmpS995 >> 2;
    if (
      _M0L6_2atmpS994 < 0
      || _M0L6_2atmpS994
         >= Moonbit_array_length(_M0FPB14base64__encodeN6base64S1741)
    ) {
      #line 90 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      moonbit_panic();
    }
    _M0L2x0S90 = _M0FPB14base64__encodeN6base64S1741[_M0L6_2atmpS994];
    _M0L6_2atmpS993 = _M0L2b0S88 & 3;
    _M0L6_2atmpS990 = _M0L6_2atmpS993 << 4;
    _M0L6_2atmpS992 = _M0L2b1S89 & 240;
    _M0L6_2atmpS991 = _M0L6_2atmpS992 >> 4;
    _M0L6_2atmpS989 = _M0L6_2atmpS990 | _M0L6_2atmpS991;
    if (
      _M0L6_2atmpS989 < 0
      || _M0L6_2atmpS989
         >= Moonbit_array_length(_M0FPB14base64__encodeN6base64S1741)
    ) {
      #line 91 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      moonbit_panic();
    }
    _M0L2x1S91 = _M0FPB14base64__encodeN6base64S1741[_M0L6_2atmpS989];
    _M0L6_2atmpS988 = _M0L2b1S89 & 15;
    _M0L6_2atmpS987 = _M0L6_2atmpS988 << 2;
    if (
      _M0L6_2atmpS987 < 0
      || _M0L6_2atmpS987
         >= Moonbit_array_length(_M0FPB14base64__encodeN6base64S1741)
    ) {
      #line 92 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
      moonbit_panic();
    }
    _M0L2x2S92 = _M0FPB14base64__encodeN6base64S1741[_M0L6_2atmpS987];
    #line 93 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS984 = _M0MPC14byte4Byte8to__char(_M0L2x0S90);
    moonbit_incref(_M0L3bufS72);
    #line 93 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0IPB13StringBuilderPB6Logger11write__char(_M0L3bufS72, _M0L6_2atmpS984);
    #line 94 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS985 = _M0MPC14byte4Byte8to__char(_M0L2x1S91);
    moonbit_incref(_M0L3bufS72);
    #line 94 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0IPB13StringBuilderPB6Logger11write__char(_M0L3bufS72, _M0L6_2atmpS985);
    #line 95 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0L6_2atmpS986 = _M0MPC14byte4Byte8to__char(_M0L2x2S92);
    moonbit_incref(_M0L3bufS72);
    #line 95 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0IPB13StringBuilderPB6Logger11write__char(_M0L3bufS72, _M0L6_2atmpS986);
    moonbit_incref(_M0L3bufS72);
    #line 96 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
    _M0IPB13StringBuilderPB6Logger11write__char(_M0L3bufS72, 61);
  } else {
    moonbit_decref(_M0L4dataS74);
  }
  #line 98 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  return _M0MPB13StringBuilder10to__string(_M0L3bufS72);
}

int32_t _M0IPB13StringBuilderPB6Logger11write__char(
  struct _M0TPB13StringBuilder* _M0L4selfS70,
  int32_t _M0L2chS69
) {
  uint32_t _M0L4codeS68;
  #line 90 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  #line 91 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L4codeS68 = _M0MPC14char4Char8to__uint(_M0L2chS69);
  if (_M0L4codeS68 <= 65535u) {
    int32_t _M0L3lenS931 = _M0L4selfS70->$1;
    int32_t _M0L6_2atmpS930 = _M0L3lenS931 + 1;
    uint16_t* _M0L4dataS932;
    int32_t _M0L3lenS933;
    int32_t _M0L6_2atmpS934;
    int32_t _M0L3lenS936;
    int32_t _M0L6_2atmpS935;
    moonbit_incref(_M0L4selfS70);
    #line 93 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0MPB13StringBuilder19grow__if__necessary(_M0L4selfS70, _M0L6_2atmpS930);
    _M0L4dataS932 = _M0L4selfS70->$0;
    _M0L3lenS933 = _M0L4selfS70->$1;
    moonbit_incref(_M0L4dataS932);
    #line 94 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0L6_2atmpS934 = _M0MPC14uint4UInt10to__uint16(_M0L4codeS68);
    if (
      _M0L3lenS933 < 0 || _M0L3lenS933 >= Moonbit_array_length(_M0L4dataS932)
    ) {
      #line 94 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
      moonbit_panic();
    }
    _M0L4dataS932[_M0L3lenS933] = _M0L6_2atmpS934;
    moonbit_decref(_M0L4dataS932);
    _M0L3lenS936 = _M0L4selfS70->$1;
    _M0L6_2atmpS935 = _M0L3lenS936 + 1;
    _M0L4selfS70->$1 = _M0L6_2atmpS935;
    moonbit_decref(_M0L4selfS70);
  } else if (_M0L4codeS68 <= 1114111u) {
    int32_t _M0L3lenS938 = _M0L4selfS70->$1;
    int32_t _M0L6_2atmpS937 = _M0L3lenS938 + 2;
    uint32_t _M0L4codeS71;
    uint16_t* _M0L4dataS939;
    int32_t _M0L3lenS940;
    uint32_t _M0L6_2atmpS943;
    uint32_t _M0L6_2atmpS942;
    int32_t _M0L6_2atmpS941;
    uint16_t* _M0L4dataS944;
    int32_t _M0L3lenS949;
    int32_t _M0L6_2atmpS945;
    uint32_t _M0L6_2atmpS948;
    uint32_t _M0L6_2atmpS947;
    int32_t _M0L6_2atmpS946;
    int32_t _M0L3lenS951;
    int32_t _M0L6_2atmpS950;
    moonbit_incref(_M0L4selfS70);
    #line 97 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0MPB13StringBuilder19grow__if__necessary(_M0L4selfS70, _M0L6_2atmpS937);
    _M0L4codeS71 = _M0L4codeS68 - 65536u;
    _M0L4dataS939 = _M0L4selfS70->$0;
    _M0L3lenS940 = _M0L4selfS70->$1;
    _M0L6_2atmpS943 = _M0L4codeS71 >> 10;
    _M0L6_2atmpS942 = 55296u + _M0L6_2atmpS943;
    moonbit_incref(_M0L4dataS939);
    #line 99 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0L6_2atmpS941 = _M0MPC14uint4UInt10to__uint16(_M0L6_2atmpS942);
    if (
      _M0L3lenS940 < 0 || _M0L3lenS940 >= Moonbit_array_length(_M0L4dataS939)
    ) {
      #line 99 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
      moonbit_panic();
    }
    _M0L4dataS939[_M0L3lenS940] = _M0L6_2atmpS941;
    moonbit_decref(_M0L4dataS939);
    _M0L4dataS944 = _M0L4selfS70->$0;
    _M0L3lenS949 = _M0L4selfS70->$1;
    _M0L6_2atmpS945 = _M0L3lenS949 + 1;
    _M0L6_2atmpS948 = _M0L4codeS71 & 1023u;
    _M0L6_2atmpS947 = 56320u + _M0L6_2atmpS948;
    moonbit_incref(_M0L4dataS944);
    #line 100 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0L6_2atmpS946 = _M0MPC14uint4UInt10to__uint16(_M0L6_2atmpS947);
    if (
      _M0L6_2atmpS945 < 0
      || _M0L6_2atmpS945 >= Moonbit_array_length(_M0L4dataS944)
    ) {
      #line 100 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
      moonbit_panic();
    }
    _M0L4dataS944[_M0L6_2atmpS945] = _M0L6_2atmpS946;
    moonbit_decref(_M0L4dataS944);
    _M0L3lenS951 = _M0L4selfS70->$1;
    _M0L6_2atmpS950 = _M0L3lenS951 + 2;
    _M0L4selfS70->$1 = _M0L6_2atmpS950;
    moonbit_decref(_M0L4selfS70);
  } else {
    moonbit_decref(_M0L4selfS70);
    #line 103 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0FPC15abort5abortGuE((moonbit_string_t)moonbit_string_literal_73.data);
  }
  return 0;
}

int32_t _M0MPB13StringBuilder19grow__if__necessary(
  struct _M0TPB13StringBuilder* _M0L4selfS62,
  int32_t _M0L8requiredS63
) {
  uint16_t* _M0L4dataS929;
  int32_t _M0L12current__lenS61;
  int32_t _M0L13enough__spaceS64;
  int32_t _M0L13enough__spaceS65;
  int32_t _M0L6_2atmpS927;
  uint16_t* _M0L9new__dataS67;
  uint16_t* _M0L4dataS925;
  int32_t _M0L3lenS926;
  uint16_t* _M0L6_2aoldS1979;
  #line 45 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L4dataS929 = _M0L4selfS62->$0;
  _M0L12current__lenS61 = Moonbit_array_length(_M0L4dataS929);
  if (_M0L8requiredS63 <= _M0L12current__lenS61) {
    moonbit_decref(_M0L4selfS62);
    return 0;
  }
  _M0L13enough__spaceS65 = _M0L12current__lenS61;
  while (1) {
    if (_M0L13enough__spaceS65 < _M0L8requiredS63) {
      int32_t _M0L6_2atmpS928 = _M0L13enough__spaceS65 * 2;
      _M0L13enough__spaceS65 = _M0L6_2atmpS928;
      continue;
    } else {
      _M0L13enough__spaceS64 = _M0L13enough__spaceS65;
    }
    break;
  }
  #line 60 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L6_2atmpS927 = _M0IPC16uint166UInt16PB7Default7default();
  _M0L9new__dataS67
  = (uint16_t*)moonbit_make_string(_M0L13enough__spaceS64, _M0L6_2atmpS927);
  _M0L4dataS925 = _M0L4selfS62->$0;
  _M0L3lenS926 = _M0L4selfS62->$1;
  moonbit_incref(_M0L4dataS925);
  moonbit_incref(_M0L9new__dataS67);
  #line 61 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0MPC15array10FixedArray12unsafe__blitGkE(_M0L9new__dataS67, 0, _M0L4dataS925, 0, _M0L3lenS926);
  _M0L6_2aoldS1979 = _M0L4selfS62->$0;
  moonbit_decref(_M0L6_2aoldS1979);
  _M0L4selfS62->$0 = _M0L9new__dataS67;
  moonbit_decref(_M0L4selfS62);
  return 0;
}

int32_t _M0MPC14uint4UInt10to__uint16(uint32_t _M0L4selfS60) {
  int32_t _M0L6_2atmpS924;
  #line 2675 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\intrinsics.mbt"
  _M0L6_2atmpS924 = *(int32_t*)&_M0L4selfS60;
  return (uint16_t)_M0L6_2atmpS924;
}

uint32_t _M0MPC14char4Char8to__uint(int32_t _M0L4selfS59) {
  int32_t _M0L6_2atmpS923;
  #line 1254 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\intrinsics.mbt"
  _M0L6_2atmpS923 = _M0L4selfS59;
  return *(uint32_t*)&_M0L6_2atmpS923;
}

moonbit_string_t _M0MPB13StringBuilder10to__string(
  struct _M0TPB13StringBuilder* _M0L4selfS57
) {
  int32_t _M0L3lenS915;
  uint16_t* _M0L4dataS917;
  int32_t _M0L6_2atmpS916;
  #line 143 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L3lenS915 = _M0L4selfS57->$1;
  _M0L4dataS917 = _M0L4selfS57->$0;
  _M0L6_2atmpS916 = Moonbit_array_length(_M0L4dataS917);
  if (_M0L3lenS915 == _M0L6_2atmpS916) {
    uint16_t* _M0L8_2afieldS1982 = _M0L4selfS57->$0;
    int32_t _M0L6_2acntS2055 = Moonbit_object_header(_M0L4selfS57)->rc;
    uint16_t* _M0L4dataS918;
    if (_M0L6_2acntS2055 > 1) {
      int32_t _M0L11_2anew__cntS2056 = _M0L6_2acntS2055 - 1;
      Moonbit_object_header(_M0L4selfS57)->rc = _M0L11_2anew__cntS2056;
      moonbit_incref(_M0L8_2afieldS1982);
    } else if (_M0L6_2acntS2055 == 1) {
      #line 145 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
      moonbit_free(_M0L4selfS57);
    }
    _M0L4dataS918 = _M0L8_2afieldS1982;
    return _M0L4dataS918;
  } else {
    int32_t _M0L3lenS921 = _M0L4selfS57->$1;
    int32_t _M0L6_2atmpS922;
    uint16_t* _M0L4dataS58;
    uint16_t* _M0L4dataS919;
    int32_t _M0L3lenS920;
    int32_t _M0L6_2acntS2057;
    #line 147 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0L6_2atmpS922 = _M0IPC16uint166UInt16PB7Default7default();
    _M0L4dataS58
    = (uint16_t*)moonbit_make_string(_M0L3lenS921, _M0L6_2atmpS922);
    _M0L4dataS919 = _M0L4selfS57->$0;
    _M0L3lenS920 = _M0L4selfS57->$1;
    _M0L6_2acntS2057 = Moonbit_object_header(_M0L4selfS57)->rc;
    if (_M0L6_2acntS2057 > 1) {
      int32_t _M0L11_2anew__cntS2058 = _M0L6_2acntS2057 - 1;
      Moonbit_object_header(_M0L4selfS57)->rc = _M0L11_2anew__cntS2058;
      moonbit_incref(_M0L4dataS919);
    } else if (_M0L6_2acntS2057 == 1) {
      #line 148 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
      moonbit_free(_M0L4selfS57);
    }
    moonbit_incref(_M0L4dataS58);
    #line 148 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0MPC15array10FixedArray12unsafe__blitGkE(_M0L4dataS58, 0, _M0L4dataS919, 0, _M0L3lenS920);
    return _M0L4dataS58;
  }
}

int32_t _M0IPC16uint166UInt16PB7Default7default() {
  #line 153 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uint16_char.mbt"
  return 0;
}

struct _M0TPB13StringBuilder* _M0MPB13StringBuilder11new_2einner(
  int32_t _M0L10size__hintS55
) {
  int32_t _M0L7initialS54;
  uint16_t* _M0L4dataS56;
  struct _M0TPB13StringBuilder* _block_2205;
  #line 32 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  if (_M0L10size__hintS55 < 1) {
    _M0L7initialS54 = 1;
  } else {
    int32_t _M0L6_2atmpS914 = _M0L10size__hintS55 + 1;
    _M0L7initialS54 = _M0L6_2atmpS914 / 2;
  }
  _M0L4dataS56 = (uint16_t*)moonbit_make_string(_M0L7initialS54, 0);
  _block_2205
  = (struct _M0TPB13StringBuilder*)moonbit_malloc(sizeof(struct _M0TPB13StringBuilder));
  Moonbit_object_header(_block_2205)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB13StringBuilder, $0) >> 2, 1, 0);
  _block_2205->$0 = _M0L4dataS56;
  _block_2205->$1 = 0;
  return _block_2205;
}

int32_t _M0MPC14byte4Byte8to__char(int32_t _M0L4selfS53) {
  int32_t _M0L6_2atmpS913;
  #line 1867 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\intrinsics.mbt"
  _M0L6_2atmpS913 = (int32_t)_M0L4selfS53;
  return _M0L6_2atmpS913;
}

int32_t _M0MPB18UninitializedArray12unsafe__blitGsE(
  moonbit_string_t* _M0L3dstS43,
  int32_t _M0L11dst__offsetS44,
  moonbit_string_t* _M0L3srcS45,
  int32_t _M0L11src__offsetS46,
  int32_t _M0L3lenS47
) {
  #line 104 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uninitialized_array.mbt"
  #line 113 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uninitialized_array.mbt"
  _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGsEE(_M0L3dstS43, _M0L11dst__offsetS44, _M0L3srcS45, _M0L11src__offsetS46, _M0L3lenS47);
  return 0;
}

int32_t _M0MPB18UninitializedArray12unsafe__blitGUsiEE(
  struct _M0TUsiE** _M0L3dstS48,
  int32_t _M0L11dst__offsetS49,
  struct _M0TUsiE** _M0L3srcS50,
  int32_t _M0L11src__offsetS51,
  int32_t _M0L3lenS52
) {
  #line 104 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uninitialized_array.mbt"
  #line 113 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uninitialized_array.mbt"
  _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGUsiEEE(_M0L3dstS48, _M0L11dst__offsetS49, _M0L3srcS50, _M0L11src__offsetS51, _M0L3lenS52);
  return 0;
}

int32_t _M0MPC15array10FixedArray12unsafe__blitGkE(
  uint16_t* _M0L3dstS16,
  int32_t _M0L11dst__offsetS18,
  uint16_t* _M0L3srcS17,
  int32_t _M0L11src__offsetS19,
  int32_t _M0L3lenS21
) {
  int32_t _if__result_2206;
  #line 38 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
  if (_M0L3dstS16 == _M0L3srcS17) {
    _if__result_2206 = _M0L11dst__offsetS18 < _M0L11src__offsetS19;
  } else {
    _if__result_2206 = 0;
  }
  if (_if__result_2206) {
    int32_t _M0L1iS20 = 0;
    while (1) {
      if (_M0L1iS20 < _M0L3lenS21) {
        int32_t _M0L6_2atmpS886 = _M0L11dst__offsetS18 + _M0L1iS20;
        int32_t _M0L6_2atmpS888 = _M0L11src__offsetS19 + _M0L1iS20;
        int32_t _M0L6_2atmpS887;
        int32_t _M0L6_2atmpS889;
        if (
          _M0L6_2atmpS888 < 0
          || _M0L6_2atmpS888 >= Moonbit_array_length(_M0L3srcS17)
        ) {
          #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2atmpS887 = (int32_t)_M0L3srcS17[_M0L6_2atmpS888];
        if (
          _M0L6_2atmpS886 < 0
          || _M0L6_2atmpS886 >= Moonbit_array_length(_M0L3dstS16)
        ) {
          #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L3dstS16[_M0L6_2atmpS886] = _M0L6_2atmpS887;
        _M0L6_2atmpS889 = _M0L1iS20 + 1;
        _M0L1iS20 = _M0L6_2atmpS889;
        continue;
      } else {
        moonbit_decref(_M0L3srcS17);
        moonbit_decref(_M0L3dstS16);
      }
      break;
    }
  } else {
    int32_t _M0L6_2atmpS894 = _M0L3lenS21 - 1;
    int32_t _M0L1iS23 = _M0L6_2atmpS894;
    while (1) {
      if (_M0L1iS23 >= 0) {
        int32_t _M0L6_2atmpS890 = _M0L11dst__offsetS18 + _M0L1iS23;
        int32_t _M0L6_2atmpS892 = _M0L11src__offsetS19 + _M0L1iS23;
        int32_t _M0L6_2atmpS891;
        int32_t _M0L6_2atmpS893;
        if (
          _M0L6_2atmpS892 < 0
          || _M0L6_2atmpS892 >= Moonbit_array_length(_M0L3srcS17)
        ) {
          #line 53 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2atmpS891 = (int32_t)_M0L3srcS17[_M0L6_2atmpS892];
        if (
          _M0L6_2atmpS890 < 0
          || _M0L6_2atmpS890 >= Moonbit_array_length(_M0L3dstS16)
        ) {
          #line 53 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L3dstS16[_M0L6_2atmpS890] = _M0L6_2atmpS891;
        _M0L6_2atmpS893 = _M0L1iS23 - 1;
        _M0L1iS23 = _M0L6_2atmpS893;
        continue;
      } else {
        moonbit_decref(_M0L3srcS17);
        moonbit_decref(_M0L3dstS16);
      }
      break;
    }
  }
  return 0;
}

int32_t _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGsEE(
  moonbit_string_t* _M0L3dstS25,
  int32_t _M0L11dst__offsetS27,
  moonbit_string_t* _M0L3srcS26,
  int32_t _M0L11src__offsetS28,
  int32_t _M0L3lenS30
) {
  int32_t _if__result_2209;
  #line 38 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
  if (_M0L3dstS25 == _M0L3srcS26) {
    _if__result_2209 = _M0L11dst__offsetS27 < _M0L11src__offsetS28;
  } else {
    _if__result_2209 = 0;
  }
  if (_if__result_2209) {
    int32_t _M0L1iS29 = 0;
    while (1) {
      if (_M0L1iS29 < _M0L3lenS30) {
        int32_t _M0L6_2atmpS895 = _M0L11dst__offsetS27 + _M0L1iS29;
        int32_t _M0L6_2atmpS897 = _M0L11src__offsetS28 + _M0L1iS29;
        moonbit_string_t _M0L6_2atmpS896;
        moonbit_string_t _M0L6_2aoldS1985;
        int32_t _M0L6_2atmpS898;
        if (
          _M0L6_2atmpS897 < 0
          || _M0L6_2atmpS897 >= Moonbit_array_length(_M0L3srcS26)
        ) {
          #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2atmpS896 = (moonbit_string_t)_M0L3srcS26[_M0L6_2atmpS897];
        if (
          _M0L6_2atmpS895 < 0
          || _M0L6_2atmpS895 >= Moonbit_array_length(_M0L3dstS25)
        ) {
          #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2aoldS1985 = (moonbit_string_t)_M0L3dstS25[_M0L6_2atmpS895];
        moonbit_incref(_M0L6_2atmpS896);
        moonbit_decref(_M0L6_2aoldS1985);
        _M0L3dstS25[_M0L6_2atmpS895] = _M0L6_2atmpS896;
        _M0L6_2atmpS898 = _M0L1iS29 + 1;
        _M0L1iS29 = _M0L6_2atmpS898;
        continue;
      } else {
        moonbit_decref(_M0L3srcS26);
        moonbit_decref(_M0L3dstS25);
      }
      break;
    }
  } else {
    int32_t _M0L6_2atmpS903 = _M0L3lenS30 - 1;
    int32_t _M0L1iS32 = _M0L6_2atmpS903;
    while (1) {
      if (_M0L1iS32 >= 0) {
        int32_t _M0L6_2atmpS899 = _M0L11dst__offsetS27 + _M0L1iS32;
        int32_t _M0L6_2atmpS901 = _M0L11src__offsetS28 + _M0L1iS32;
        moonbit_string_t _M0L6_2atmpS900;
        moonbit_string_t _M0L6_2aoldS1987;
        int32_t _M0L6_2atmpS902;
        if (
          _M0L6_2atmpS901 < 0
          || _M0L6_2atmpS901 >= Moonbit_array_length(_M0L3srcS26)
        ) {
          #line 53 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2atmpS900 = (moonbit_string_t)_M0L3srcS26[_M0L6_2atmpS901];
        if (
          _M0L6_2atmpS899 < 0
          || _M0L6_2atmpS899 >= Moonbit_array_length(_M0L3dstS25)
        ) {
          #line 53 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2aoldS1987 = (moonbit_string_t)_M0L3dstS25[_M0L6_2atmpS899];
        moonbit_incref(_M0L6_2atmpS900);
        moonbit_decref(_M0L6_2aoldS1987);
        _M0L3dstS25[_M0L6_2atmpS899] = _M0L6_2atmpS900;
        _M0L6_2atmpS902 = _M0L1iS32 - 1;
        _M0L1iS32 = _M0L6_2atmpS902;
        continue;
      } else {
        moonbit_decref(_M0L3srcS26);
        moonbit_decref(_M0L3dstS25);
      }
      break;
    }
  }
  return 0;
}

int32_t _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGUsiEEE(
  struct _M0TUsiE** _M0L3dstS34,
  int32_t _M0L11dst__offsetS36,
  struct _M0TUsiE** _M0L3srcS35,
  int32_t _M0L11src__offsetS37,
  int32_t _M0L3lenS39
) {
  int32_t _if__result_2212;
  #line 38 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
  if (_M0L3dstS34 == _M0L3srcS35) {
    _if__result_2212 = _M0L11dst__offsetS36 < _M0L11src__offsetS37;
  } else {
    _if__result_2212 = 0;
  }
  if (_if__result_2212) {
    int32_t _M0L1iS38 = 0;
    while (1) {
      if (_M0L1iS38 < _M0L3lenS39) {
        int32_t _M0L6_2atmpS904 = _M0L11dst__offsetS36 + _M0L1iS38;
        int32_t _M0L6_2atmpS906 = _M0L11src__offsetS37 + _M0L1iS38;
        struct _M0TUsiE* _M0L6_2atmpS905;
        struct _M0TUsiE* _M0L6_2aoldS1989;
        int32_t _M0L6_2atmpS907;
        if (
          _M0L6_2atmpS906 < 0
          || _M0L6_2atmpS906 >= Moonbit_array_length(_M0L3srcS35)
        ) {
          #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2atmpS905 = (struct _M0TUsiE*)_M0L3srcS35[_M0L6_2atmpS906];
        if (
          _M0L6_2atmpS904 < 0
          || _M0L6_2atmpS904 >= Moonbit_array_length(_M0L3dstS34)
        ) {
          #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2aoldS1989 = (struct _M0TUsiE*)_M0L3dstS34[_M0L6_2atmpS904];
        if (_M0L6_2atmpS905) {
          moonbit_incref(_M0L6_2atmpS905);
        }
        if (_M0L6_2aoldS1989) {
          moonbit_decref(_M0L6_2aoldS1989);
        }
        _M0L3dstS34[_M0L6_2atmpS904] = _M0L6_2atmpS905;
        _M0L6_2atmpS907 = _M0L1iS38 + 1;
        _M0L1iS38 = _M0L6_2atmpS907;
        continue;
      } else {
        moonbit_decref(_M0L3srcS35);
        moonbit_decref(_M0L3dstS34);
      }
      break;
    }
  } else {
    int32_t _M0L6_2atmpS912 = _M0L3lenS39 - 1;
    int32_t _M0L1iS41 = _M0L6_2atmpS912;
    while (1) {
      if (_M0L1iS41 >= 0) {
        int32_t _M0L6_2atmpS908 = _M0L11dst__offsetS36 + _M0L1iS41;
        int32_t _M0L6_2atmpS910 = _M0L11src__offsetS37 + _M0L1iS41;
        struct _M0TUsiE* _M0L6_2atmpS909;
        struct _M0TUsiE* _M0L6_2aoldS1991;
        int32_t _M0L6_2atmpS911;
        if (
          _M0L6_2atmpS910 < 0
          || _M0L6_2atmpS910 >= Moonbit_array_length(_M0L3srcS35)
        ) {
          #line 53 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2atmpS909 = (struct _M0TUsiE*)_M0L3srcS35[_M0L6_2atmpS910];
        if (
          _M0L6_2atmpS908 < 0
          || _M0L6_2atmpS908 >= Moonbit_array_length(_M0L3dstS34)
        ) {
          #line 53 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2aoldS1991 = (struct _M0TUsiE*)_M0L3dstS34[_M0L6_2atmpS908];
        if (_M0L6_2atmpS909) {
          moonbit_incref(_M0L6_2atmpS909);
        }
        if (_M0L6_2aoldS1991) {
          moonbit_decref(_M0L6_2aoldS1991);
        }
        _M0L3dstS34[_M0L6_2atmpS908] = _M0L6_2atmpS909;
        _M0L6_2atmpS911 = _M0L1iS41 - 1;
        _M0L1iS41 = _M0L6_2atmpS911;
        continue;
      } else {
        moonbit_decref(_M0L3srcS35);
        moonbit_decref(_M0L3dstS34);
      }
      break;
    }
  }
  return 0;
}

int32_t _M0MPB6Hasher13combine__uint(
  struct _M0TPB6Hasher* _M0L4selfS14,
  uint32_t _M0L5valueS15
) {
  uint32_t _M0L3accS885;
  uint32_t _M0L6_2atmpS884;
  #line 236 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0L3accS885 = _M0L4selfS14->$0;
  _M0L6_2atmpS884 = _M0L3accS885 + 4u;
  _M0L4selfS14->$0 = _M0L6_2atmpS884;
  #line 238 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0MPB6Hasher8consume4(_M0L4selfS14, _M0L5valueS15);
  return 0;
}

int32_t _M0MPB6Hasher8consume4(
  struct _M0TPB6Hasher* _M0L4selfS12,
  uint32_t _M0L5inputS13
) {
  uint32_t _M0L3accS882;
  uint32_t _M0L6_2atmpS883;
  uint32_t _M0L6_2atmpS881;
  uint32_t _M0L6_2atmpS880;
  uint32_t _M0L6_2atmpS879;
  #line 451 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0L3accS882 = _M0L4selfS12->$0;
  _M0L6_2atmpS883 = _M0L5inputS13 * 3266489917u;
  _M0L6_2atmpS881 = _M0L3accS882 + _M0L6_2atmpS883;
  #line 452 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0L6_2atmpS880 = _M0FPB4rotl(_M0L6_2atmpS881, 17);
  _M0L6_2atmpS879 = _M0L6_2atmpS880 * 668265263u;
  _M0L4selfS12->$0 = _M0L6_2atmpS879;
  moonbit_decref(_M0L4selfS12);
  return 0;
}

uint32_t _M0FPB4rotl(uint32_t _M0L1xS10, int32_t _M0L1rS11) {
  uint32_t _M0L6_2atmpS876;
  int32_t _M0L6_2atmpS878;
  uint32_t _M0L6_2atmpS877;
  #line 461 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\hasher.mbt"
  _M0L6_2atmpS876 = _M0L1xS10 << (_M0L1rS11 & 31);
  _M0L6_2atmpS878 = 32 - _M0L1rS11;
  _M0L6_2atmpS877 = _M0L1xS10 >> (_M0L6_2atmpS878 & 31);
  return _M0L6_2atmpS876 | _M0L6_2atmpS877;
}

int32_t _M0IPB7FailurePB4Show6output(
  void* _M0L10_2ax__5120S6,
  struct _M0TPB6Logger _M0L10_2ax__5121S9
) {
  struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure* _M0L10_2aFailureS7;
  moonbit_string_t _M0L8_2afieldS1993;
  int32_t _M0L6_2acntS2059;
  moonbit_string_t _M0L15_2a_2aarg__5122S8;
  #line 37 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
  _M0L10_2aFailureS7
  = (struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure*)_M0L10_2ax__5120S6;
  _M0L8_2afieldS1993 = _M0L10_2aFailureS7->$0;
  _M0L6_2acntS2059 = Moonbit_object_header(_M0L10_2aFailureS7)->rc;
  if (_M0L6_2acntS2059 > 1) {
    int32_t _M0L11_2anew__cntS2060 = _M0L6_2acntS2059 - 1;
    Moonbit_object_header(_M0L10_2aFailureS7)->rc = _M0L11_2anew__cntS2060;
    moonbit_incref(_M0L8_2afieldS1993);
  } else if (_M0L6_2acntS2059 == 1) {
    #line 37 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
    moonbit_free(_M0L10_2aFailureS7);
  }
  _M0L15_2a_2aarg__5122S8 = _M0L8_2afieldS1993;
  if (_M0L10_2ax__5121S9.$1) {
    moonbit_incref(_M0L10_2ax__5121S9.$1);
  }
  #line 37 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
  _M0L10_2ax__5121S9.$0->$method_0(_M0L10_2ax__5121S9.$1, (moonbit_string_t)moonbit_string_literal_74.data);
  if (_M0L10_2ax__5121S9.$1) {
    moonbit_incref(_M0L10_2ax__5121S9.$1);
  }
  #line 37 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
  _M0MPB6Logger13write__objectGsE(_M0L10_2ax__5121S9, _M0L15_2a_2aarg__5122S8);
  #line 37 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
  _M0L10_2ax__5121S9.$0->$method_0(_M0L10_2ax__5121S9.$1, (moonbit_string_t)moonbit_string_literal_75.data);
  return 0;
}

int32_t _M0MPB6Logger13write__objectGsE(
  struct _M0TPB6Logger _M0L4selfS5,
  moonbit_string_t _M0L3objS4
) {
  #line 148 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  #line 149 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0IPC16string6StringPB4Show6output(_M0L3objS4, _M0L4selfS5);
  return 0;
}

int32_t _M0FPC15abort5abortGuE(moonbit_string_t _M0L3msgS1) {
  #line 47 "C:\\Users\\hnlyh\\.moon\\lib\\core\\abort\\abort.mbt"
  #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\abort\\abort.mbt"
  moonbit_println(_M0L3msgS1);
  moonbit_decref(_M0L3msgS1);
  #line 50 "C:\\Users\\hnlyh\\.moon\\lib\\core\\abort\\abort.mbt"
  moonbit_panic();
  return 0;
}

int32_t _M0FPC15abort5abortGiE(moonbit_string_t _M0L3msgS2) {
  #line 47 "C:\\Users\\hnlyh\\.moon\\lib\\core\\abort\\abort.mbt"
  #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\abort\\abort.mbt"
  moonbit_println(_M0L3msgS2);
  moonbit_decref(_M0L3msgS2);
  #line 50 "C:\\Users\\hnlyh\\.moon\\lib\\core\\abort\\abort.mbt"
  moonbit_panic();
}

struct _M0TPC16string10StringView _M0FPC15abort5abortGRPC16string10StringViewE(
  moonbit_string_t _M0L3msgS3
) {
  #line 47 "C:\\Users\\hnlyh\\.moon\\lib\\core\\abort\\abort.mbt"
  #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\abort\\abort.mbt"
  moonbit_println(_M0L3msgS3);
  moonbit_decref(_M0L3msgS3);
  #line 50 "C:\\Users\\hnlyh\\.moon\\lib\\core\\abort\\abort.mbt"
  moonbit_panic();
}

moonbit_string_t _M0FP15Error10to__string(void* _M0L4_2aeS824) {
  switch (Moonbit_object_tag(_M0L4_2aeS824)) {
    case 5: {
      moonbit_decref(_M0L4_2aeS824);
      return (moonbit_string_t)moonbit_string_literal_76.data;
      break;
    }
    
    case 8: {
      moonbit_decref(_M0L4_2aeS824);
      return (moonbit_string_t)moonbit_string_literal_77.data;
      break;
    }
    
    case 3: {
      moonbit_decref(_M0L4_2aeS824);
      return (moonbit_string_t)moonbit_string_literal_78.data;
      break;
    }
    
    case 10: {
      moonbit_decref(_M0L4_2aeS824);
      return (moonbit_string_t)moonbit_string_literal_79.data;
      break;
    }
    
    case 11: {
      moonbit_decref(_M0L4_2aeS824);
      return (moonbit_string_t)moonbit_string_literal_80.data;
      break;
    }
    
    case 9: {
      moonbit_decref(_M0L4_2aeS824);
      return (moonbit_string_t)moonbit_string_literal_81.data;
      break;
    }
    
    case 0: {
      return _M0IP016_24default__implPB4Show10to__stringGRPB7FailureE(_M0L4_2aeS824);
      break;
    }
    
    case 1: {
      moonbit_decref(_M0L4_2aeS824);
      return (moonbit_string_t)moonbit_string_literal_82.data;
      break;
    }
    
    case 6: {
      moonbit_decref(_M0L4_2aeS824);
      return (moonbit_string_t)moonbit_string_literal_83.data;
      break;
    }
    
    case 4: {
      moonbit_decref(_M0L4_2aeS824);
      return (moonbit_string_t)moonbit_string_literal_84.data;
      break;
    }
    
    case 7: {
      moonbit_decref(_M0L4_2aeS824);
      return (moonbit_string_t)moonbit_string_literal_85.data;
      break;
    }
    default: {
      moonbit_decref(_M0L4_2aeS824);
      return (moonbit_string_t)moonbit_string_literal_86.data;
      break;
    }
  }
}

moonbit_string_t _M0IPC16string6StringPB4Show64to__string_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eShow(
  void* _M0L11_2aobj__ptrS846
) {
  moonbit_string_t _M0L7_2aselfS845 = (moonbit_string_t)_M0L11_2aobj__ptrS846;
  return _M0IPC16string6StringPB4Show10to__string(_M0L7_2aselfS845);
}

int32_t _M0IPC16string6StringPB4Show60output_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eShow(
  void* _M0L11_2aobj__ptrS844,
  struct _M0TPB6Logger _M0L8_2aparamS843
) {
  moonbit_string_t _M0L7_2aselfS842 = (moonbit_string_t)_M0L11_2aobj__ptrS844;
  _M0IPC16string6StringPB4Show6output(_M0L7_2aselfS842, _M0L8_2aparamS843);
  return 0;
}

int32_t _M0IPB13StringBuilderPB6Logger67write__char_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void* _M0L11_2aobj__ptrS841,
  int32_t _M0L8_2aparamS840
) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS839 =
    (struct _M0TPB13StringBuilder*)_M0L11_2aobj__ptrS841;
  _M0IPB13StringBuilderPB6Logger11write__char(_M0L7_2aselfS839, _M0L8_2aparamS840);
  return 0;
}

int32_t _M0IPB13StringBuilderPB6Logger67write__view_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void* _M0L11_2aobj__ptrS838,
  struct _M0TPC16string10StringView _M0L8_2aparamS837
) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS836 =
    (struct _M0TPB13StringBuilder*)_M0L11_2aobj__ptrS838;
  _M0IPB13StringBuilderPB6Logger11write__view(_M0L7_2aselfS836, _M0L8_2aparamS837);
  return 0;
}

int32_t _M0IP016_24default__implPB6Logger72write__substring_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLoggerGRPB13StringBuilderE(
  void* _M0L11_2aobj__ptrS835,
  moonbit_string_t _M0L8_2aparamS832,
  int32_t _M0L8_2aparamS833,
  int32_t _M0L8_2aparamS834
) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS831 =
    (struct _M0TPB13StringBuilder*)_M0L11_2aobj__ptrS835;
  _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE(_M0L7_2aselfS831, _M0L8_2aparamS832, _M0L8_2aparamS833, _M0L8_2aparamS834);
  return 0;
}

int32_t _M0IPB13StringBuilderPB6Logger69write__string_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void* _M0L11_2aobj__ptrS830,
  moonbit_string_t _M0L8_2aparamS829
) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS828 =
    (struct _M0TPB13StringBuilder*)_M0L11_2aobj__ptrS830;
  _M0IPB13StringBuilderPB6Logger13write__string(_M0L7_2aselfS828, _M0L8_2aparamS829);
  return 0;
}

void moonbit_init() {
  moonbit_string_t* _M0L6_2atmpS875 =
    (moonbit_string_t*)moonbit_make_ref_array_raw(1);
  struct _M0TUWEuQRPC15error5ErrorNsE* _M0L8_2atupleS874;
  struct _M0TUiUWEuQRPC15error5ErrorNsEE* _M0L8_2atupleS858;
  moonbit_string_t* _M0L6_2atmpS873;
  struct _M0TUWEuQRPC15error5ErrorNsE* _M0L8_2atupleS872;
  struct _M0TUiUWEuQRPC15error5ErrorNsEE* _M0L8_2atupleS859;
  moonbit_string_t* _M0L6_2atmpS871;
  struct _M0TUWEuQRPC15error5ErrorNsE* _M0L8_2atupleS870;
  struct _M0TUiUWEuQRPC15error5ErrorNsEE* _M0L8_2atupleS860;
  moonbit_string_t* _M0L6_2atmpS869;
  struct _M0TUWEuQRPC15error5ErrorNsE* _M0L8_2atupleS868;
  struct _M0TUiUWEuQRPC15error5ErrorNsEE* _M0L8_2atupleS861;
  moonbit_string_t* _M0L6_2atmpS867;
  struct _M0TUWEuQRPC15error5ErrorNsE* _M0L8_2atupleS866;
  struct _M0TUiUWEuQRPC15error5ErrorNsEE* _M0L8_2atupleS862;
  moonbit_string_t* _M0L6_2atmpS865;
  struct _M0TUWEuQRPC15error5ErrorNsE* _M0L8_2atupleS864;
  struct _M0TUiUWEuQRPC15error5ErrorNsEE* _M0L8_2atupleS863;
  struct _M0TUiUWEuQRPC15error5ErrorNsEE** _M0L7_2abindS751;
  struct _M0TUiUWEuQRPC15error5ErrorNsEE** _M0L6_2atmpS857;
  struct _M0TPB9ArrayViewGUiUWEuQRPC15error5ErrorNsEEE _M0L6_2atmpS856;
  struct _M0TPB3MapGiUWEuQRPC15error5ErrorNsEE* _M0L6_2atmpS855;
  struct _M0TUsRPB3MapGiUWEuQRPC15error5ErrorNsEEE* _M0L8_2atupleS854;
  struct _M0TUsRPB3MapGiUWEuQRPC15error5ErrorNsEEE** _M0L7_2abindS750;
  struct _M0TUsRPB3MapGiUWEuQRPC15error5ErrorNsEEE** _M0L6_2atmpS853;
  struct _M0TPB9ArrayViewGUsRPB3MapGiUWEuQRPC15error5ErrorNsEEEE _M0L6_2atmpS852;
  _M0L6_2atmpS875[0] = (moonbit_string_t)moonbit_string_literal_87.data;
  moonbit_incref(_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__0_2eclo);
  _M0L8_2atupleS874
  = (struct _M0TUWEuQRPC15error5ErrorNsE*)moonbit_malloc(sizeof(struct _M0TUWEuQRPC15error5ErrorNsE));
  Moonbit_object_header(_M0L8_2atupleS874)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TUWEuQRPC15error5ErrorNsE, $0) >> 2, 2, 0);
  _M0L8_2atupleS874->$0
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__0_2eclo;
  _M0L8_2atupleS874->$1 = _M0L6_2atmpS875;
  _M0L8_2atupleS858
  = (struct _M0TUiUWEuQRPC15error5ErrorNsEE*)moonbit_malloc(sizeof(struct _M0TUiUWEuQRPC15error5ErrorNsEE));
  Moonbit_object_header(_M0L8_2atupleS858)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TUiUWEuQRPC15error5ErrorNsEE, $1) >> 2, 1, 0);
  _M0L8_2atupleS858->$0 = 0;
  _M0L8_2atupleS858->$1 = _M0L8_2atupleS874;
  _M0L6_2atmpS873 = (moonbit_string_t*)moonbit_make_ref_array_raw(1);
  _M0L6_2atmpS873[0] = (moonbit_string_t)moonbit_string_literal_88.data;
  moonbit_incref(_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__1_2eclo);
  _M0L8_2atupleS872
  = (struct _M0TUWEuQRPC15error5ErrorNsE*)moonbit_malloc(sizeof(struct _M0TUWEuQRPC15error5ErrorNsE));
  Moonbit_object_header(_M0L8_2atupleS872)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TUWEuQRPC15error5ErrorNsE, $0) >> 2, 2, 0);
  _M0L8_2atupleS872->$0
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__1_2eclo;
  _M0L8_2atupleS872->$1 = _M0L6_2atmpS873;
  _M0L8_2atupleS859
  = (struct _M0TUiUWEuQRPC15error5ErrorNsEE*)moonbit_malloc(sizeof(struct _M0TUiUWEuQRPC15error5ErrorNsEE));
  Moonbit_object_header(_M0L8_2atupleS859)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TUiUWEuQRPC15error5ErrorNsEE, $1) >> 2, 1, 0);
  _M0L8_2atupleS859->$0 = 1;
  _M0L8_2atupleS859->$1 = _M0L8_2atupleS872;
  _M0L6_2atmpS871 = (moonbit_string_t*)moonbit_make_ref_array_raw(1);
  _M0L6_2atmpS871[0] = (moonbit_string_t)moonbit_string_literal_89.data;
  moonbit_incref(_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__2_2eclo);
  _M0L8_2atupleS870
  = (struct _M0TUWEuQRPC15error5ErrorNsE*)moonbit_malloc(sizeof(struct _M0TUWEuQRPC15error5ErrorNsE));
  Moonbit_object_header(_M0L8_2atupleS870)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TUWEuQRPC15error5ErrorNsE, $0) >> 2, 2, 0);
  _M0L8_2atupleS870->$0
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__2_2eclo;
  _M0L8_2atupleS870->$1 = _M0L6_2atmpS871;
  _M0L8_2atupleS860
  = (struct _M0TUiUWEuQRPC15error5ErrorNsEE*)moonbit_malloc(sizeof(struct _M0TUiUWEuQRPC15error5ErrorNsEE));
  Moonbit_object_header(_M0L8_2atupleS860)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TUiUWEuQRPC15error5ErrorNsEE, $1) >> 2, 1, 0);
  _M0L8_2atupleS860->$0 = 2;
  _M0L8_2atupleS860->$1 = _M0L8_2atupleS870;
  _M0L6_2atmpS869 = (moonbit_string_t*)moonbit_make_ref_array_raw(1);
  _M0L6_2atmpS869[0] = (moonbit_string_t)moonbit_string_literal_90.data;
  moonbit_incref(_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__3_2eclo);
  _M0L8_2atupleS868
  = (struct _M0TUWEuQRPC15error5ErrorNsE*)moonbit_malloc(sizeof(struct _M0TUWEuQRPC15error5ErrorNsE));
  Moonbit_object_header(_M0L8_2atupleS868)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TUWEuQRPC15error5ErrorNsE, $0) >> 2, 2, 0);
  _M0L8_2atupleS868->$0
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__3_2eclo;
  _M0L8_2atupleS868->$1 = _M0L6_2atmpS869;
  _M0L8_2atupleS861
  = (struct _M0TUiUWEuQRPC15error5ErrorNsEE*)moonbit_malloc(sizeof(struct _M0TUiUWEuQRPC15error5ErrorNsEE));
  Moonbit_object_header(_M0L8_2atupleS861)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TUiUWEuQRPC15error5ErrorNsEE, $1) >> 2, 1, 0);
  _M0L8_2atupleS861->$0 = 3;
  _M0L8_2atupleS861->$1 = _M0L8_2atupleS868;
  _M0L6_2atmpS867 = (moonbit_string_t*)moonbit_make_ref_array_raw(1);
  _M0L6_2atmpS867[0] = (moonbit_string_t)moonbit_string_literal_91.data;
  moonbit_incref(_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__4_2eclo);
  _M0L8_2atupleS866
  = (struct _M0TUWEuQRPC15error5ErrorNsE*)moonbit_malloc(sizeof(struct _M0TUWEuQRPC15error5ErrorNsE));
  Moonbit_object_header(_M0L8_2atupleS866)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TUWEuQRPC15error5ErrorNsE, $0) >> 2, 2, 0);
  _M0L8_2atupleS866->$0
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__4_2eclo;
  _M0L8_2atupleS866->$1 = _M0L6_2atmpS867;
  _M0L8_2atupleS862
  = (struct _M0TUiUWEuQRPC15error5ErrorNsEE*)moonbit_malloc(sizeof(struct _M0TUiUWEuQRPC15error5ErrorNsEE));
  Moonbit_object_header(_M0L8_2atupleS862)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TUiUWEuQRPC15error5ErrorNsEE, $1) >> 2, 1, 0);
  _M0L8_2atupleS862->$0 = 4;
  _M0L8_2atupleS862->$1 = _M0L8_2atupleS866;
  _M0L6_2atmpS865 = (moonbit_string_t*)moonbit_make_ref_array_raw(1);
  _M0L6_2atmpS865[0] = (moonbit_string_t)moonbit_string_literal_92.data;
  moonbit_incref(_M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__5_2eclo);
  _M0L8_2atupleS864
  = (struct _M0TUWEuQRPC15error5ErrorNsE*)moonbit_malloc(sizeof(struct _M0TUWEuQRPC15error5ErrorNsE));
  Moonbit_object_header(_M0L8_2atupleS864)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TUWEuQRPC15error5ErrorNsE, $0) >> 2, 2, 0);
  _M0L8_2atupleS864->$0
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors53____test__6572726f72735f7762746573742e6d6274__5_2eclo;
  _M0L8_2atupleS864->$1 = _M0L6_2atmpS865;
  _M0L8_2atupleS863
  = (struct _M0TUiUWEuQRPC15error5ErrorNsEE*)moonbit_malloc(sizeof(struct _M0TUiUWEuQRPC15error5ErrorNsEE));
  Moonbit_object_header(_M0L8_2atupleS863)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TUiUWEuQRPC15error5ErrorNsEE, $1) >> 2, 1, 0);
  _M0L8_2atupleS863->$0 = 5;
  _M0L8_2atupleS863->$1 = _M0L8_2atupleS864;
  _M0L7_2abindS751
  = (struct _M0TUiUWEuQRPC15error5ErrorNsEE**)moonbit_make_ref_array_raw(6);
  _M0L7_2abindS751[0] = _M0L8_2atupleS858;
  _M0L7_2abindS751[1] = _M0L8_2atupleS859;
  _M0L7_2abindS751[2] = _M0L8_2atupleS860;
  _M0L7_2abindS751[3] = _M0L8_2atupleS861;
  _M0L7_2abindS751[4] = _M0L8_2atupleS862;
  _M0L7_2abindS751[5] = _M0L8_2atupleS863;
  _M0L6_2atmpS857 = _M0L7_2abindS751;
  _M0L6_2atmpS856
  = (struct _M0TPB9ArrayViewGUiUWEuQRPC15error5ErrorNsEEE){
    0, 6, _M0L6_2atmpS857
  };
  #line 398 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L6_2atmpS855
  = _M0MPB3Map11from__arrayGiUWEuQRPC15error5ErrorNsEE(_M0L6_2atmpS856);
  _M0L8_2atupleS854
  = (struct _M0TUsRPB3MapGiUWEuQRPC15error5ErrorNsEEE*)moonbit_malloc(sizeof(struct _M0TUsRPB3MapGiUWEuQRPC15error5ErrorNsEEE));
  Moonbit_object_header(_M0L8_2atupleS854)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TUsRPB3MapGiUWEuQRPC15error5ErrorNsEEE, $0) >> 2, 2, 0);
  _M0L8_2atupleS854->$0 = (moonbit_string_t)moonbit_string_literal_93.data;
  _M0L8_2atupleS854->$1 = _M0L6_2atmpS855;
  _M0L7_2abindS750
  = (struct _M0TUsRPB3MapGiUWEuQRPC15error5ErrorNsEEE**)moonbit_make_ref_array_raw(1);
  _M0L7_2abindS750[0] = _M0L8_2atupleS854;
  _M0L6_2atmpS853 = _M0L7_2abindS750;
  _M0L6_2atmpS852
  = (struct _M0TPB9ArrayViewGUsRPB3MapGiUWEuQRPC15error5ErrorNsEEEE){
    0, 1, _M0L6_2atmpS853
  };
  #line 397 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors48moonbit__test__driver__internal__no__args__tests
  = _M0MPB3Map11from__arrayGsRPB3MapGiUWEuQRPC15error5ErrorNsEEE(_M0L6_2atmpS852);
}

int main(int argc, char** argv) {
  struct _M0TWWuEuWRPC15error5ErrorEuEOuQRPC15error5Error** _M0L6_2atmpS851;
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12async__testsS818;
  struct _M0TPB5ArrayGUsiEE* _M0L7_2abindS819;
  int32_t _M0L7_2abindS820;
  int32_t _M0L2__S821;
  moonbit_runtime_init(argc, argv);
  moonbit_init();
  _M0L6_2atmpS851
  = (struct _M0TWWuEuWRPC15error5ErrorEuEOuQRPC15error5Error**)moonbit_empty_ref_array;
  _M0L12async__testsS818
  = (struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE));
  Moonbit_object_header(_M0L12async__testsS818)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE, $0) >> 2, 1, 0);
  _M0L12async__testsS818->$0 = _M0L6_2atmpS851;
  _M0L12async__testsS818->$1 = 0;
  #line 443 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0L7_2abindS819
  = _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors52moonbit__test__driver__internal__native__parse__args();
  _M0L7_2abindS820 = _M0L7_2abindS819->$1;
  _M0L2__S821 = 0;
  while (1) {
    if (_M0L2__S821 < _M0L7_2abindS820) {
      struct _M0TUsiE** _M0L3bufS850 = _M0L7_2abindS819->$0;
      struct _M0TUsiE* _M0L3argS822 =
        (struct _M0TUsiE*)_M0L3bufS850[_M0L2__S821];
      moonbit_string_t _M0L6_2atmpS847 = _M0L3argS822->$0;
      int32_t _M0L6_2atmpS848 = _M0L3argS822->$1;
      int32_t _M0L6_2atmpS849;
      moonbit_incref(_M0L6_2atmpS847);
      moonbit_incref(_M0L12async__testsS818);
      #line 444 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
      _M0FP412hnlyxiaobing12MBOpenClacky3lib6errors44moonbit__test__driver__internal__do__execute(_M0L12async__testsS818, _M0L6_2atmpS847, _M0L6_2atmpS848);
      _M0L6_2atmpS849 = _M0L2__S821 + 1;
      _M0L2__S821 = _M0L6_2atmpS849;
      continue;
    } else {
      moonbit_decref(_M0L7_2abindS819);
    }
    break;
  }
  #line 446 "D:\\MoonBit\\MBOpenClacky\\lib\\errors\\__generated_driver_for_whitebox_test.mbt"
  _M0IP016_24default__implP412hnlyxiaobing12MBOpenClacky3lib6errors28MoonBit__Async__Test__Driver17run__async__testsGRP412hnlyxiaobing12MBOpenClacky3lib6errors34MoonBit__Async__Test__Driver__ImplE(_M0L12async__testsS818);
  return 0;
}