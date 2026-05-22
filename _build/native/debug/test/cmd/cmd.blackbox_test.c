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
struct _M0DTPC16result6ResultGbRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test33MoonBitTestDriverInternalSkipTestE2Ok;

struct _M0DTPC15error5Error119hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalJsError_2eMoonBitTestDriverInternalJsError;

struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib7message8ToolCallE;

struct _M0DTP412hnlyxiaobing12MBOpenClacky3lib7message12ContentBlock5Image;

struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib6config11ModelConfigE;

struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure;

struct _M0DTPC15error5Error58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectError;

struct _M0DTPB4Json5Array;

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message9TextBlock;

struct _M0TWssbEu;

struct _M0TUsiE;

struct _M0TPB13StringBuilder;

struct _M0DTPC15error5Error121hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest;

struct _M0DTP412hnlyxiaobing12MBOpenClacky3lib7message14MessageContent6Blocks;

struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib7message12ContentBlockE;

struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib7message7MessageE;

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib6config11ModelConfig;

struct _M0TWWuEuWRPC15error5ErrorEuEOuQRPC15error5Error;

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message10ImageBlock;

struct _M0TPB5ArrayGUsiEE;

struct _M0TWRPC15error5ErrorEs;

struct _M0BTPB6Logger;

struct _M0TPB5ArrayGRPB4JsonE;

struct _M0TPB6Logger;

struct _M0TURPB6LoggerRPC16string10StringViewE;

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message8ToolCall;

struct _M0DTPC15error5Error60moonbitlang_2fcore_2fbuiltin_2eSnapshotError_2eSnapshotError;

struct _M0DTPB4Json6Number;

struct _M0TPB8MutLocalGiE;

struct _M0DTPB4Json6String;

struct _M0DTPC16result6ResultGOuRPC15error5ErrorE3Err;

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message12FunctionCall;

struct _M0DTP412hnlyxiaobing12MBOpenClacky3lib7message12ContentBlock4Text;

struct _M0R122_24hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c354;

struct _M0TWRPC15error5ErrorEu;

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib5agent5Agent;

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib6config11AgentConfig;

struct _M0DTPB4Json6Object;

struct _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok;

struct _M0DTP412hnlyxiaobing12MBOpenClacky3lib7message14MessageContent4Text;

struct _M0TWuEu;

struct _M0TPC16string10StringView;

struct _M0KTPB6LoggerTPB13StringBuilder;

struct _M0TPB5EntryGsRPB4JsonE;

struct _M0TPB5ArrayGsE;

struct _M0TPB3MapGsRPB4JsonE;

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message7Message;

struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE;

struct _M0DTPC16result6ResultGbRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test33MoonBitTestDriverInternalSkipTestE3Err;

struct _M0DTPC16result6ResultGbRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test33MoonBitTestDriverInternalSkipTestE2Ok {
  int32_t $0;
  
};

struct _M0DTPC15error5Error119hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalJsError_2eMoonBitTestDriverInternalJsError {
  moonbit_string_t $0;
  
};

struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib7message8ToolCallE {
  int32_t $1;
  struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message8ToolCall** $0;
  
};

struct _M0DTP412hnlyxiaobing12MBOpenClacky3lib7message12ContentBlock5Image {
  struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message10ImageBlock* $0;
  
};

struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib6config11ModelConfigE {
  int32_t $1;
  struct _M0TP412hnlyxiaobing12MBOpenClacky3lib6config11ModelConfig** $0;
  
};

struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure {
  moonbit_string_t $0;
  
};

struct _M0DTPC15error5Error58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectError {
  moonbit_string_t $0;
  
};

struct _M0DTPB4Json5Array {
  struct _M0TPB5ArrayGRPB4JsonE* $0;
  
};

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message9TextBlock {
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

struct _M0TPB13StringBuilder {
  int32_t $1;
  uint16_t* $0;
  
};

struct _M0DTPC15error5Error121hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest {
  moonbit_string_t $0;
  
};

struct _M0DTP412hnlyxiaobing12MBOpenClacky3lib7message14MessageContent6Blocks {
  struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib7message12ContentBlockE* $0;
  
};

struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib7message12ContentBlockE {
  int32_t $1;
  void** $0;
  
};

struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib7message7MessageE {
  int32_t $1;
  struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message7Message** $0;
  
};

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib6config11ModelConfig {
  int32_t $5;
  moonbit_string_t $0;
  moonbit_string_t $1;
  moonbit_string_t $2;
  moonbit_string_t $3;
  moonbit_string_t $4;
  
};

struct _M0TWWuEuWRPC15error5ErrorEuEOuQRPC15error5Error {
  struct moonbit_result_0(* code)(
    struct _M0TWWuEuWRPC15error5ErrorEuEOuQRPC15error5Error*,
    struct _M0TWuEu*,
    struct _M0TWRPC15error5ErrorEu*
  );
  
};

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message10ImageBlock {
  moonbit_string_t $0;
  moonbit_string_t $1;
  
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

struct _M0TPB5ArrayGRPB4JsonE {
  int32_t $1;
  void** $0;
  
};

struct _M0TPB6Logger {
  struct _M0BTPB6Logger* $0;
  void* $1;
  
};

struct _M0TURPB6LoggerRPC16string10StringViewE {
  int32_t $1_1;
  int32_t $1_2;
  struct _M0BTPB6Logger* $0_0;
  void* $0_1;
  moonbit_string_t $1_0;
  
};

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message8ToolCall {
  moonbit_string_t $0;
  moonbit_string_t $1;
  struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message12FunctionCall* $2;
  
};

struct _M0DTPC15error5Error60moonbitlang_2fcore_2fbuiltin_2eSnapshotError_2eSnapshotError {
  moonbit_string_t $0;
  
};

struct _M0DTPB4Json6Number {
  double $0;
  moonbit_string_t $1;
  
};

struct _M0TPB8MutLocalGiE {
  int32_t $0;
  
};

struct _M0DTPB4Json6String {
  moonbit_string_t $0;
  
};

struct _M0DTPC16result6ResultGOuRPC15error5ErrorE3Err {
  void* $0;
  
};

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message12FunctionCall {
  moonbit_string_t $0;
  moonbit_string_t $1;
  
};

struct _M0DTP412hnlyxiaobing12MBOpenClacky3lib7message12ContentBlock4Text {
  struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message9TextBlock* $0;
  
};

struct _M0R122_24hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c354 {
  int32_t(* code)(
    struct _M0TWssbEu*,
    moonbit_string_t,
    moonbit_string_t,
    int32_t
  );
  int32_t $0;
  moonbit_string_t $1;
  
};

struct _M0TWRPC15error5ErrorEu {
  int32_t(* code)(struct _M0TWRPC15error5ErrorEu*, void*);
  
};

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib5agent5Agent {
  int32_t $3;
  double $4;
  int32_t $7;
  int32_t $9;
  int32_t $11;
  moonbit_string_t $0;
  moonbit_string_t $1;
  struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib7message7MessageE* $2;
  moonbit_string_t $5;
  moonbit_string_t $6;
  moonbit_string_t $8;
  moonbit_string_t $10;
  
};

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib6config11AgentConfig {
  int32_t $0;
  int32_t $1;
  int32_t $2;
  int32_t $3;
  int32_t $4;
  int32_t $7;
  int32_t $9;
  int32_t $10;
  struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib6config11ModelConfigE* $5;
  moonbit_string_t $6;
  void* $8;
  
};

struct _M0DTPB4Json6Object {
  struct _M0TPB3MapGsRPB4JsonE* $0;
  
};

struct _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok {
  int32_t $0;
  
};

struct _M0DTP412hnlyxiaobing12MBOpenClacky3lib7message14MessageContent4Text {
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

struct _M0KTPB6LoggerTPB13StringBuilder {
  struct _M0BTPB6Logger* $0;
  void* $1;
  
};

struct _M0TPB5EntryGsRPB4JsonE {
  int32_t $0;
  int32_t $2;
  int32_t $3;
  struct _M0TPB5EntryGsRPB4JsonE* $1;
  moonbit_string_t $4;
  void* $5;
  
};

struct _M0TPB5ArrayGsE {
  int32_t $1;
  moonbit_string_t* $0;
  
};

struct _M0TPB3MapGsRPB4JsonE {
  int32_t $1;
  int32_t $2;
  int32_t $3;
  int32_t $4;
  int32_t $6;
  struct _M0TPB5EntryGsRPB4JsonE** $0;
  struct _M0TPB5EntryGsRPB4JsonE* $5;
  
};

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message7Message {
  int32_t $0;
  int32_t $7;
  int32_t $13;
  void* $1;
  struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib7message8ToolCallE* $2;
  moonbit_string_t $3;
  moonbit_string_t $4;
  moonbit_string_t $5;
  moonbit_string_t $6;
  void* $8;
  moonbit_string_t $9;
  moonbit_string_t $10;
  void* $11;
  moonbit_string_t $12;
  
};

struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE {
  int32_t $1;
  struct _M0TWWuEuWRPC15error5ErrorEuEOuQRPC15error5Error** $0;
  
};

struct _M0DTPC16result6ResultGbRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test33MoonBitTestDriverInternalSkipTestE3Err {
  void* $0;
  
};

struct moonbit_result_0 {
  int tag;
  union { int32_t ok; void* err;  } data;
  
};

int32_t _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test44moonbit__test__driver__internal__do__execute(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*,
  moonbit_string_t,
  int32_t
);

moonbit_string_t _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test44moonbit__test__driver__internal__do__executeN17error__to__stringS363(
  struct _M0TWRPC15error5ErrorEs*,
  void*
);

int32_t _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test44moonbit__test__driver__internal__do__executeN14handle__resultS354(
  struct _M0TWssbEu*,
  moonbit_string_t,
  moonbit_string_t,
  int32_t
);

struct _M0TPB5ArrayGUsiEE* _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__args(
  
);

struct _M0TPB5ArrayGsE* _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN51moonbit__test__driver__internal__split__mbt__stringS332(
  int32_t,
  moonbit_string_t,
  int32_t
);

struct _M0TPB5ArrayGsE* _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN57moonbit__test__driver__internal__get__cli__args__internalS327(
  int32_t
);

moonbit_string_t _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS320(
  int32_t,
  moonbit_bytes_t
);

int32_t _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN45moonbit__test__driver__internal__parse__int__S314(
  int32_t,
  moonbit_string_t
);

#define _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__get__cli__args__ffi moonbit_get_cli_args

struct moonbit_result_0 _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test41MoonBit__Test__Driver__Internal__No__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*,
  moonbit_string_t,
  int32_t,
  struct _M0TWssbEu*,
  struct _M0TWRPC15error5ErrorEs*
);

struct moonbit_result_0 _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test43MoonBit__Test__Driver__Internal__With__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*,
  moonbit_string_t,
  int32_t,
  struct _M0TWssbEu*,
  struct _M0TWRPC15error5ErrorEs*
);

struct moonbit_result_0 _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test48MoonBit__Test__Driver__Internal__Async__No__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*,
  moonbit_string_t,
  int32_t,
  struct _M0TWssbEu*,
  struct _M0TWRPC15error5ErrorEs*
);

struct moonbit_result_0 _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test50MoonBit__Test__Driver__Internal__Async__With__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*,
  moonbit_string_t,
  int32_t,
  struct _M0TWssbEu*,
  struct _M0TWRPC15error5ErrorEs*
);

struct moonbit_result_0 _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test50MoonBit__Test__Driver__Internal__With__Bench__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*,
  moonbit_string_t,
  int32_t,
  struct _M0TWssbEu*,
  struct _M0TWRPC15error5ErrorEs*
);

int32_t _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test28MoonBit__Async__Test__Driver17run__async__testsGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test34MoonBit__Async__Test__Driver__ImplE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*
);

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib6config11AgentConfig* _M0MP412hnlyxiaobing12MBOpenClacky3lib6config11AgentConfig7default(
  
);

moonbit_string_t _M0MP412hnlyxiaobing12MBOpenClacky3lib6config14PermissionMode17to__string__value(
  int32_t
);

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib5agent5Agent* _M0MP412hnlyxiaobing12MBOpenClacky3lib5agent5Agent3new(
  moonbit_string_t,
  moonbit_string_t,
  moonbit_string_t
);

moonbit_string_t _M0MP412hnlyxiaobing12MBOpenClacky3lib5agent11AgentSource17to__string__value(
  int32_t
);

moonbit_string_t _M0MP412hnlyxiaobing12MBOpenClacky3lib5agent11AgentStatus17to__string__value(
  int32_t
);

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message7Message* _M0MP412hnlyxiaobing12MBOpenClacky3lib7message7Message4user(
  moonbit_string_t
);

moonbit_string_t _M0MP412hnlyxiaobing12MBOpenClacky3lib7message4Role17to__string__value(
  int32_t
);

moonbit_string_t _M0MPC15array5Array2atGsE(struct _M0TPB5ArrayGsE*, int32_t);

int32_t _M0FPB7printlnGsE(moonbit_string_t);

int32_t _M0IPC16string6StringPB4Show6output(
  moonbit_string_t,
  struct _M0TPB6Logger
);

moonbit_string_t _M0IPC13int3IntPB4Show10to__string(int32_t);

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

int32_t _M0MPC16uint166UInt1616unsafe__to__char(int32_t);

int32_t _M0MPC16uint166UInt1623is__trailing__surrogate(int32_t);

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

int32_t _M0IPB7FailurePB4Show6output(void*, struct _M0TPB6Logger);

int32_t _M0MPB6Logger13write__objectGsE(
  struct _M0TPB6Logger,
  moonbit_string_t
);

int32_t _M0FPC15abort5abortGuE(moonbit_string_t);

moonbit_string_t _M0FP15Error10to__string(void*);

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

struct { int32_t rc; uint32_t meta; uint16_t const data[35]; 
} const moonbit_string_literal_2 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 34), 
    45, 45, 45, 45, 45, 32, 66, 69, 71, 73, 78, 32, 77, 79, 79, 78, 32, 
    84, 69, 83, 84, 32, 82, 69, 83, 85, 76, 84, 32, 45, 45, 45, 45, 45, 
    0
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

struct { int32_t rc; uint32_t meta; uint16_t const data[3]; 
} const moonbit_string_literal_30 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 2), 
    92, 116, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[3]; 
} const moonbit_string_literal_28 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 2), 
    92, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[10]; 
} const moonbit_string_literal_21 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 9), 
    97, 115, 115, 105, 115, 116, 97, 110, 116, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[19]; 
} const moonbit_string_literal_32 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 18), 
    105, 110, 118, 97, 108, 105, 100, 32, 99, 111, 100, 101, 32, 112, 
    111, 105, 110, 116, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[53]; 
} const moonbit_string_literal_35 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 52), 
    109, 111, 111, 110, 98, 105, 116, 108, 97, 110, 103, 47, 99, 111, 
    114, 101, 47, 98, 117, 105, 108, 116, 105, 110, 46, 83, 110, 97, 
    112, 115, 104, 111, 116, 69, 114, 114, 111, 114, 46, 83, 110, 97, 
    112, 115, 104, 111, 116, 69, 114, 114, 111, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[3]; 
} const moonbit_string_literal_27 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 2), 
    92, 110, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[5]; 
} const moonbit_string_literal_23 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 4), 
    116, 111, 111, 108, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[31]; 
} const moonbit_string_literal_24 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 30), 
    114, 97, 100, 105, 120, 32, 109, 117, 115, 116, 32, 98, 101, 32, 
    98, 101, 116, 119, 101, 101, 110, 32, 50, 32, 97, 110, 100, 32, 51, 
    54, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[10]; 
} const moonbit_string_literal_19 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 9), 
    99, 111, 109, 112, 108, 101, 116, 101, 100, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[6]; 
} const moonbit_string_literal_18 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 5), 
    101, 114, 114, 111, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[58]; 
} const moonbit_string_literal_3 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 57), 
    123, 34, 112, 97, 99, 107, 97, 103, 101, 34, 58, 32, 34, 104, 110, 
    108, 121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 66, 79, 112, 
    101, 110, 67, 108, 97, 99, 107, 121, 47, 99, 109, 100, 34, 44, 32, 
    34, 102, 105, 108, 101, 110, 97, 109, 101, 34, 58, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[2]; 
} const moonbit_string_literal_25 =
  { -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 1), 48, 0};

struct { int32_t rc; uint32_t meta; uint16_t const data[5]; 
} const moonbit_string_literal_20 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 4), 
    117, 115, 101, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[4]; 
} const moonbit_string_literal_31 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 3), 
    92, 117, 123, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[8]; 
} const moonbit_string_literal_16 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 7), 
    114, 117, 110, 110, 105, 110, 103, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[8]; 
} const moonbit_string_literal_14 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 7), 
    99, 104, 97, 110, 110, 101, 108, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[13]; 
} const moonbit_string_literal_9 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 12), 
    97, 117, 116, 111, 95, 97, 112, 112, 114, 111, 118, 101, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[112]; 
} const moonbit_string_literal_36 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 111), 
    104, 110, 108, 121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 
    66, 79, 112, 101, 110, 67, 108, 97, 99, 107, 121, 47, 99, 109, 100, 
    95, 98, 108, 97, 99, 107, 98, 111, 120, 95, 116, 101, 115, 116, 46, 
    77, 111, 111, 110, 66, 105, 116, 84, 101, 115, 116, 68, 114, 105, 
    118, 101, 114, 73, 110, 116, 101, 114, 110, 97, 108, 83, 107, 105, 
    112, 84, 101, 115, 116, 46, 77, 111, 111, 110, 66, 105, 116, 84, 
    101, 115, 116, 68, 114, 105, 118, 101, 114, 73, 110, 116, 101, 114, 
    110, 97, 108, 83, 107, 105, 112, 84, 101, 115, 116, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[5]; 
} const moonbit_string_literal_13 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 4), 
    99, 114, 111, 110, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[14]; 
} const moonbit_string_literal_10 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 13), 
    99, 111, 110, 102, 105, 114, 109, 95, 115, 97, 102, 101, 115, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[13]; 
} const moonbit_string_literal_4 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 12), 
    44, 32, 34, 105, 110, 100, 101, 120, 34, 58, 32, 34, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[2]; 
} const moonbit_string_literal_34 =
  { -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 1), 41, 0};

struct { int32_t rc; uint32_t meta; uint16_t const data[37]; 
} const moonbit_string_literal_26 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 36), 
    48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102, 
    103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 
    116, 117, 118, 119, 120, 121, 122, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[3]; 
} const moonbit_string_literal_29 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 2), 
    92, 98, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[51]; 
} const moonbit_string_literal_37 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 50), 
    109, 111, 111, 110, 98, 105, 116, 108, 97, 110, 103, 47, 99, 111, 
    114, 101, 47, 98, 117, 105, 108, 116, 105, 110, 46, 73, 110, 115, 
    112, 101, 99, 116, 69, 114, 114, 111, 114, 46, 73, 110, 115, 112, 
    101, 99, 116, 69, 114, 114, 111, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[18]; 
} const moonbit_string_literal_17 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 17), 
    119, 97, 105, 116, 105, 110, 103, 95, 102, 111, 114, 95, 105, 110, 
    112, 117, 116, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[33]; 
} const moonbit_string_literal_8 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 32), 
    45, 45, 45, 45, 45, 32, 69, 78, 68, 32, 77, 79, 79, 78, 32, 84, 69, 
    83, 84, 32, 82, 69, 83, 85, 76, 84, 32, 45, 45, 45, 45, 45, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[7]; 
} const moonbit_string_literal_12 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 6), 
    109, 97, 110, 117, 97, 108, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[110]; 
} const moonbit_string_literal_38 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 109), 
    104, 110, 108, 121, 120, 105, 97, 111, 98, 105, 110, 103, 47, 77, 
    66, 79, 112, 101, 110, 67, 108, 97, 99, 107, 121, 47, 99, 109, 100, 
    95, 98, 108, 97, 99, 107, 98, 111, 120, 95, 116, 101, 115, 116, 46, 
    77, 111, 111, 110, 66, 105, 116, 84, 101, 115, 116, 68, 114, 105, 
    118, 101, 114, 73, 110, 116, 101, 114, 110, 97, 108, 74, 115, 69, 
    114, 114, 111, 114, 46, 77, 111, 111, 110, 66, 105, 116, 84, 101, 
    115, 116, 68, 114, 105, 118, 101, 114, 73, 110, 116, 101, 114, 110, 
    97, 108, 74, 115, 69, 114, 114, 111, 114, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[12]; 
} const moonbit_string_literal_11 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 11), 
    99, 111, 110, 102, 105, 114, 109, 95, 97, 108, 108, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[9]; 
} const moonbit_string_literal_33 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 8), 
    70, 97, 105, 108, 117, 114, 101, 40, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[17]; 
} const moonbit_string_literal_5 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 16), 
    34, 44, 32, 34, 116, 101, 115, 116, 95, 110, 97, 109, 101, 34, 58, 
    32, 0
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

struct { int32_t rc; uint32_t meta; uint16_t const data[7]; 
} const moonbit_string_literal_22 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 6), 
    115, 121, 115, 116, 101, 109, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[5]; 
} const moonbit_string_literal_15 =
  {
    -1, Moonbit_make_array_header(moonbit_BLOCK_KIND_VAL_ARRAY, 1, 4), 
    105, 100, 108, 101, 0
  };

struct { int32_t rc; uint32_t meta; struct _M0TWRPC15error5ErrorEs data; 
} const _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test44moonbit__test__driver__internal__do__executeN17error__to__stringS363$closure =
  {
    -1, Moonbit_make_regular_object_header(2, 0, 0),
    _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test44moonbit__test__driver__internal__do__executeN17error__to__stringS363
  };

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

int32_t _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test44moonbit__test__driver__internal__do__execute(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12async__testsS384,
  moonbit_string_t _M0L8filenameS359,
  int32_t _M0L5indexS362
) {
  struct _M0R122_24hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c354* _closure_923;
  struct _M0TWssbEu* _M0L14handle__resultS354;
  struct _M0TWRPC15error5ErrorEs* _M0L17error__to__stringS363;
  void* _M0L11_2atry__errS378;
  struct moonbit_result_0 _tmp_925;
  int32_t _handle__error__result_926;
  int32_t _M0L6_2atmpS836;
  void* _M0L3errS379;
  moonbit_string_t _M0L4nameS381;
  struct _M0DTPC15error5Error121hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest* _M0L36_2aMoonBitTestDriverInternalSkipTestS382;
  moonbit_string_t _M0L8_2afieldS848;
  int32_t _M0L6_2acntS899;
  moonbit_string_t _M0L7_2anameS383;
  #line 483 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  moonbit_incref(_M0L8filenameS359);
  _closure_923
  = (struct _M0R122_24hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c354*)moonbit_malloc(sizeof(struct _M0R122_24hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c354));
  Moonbit_object_header(_closure_923)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0R122_24hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c354, $1) >> 2, 1, 0);
  _closure_923->code
  = &_M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test44moonbit__test__driver__internal__do__executeN14handle__resultS354;
  _closure_923->$0 = _M0L5indexS362;
  _closure_923->$1 = _M0L8filenameS359;
  _M0L14handle__resultS354 = (struct _M0TWssbEu*)_closure_923;
  _M0L17error__to__stringS363
  = (struct _M0TWRPC15error5ErrorEs*)&_M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test44moonbit__test__driver__internal__do__executeN17error__to__stringS363$closure.data;
  moonbit_incref(_M0L12async__testsS384);
  moonbit_incref(_M0L17error__to__stringS363);
  moonbit_incref(_M0L8filenameS359);
  moonbit_incref(_M0L14handle__resultS354);
  #line 517 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _tmp_925
  = _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test41MoonBit__Test__Driver__Internal__No__ArgsE(_M0L12async__testsS384, _M0L8filenameS359, _M0L5indexS362, _M0L14handle__resultS354, _M0L17error__to__stringS363);
  if (_tmp_925.tag) {
    int32_t const _M0L5_2aokS845 = _tmp_925.data.ok;
    _handle__error__result_926 = _M0L5_2aokS845;
  } else {
    void* const _M0L6_2aerrS846 = _tmp_925.data.err;
    moonbit_decref(_M0L12async__testsS384);
    moonbit_decref(_M0L17error__to__stringS363);
    moonbit_decref(_M0L8filenameS359);
    _M0L11_2atry__errS378 = _M0L6_2aerrS846;
    goto join_377;
  }
  if (_handle__error__result_926) {
    moonbit_decref(_M0L12async__testsS384);
    moonbit_decref(_M0L17error__to__stringS363);
    moonbit_decref(_M0L8filenameS359);
    _M0L6_2atmpS836 = 1;
  } else {
    struct moonbit_result_0 _tmp_927;
    int32_t _handle__error__result_928;
    moonbit_incref(_M0L12async__testsS384);
    moonbit_incref(_M0L17error__to__stringS363);
    moonbit_incref(_M0L8filenameS359);
    moonbit_incref(_M0L14handle__resultS354);
    #line 520 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
    _tmp_927
    = _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test43MoonBit__Test__Driver__Internal__With__ArgsE(_M0L12async__testsS384, _M0L8filenameS359, _M0L5indexS362, _M0L14handle__resultS354, _M0L17error__to__stringS363);
    if (_tmp_927.tag) {
      int32_t const _M0L5_2aokS843 = _tmp_927.data.ok;
      _handle__error__result_928 = _M0L5_2aokS843;
    } else {
      void* const _M0L6_2aerrS844 = _tmp_927.data.err;
      moonbit_decref(_M0L12async__testsS384);
      moonbit_decref(_M0L17error__to__stringS363);
      moonbit_decref(_M0L8filenameS359);
      _M0L11_2atry__errS378 = _M0L6_2aerrS844;
      goto join_377;
    }
    if (_handle__error__result_928) {
      moonbit_decref(_M0L12async__testsS384);
      moonbit_decref(_M0L17error__to__stringS363);
      moonbit_decref(_M0L8filenameS359);
      _M0L6_2atmpS836 = 1;
    } else {
      struct moonbit_result_0 _tmp_929;
      int32_t _handle__error__result_930;
      moonbit_incref(_M0L12async__testsS384);
      moonbit_incref(_M0L17error__to__stringS363);
      moonbit_incref(_M0L8filenameS359);
      moonbit_incref(_M0L14handle__resultS354);
      #line 523 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
      _tmp_929
      = _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test48MoonBit__Test__Driver__Internal__Async__No__ArgsE(_M0L12async__testsS384, _M0L8filenameS359, _M0L5indexS362, _M0L14handle__resultS354, _M0L17error__to__stringS363);
      if (_tmp_929.tag) {
        int32_t const _M0L5_2aokS841 = _tmp_929.data.ok;
        _handle__error__result_930 = _M0L5_2aokS841;
      } else {
        void* const _M0L6_2aerrS842 = _tmp_929.data.err;
        moonbit_decref(_M0L12async__testsS384);
        moonbit_decref(_M0L17error__to__stringS363);
        moonbit_decref(_M0L8filenameS359);
        _M0L11_2atry__errS378 = _M0L6_2aerrS842;
        goto join_377;
      }
      if (_handle__error__result_930) {
        moonbit_decref(_M0L12async__testsS384);
        moonbit_decref(_M0L17error__to__stringS363);
        moonbit_decref(_M0L8filenameS359);
        _M0L6_2atmpS836 = 1;
      } else {
        struct moonbit_result_0 _tmp_931;
        int32_t _handle__error__result_932;
        moonbit_incref(_M0L12async__testsS384);
        moonbit_incref(_M0L17error__to__stringS363);
        moonbit_incref(_M0L8filenameS359);
        moonbit_incref(_M0L14handle__resultS354);
        #line 526 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
        _tmp_931
        = _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test50MoonBit__Test__Driver__Internal__Async__With__ArgsE(_M0L12async__testsS384, _M0L8filenameS359, _M0L5indexS362, _M0L14handle__resultS354, _M0L17error__to__stringS363);
        if (_tmp_931.tag) {
          int32_t const _M0L5_2aokS839 = _tmp_931.data.ok;
          _handle__error__result_932 = _M0L5_2aokS839;
        } else {
          void* const _M0L6_2aerrS840 = _tmp_931.data.err;
          moonbit_decref(_M0L12async__testsS384);
          moonbit_decref(_M0L17error__to__stringS363);
          moonbit_decref(_M0L8filenameS359);
          _M0L11_2atry__errS378 = _M0L6_2aerrS840;
          goto join_377;
        }
        if (_handle__error__result_932) {
          moonbit_decref(_M0L12async__testsS384);
          moonbit_decref(_M0L17error__to__stringS363);
          moonbit_decref(_M0L8filenameS359);
          _M0L6_2atmpS836 = 1;
        } else {
          struct moonbit_result_0 _tmp_933;
          moonbit_incref(_M0L14handle__resultS354);
          #line 529 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
          _tmp_933
          = _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test50MoonBit__Test__Driver__Internal__With__Bench__ArgsE(_M0L12async__testsS384, _M0L8filenameS359, _M0L5indexS362, _M0L14handle__resultS354, _M0L17error__to__stringS363);
          if (_tmp_933.tag) {
            int32_t const _M0L5_2aokS837 = _tmp_933.data.ok;
            _M0L6_2atmpS836 = _M0L5_2aokS837;
          } else {
            void* const _M0L6_2aerrS838 = _tmp_933.data.err;
            _M0L11_2atry__errS378 = _M0L6_2aerrS838;
            goto join_377;
          }
        }
      }
    }
  }
  if (!_M0L6_2atmpS836) {
    void* _M0L121hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTestS847 =
      (void*)moonbit_malloc(sizeof(struct _M0DTPC15error5Error121hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest));
    Moonbit_object_header(_M0L121hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTestS847)->meta
    = Moonbit_make_regular_object_header(offsetof(struct _M0DTPC15error5Error121hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest, $0) >> 2, 1, 1);
    ((struct _M0DTPC15error5Error121hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest*)_M0L121hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTestS847)->$0
    = (moonbit_string_t)moonbit_string_literal_0.data;
    _M0L11_2atry__errS378
    = _M0L121hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTestS847;
    goto join_377;
  } else {
    moonbit_decref(_M0L14handle__resultS354);
  }
  goto joinlet_924;
  join_377:;
  _M0L3errS379 = _M0L11_2atry__errS378;
  _M0L36_2aMoonBitTestDriverInternalSkipTestS382
  = (struct _M0DTPC15error5Error121hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalSkipTest_2eMoonBitTestDriverInternalSkipTest*)_M0L3errS379;
  _M0L8_2afieldS848 = _M0L36_2aMoonBitTestDriverInternalSkipTestS382->$0;
  _M0L6_2acntS899
  = Moonbit_object_header(_M0L36_2aMoonBitTestDriverInternalSkipTestS382)->rc;
  if (_M0L6_2acntS899 > 1) {
    int32_t _M0L11_2anew__cntS900 = _M0L6_2acntS899 - 1;
    Moonbit_object_header(_M0L36_2aMoonBitTestDriverInternalSkipTestS382)->rc
    = _M0L11_2anew__cntS900;
    moonbit_incref(_M0L8_2afieldS848);
  } else if (_M0L6_2acntS899 == 1) {
    #line 536 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
    moonbit_free(_M0L36_2aMoonBitTestDriverInternalSkipTestS382);
  }
  _M0L7_2anameS383 = _M0L8_2afieldS848;
  _M0L4nameS381 = _M0L7_2anameS383;
  goto join_380;
  goto joinlet_934;
  join_380:;
  #line 537 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test44moonbit__test__driver__internal__do__executeN14handle__resultS354(_M0L14handle__resultS354, _M0L4nameS381, (moonbit_string_t)moonbit_string_literal_1.data, 1);
  joinlet_934:;
  joinlet_924:;
  return 0;
}

moonbit_string_t _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test44moonbit__test__driver__internal__do__executeN17error__to__stringS363(
  struct _M0TWRPC15error5ErrorEs* _M0L6_2aenvS835,
  void* _M0L3errS364
) {
  void* _M0L1eS366;
  moonbit_string_t _M0L1eS368;
  #line 506 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  moonbit_decref(_M0L6_2aenvS835);
  switch (Moonbit_object_tag(_M0L3errS364)) {
    case 0: {
      struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure* _M0L10_2aFailureS369 =
        (struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure*)_M0L3errS364;
      moonbit_string_t _M0L8_2afieldS849 = _M0L10_2aFailureS369->$0;
      int32_t _M0L6_2acntS901 =
        Moonbit_object_header(_M0L10_2aFailureS369)->rc;
      moonbit_string_t _M0L4_2aeS370;
      if (_M0L6_2acntS901 > 1) {
        int32_t _M0L11_2anew__cntS902 = _M0L6_2acntS901 - 1;
        Moonbit_object_header(_M0L10_2aFailureS369)->rc
        = _M0L11_2anew__cntS902;
        moonbit_incref(_M0L8_2afieldS849);
      } else if (_M0L6_2acntS901 == 1) {
        #line 507 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
        moonbit_free(_M0L10_2aFailureS369);
      }
      _M0L4_2aeS370 = _M0L8_2afieldS849;
      _M0L1eS368 = _M0L4_2aeS370;
      goto join_367;
      break;
    }
    
    case 2: {
      struct _M0DTPC15error5Error58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectError* _M0L15_2aInspectErrorS371 =
        (struct _M0DTPC15error5Error58moonbitlang_2fcore_2fbuiltin_2eInspectError_2eInspectError*)_M0L3errS364;
      moonbit_string_t _M0L8_2afieldS850 = _M0L15_2aInspectErrorS371->$0;
      int32_t _M0L6_2acntS903 =
        Moonbit_object_header(_M0L15_2aInspectErrorS371)->rc;
      moonbit_string_t _M0L4_2aeS372;
      if (_M0L6_2acntS903 > 1) {
        int32_t _M0L11_2anew__cntS904 = _M0L6_2acntS903 - 1;
        Moonbit_object_header(_M0L15_2aInspectErrorS371)->rc
        = _M0L11_2anew__cntS904;
        moonbit_incref(_M0L8_2afieldS850);
      } else if (_M0L6_2acntS903 == 1) {
        #line 507 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
        moonbit_free(_M0L15_2aInspectErrorS371);
      }
      _M0L4_2aeS372 = _M0L8_2afieldS850;
      _M0L1eS368 = _M0L4_2aeS372;
      goto join_367;
      break;
    }
    
    case 3: {
      struct _M0DTPC15error5Error60moonbitlang_2fcore_2fbuiltin_2eSnapshotError_2eSnapshotError* _M0L16_2aSnapshotErrorS373 =
        (struct _M0DTPC15error5Error60moonbitlang_2fcore_2fbuiltin_2eSnapshotError_2eSnapshotError*)_M0L3errS364;
      moonbit_string_t _M0L8_2afieldS851 = _M0L16_2aSnapshotErrorS373->$0;
      int32_t _M0L6_2acntS905 =
        Moonbit_object_header(_M0L16_2aSnapshotErrorS373)->rc;
      moonbit_string_t _M0L4_2aeS374;
      if (_M0L6_2acntS905 > 1) {
        int32_t _M0L11_2anew__cntS906 = _M0L6_2acntS905 - 1;
        Moonbit_object_header(_M0L16_2aSnapshotErrorS373)->rc
        = _M0L11_2anew__cntS906;
        moonbit_incref(_M0L8_2afieldS851);
      } else if (_M0L6_2acntS905 == 1) {
        #line 507 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
        moonbit_free(_M0L16_2aSnapshotErrorS373);
      }
      _M0L4_2aeS374 = _M0L8_2afieldS851;
      _M0L1eS368 = _M0L4_2aeS374;
      goto join_367;
      break;
    }
    
    case 4: {
      struct _M0DTPC15error5Error119hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalJsError_2eMoonBitTestDriverInternalJsError* _M0L35_2aMoonBitTestDriverInternalJsErrorS375 =
        (struct _M0DTPC15error5Error119hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2eMoonBitTestDriverInternalJsError_2eMoonBitTestDriverInternalJsError*)_M0L3errS364;
      moonbit_string_t _M0L8_2afieldS852 =
        _M0L35_2aMoonBitTestDriverInternalJsErrorS375->$0;
      int32_t _M0L6_2acntS907 =
        Moonbit_object_header(_M0L35_2aMoonBitTestDriverInternalJsErrorS375)->rc;
      moonbit_string_t _M0L4_2aeS376;
      if (_M0L6_2acntS907 > 1) {
        int32_t _M0L11_2anew__cntS908 = _M0L6_2acntS907 - 1;
        Moonbit_object_header(_M0L35_2aMoonBitTestDriverInternalJsErrorS375)->rc
        = _M0L11_2anew__cntS908;
        moonbit_incref(_M0L8_2afieldS852);
      } else if (_M0L6_2acntS907 == 1) {
        #line 507 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
        moonbit_free(_M0L35_2aMoonBitTestDriverInternalJsErrorS375);
      }
      _M0L4_2aeS376 = _M0L8_2afieldS852;
      _M0L1eS368 = _M0L4_2aeS376;
      goto join_367;
      break;
    }
    default: {
      _M0L1eS366 = _M0L3errS364;
      goto join_365;
      break;
    }
  }
  join_367:;
  return _M0L1eS368;
  join_365:;
  #line 512 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  return _M0FP15Error10to__string(_M0L1eS366);
}

int32_t _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test44moonbit__test__driver__internal__do__executeN14handle__resultS354(
  struct _M0TWssbEu* _M0L6_2aenvS821,
  moonbit_string_t _M0L8testnameS355,
  moonbit_string_t _M0L7messageS356,
  int32_t _M0L7skippedS357
) {
  struct _M0R122_24hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c354* _M0L14_2acasted__envS822;
  moonbit_string_t _M0L8filenameS359;
  int32_t _M0L5indexS362;
  int32_t _M0L6_2acntS909;
  int32_t _if__result_937;
  moonbit_string_t _M0L10file__nameS358;
  moonbit_string_t _M0L10test__nameS360;
  moonbit_string_t _M0L7messageS361;
  moonbit_string_t _M0L6_2atmpS834;
  moonbit_string_t _M0L6_2atmpS833;
  moonbit_string_t _M0L6_2atmpS831;
  moonbit_string_t _M0L6_2atmpS832;
  moonbit_string_t _M0L6_2atmpS830;
  moonbit_string_t _M0L6_2atmpS828;
  moonbit_string_t _M0L6_2atmpS829;
  moonbit_string_t _M0L6_2atmpS827;
  moonbit_string_t _M0L6_2atmpS825;
  moonbit_string_t _M0L6_2atmpS826;
  moonbit_string_t _M0L6_2atmpS824;
  moonbit_string_t _M0L6_2atmpS823;
  #line 490 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L14_2acasted__envS822
  = (struct _M0R122_24hnlyxiaobing_2fMBOpenClacky_2fcmd__blackbox__test_2emoonbit__test__driver__internal__do__execute_2ehandle__result_7c354*)_M0L6_2aenvS821;
  _M0L8filenameS359 = _M0L14_2acasted__envS822->$1;
  _M0L5indexS362 = _M0L14_2acasted__envS822->$0;
  _M0L6_2acntS909 = Moonbit_object_header(_M0L14_2acasted__envS822)->rc;
  if (_M0L6_2acntS909 > 1) {
    int32_t _M0L11_2anew__cntS910 = _M0L6_2acntS909 - 1;
    Moonbit_object_header(_M0L14_2acasted__envS822)->rc
    = _M0L11_2anew__cntS910;
    moonbit_incref(_M0L8filenameS359);
  } else if (_M0L6_2acntS909 == 1) {
    #line 490 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
    moonbit_free(_M0L14_2acasted__envS822);
  }
  if (!_M0L7skippedS357) {
    _if__result_937 = 1;
  } else {
    _if__result_937 = 0;
  }
  if (_if__result_937) {
    
  }
  #line 496 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L10file__nameS358
  = _M0MPC16string6String14escape_2einner(_M0L8filenameS359, 1);
  #line 497 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L10test__nameS360
  = _M0MPC16string6String14escape_2einner(_M0L8testnameS355, 1);
  #line 498 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L7messageS361
  = _M0MPC16string6String14escape_2einner(_M0L7messageS356, 1);
  #line 499 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_2.data);
  #line 501 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L6_2atmpS834
  = _M0IPC16string6StringPB4Show10to__string(_M0L10file__nameS358);
  #line 500 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L6_2atmpS833
  = moonbit_add_string((moonbit_string_t)moonbit_string_literal_3.data, _M0L6_2atmpS834);
  moonbit_decref(_M0L6_2atmpS834);
  #line 500 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L6_2atmpS831
  = moonbit_add_string(_M0L6_2atmpS833, (moonbit_string_t)moonbit_string_literal_4.data);
  moonbit_decref(_M0L6_2atmpS833);
  #line 501 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L6_2atmpS832 = _M0IPC13int3IntPB4Show10to__string(_M0L5indexS362);
  #line 500 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L6_2atmpS830 = moonbit_add_string(_M0L6_2atmpS831, _M0L6_2atmpS832);
  moonbit_decref(_M0L6_2atmpS832);
  moonbit_decref(_M0L6_2atmpS831);
  #line 500 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L6_2atmpS828
  = moonbit_add_string(_M0L6_2atmpS830, (moonbit_string_t)moonbit_string_literal_5.data);
  moonbit_decref(_M0L6_2atmpS830);
  #line 501 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L6_2atmpS829
  = _M0IPC16string6StringPB4Show10to__string(_M0L10test__nameS360);
  #line 500 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L6_2atmpS827 = moonbit_add_string(_M0L6_2atmpS828, _M0L6_2atmpS829);
  moonbit_decref(_M0L6_2atmpS829);
  moonbit_decref(_M0L6_2atmpS828);
  #line 500 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L6_2atmpS825
  = moonbit_add_string(_M0L6_2atmpS827, (moonbit_string_t)moonbit_string_literal_6.data);
  moonbit_decref(_M0L6_2atmpS827);
  #line 501 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L6_2atmpS826
  = _M0IPC16string6StringPB4Show10to__string(_M0L7messageS361);
  #line 500 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L6_2atmpS824 = moonbit_add_string(_M0L6_2atmpS825, _M0L6_2atmpS826);
  moonbit_decref(_M0L6_2atmpS826);
  moonbit_decref(_M0L6_2atmpS825);
  #line 500 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L6_2atmpS823
  = moonbit_add_string(_M0L6_2atmpS824, (moonbit_string_t)moonbit_string_literal_7.data);
  moonbit_decref(_M0L6_2atmpS824);
  #line 500 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0FPB7printlnGsE(_M0L6_2atmpS823);
  #line 503 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_8.data);
  return 0;
}

struct _M0TPB5ArrayGUsiEE* _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__args(
  
) {
  int32_t _M0L45moonbit__test__driver__internal__parse__int__S314;
  int32_t _M0L61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS320;
  int32_t _M0L57moonbit__test__driver__internal__get__cli__args__internalS327;
  int32_t _M0L51moonbit__test__driver__internal__split__mbt__stringS332;
  struct _M0TUsiE** _M0L6_2atmpS820;
  struct _M0TPB5ArrayGUsiEE* _M0L16file__and__indexS339;
  struct _M0TPB5ArrayGsE* _M0L9cli__argsS340;
  moonbit_string_t _M0L6_2atmpS819;
  struct _M0TPB5ArrayGsE* _M0L10test__argsS341;
  int32_t _M0L7_2abindS342;
  int32_t _M0L2__S343;
  #line 193 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L45moonbit__test__driver__internal__parse__int__S314 = 0;
  _M0L61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS320 = 0;
  _M0L57moonbit__test__driver__internal__get__cli__args__internalS327
  = _M0L61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS320;
  _M0L51moonbit__test__driver__internal__split__mbt__stringS332 = 0;
  _M0L6_2atmpS820 = (struct _M0TUsiE**)moonbit_empty_ref_array;
  _M0L16file__and__indexS339
  = (struct _M0TPB5ArrayGUsiEE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGUsiEE));
  Moonbit_object_header(_M0L16file__and__indexS339)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGUsiEE, $0) >> 2, 1, 0);
  _M0L16file__and__indexS339->$0 = _M0L6_2atmpS820;
  _M0L16file__and__indexS339->$1 = 0;
  #line 282 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L9cli__argsS340
  = _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN57moonbit__test__driver__internal__get__cli__args__internalS327(_M0L57moonbit__test__driver__internal__get__cli__args__internalS327);
  #line 284 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L6_2atmpS819 = _M0MPC15array5Array2atGsE(_M0L9cli__argsS340, 1);
  #line 283 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L10test__argsS341
  = _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN51moonbit__test__driver__internal__split__mbt__stringS332(_M0L51moonbit__test__driver__internal__split__mbt__stringS332, _M0L6_2atmpS819, 47);
  _M0L7_2abindS342 = _M0L10test__argsS341->$1;
  _M0L2__S343 = 0;
  while (1) {
    if (_M0L2__S343 < _M0L7_2abindS342) {
      moonbit_string_t* _M0L3bufS818 = _M0L10test__argsS341->$0;
      moonbit_string_t _M0L3argS344 =
        (moonbit_string_t)_M0L3bufS818[_M0L2__S343];
      struct _M0TPB5ArrayGsE* _M0L16file__and__rangeS345;
      moonbit_string_t _M0L4fileS346;
      moonbit_string_t _M0L5rangeS347;
      struct _M0TPB5ArrayGsE* _M0L15start__and__endS348;
      moonbit_string_t _M0L6_2atmpS816;
      int32_t _M0L5startS349;
      moonbit_string_t _M0L6_2atmpS815;
      int32_t _M0L3endS350;
      int32_t _M0L1iS351;
      int32_t _M0L6_2atmpS817;
      moonbit_incref(_M0L3argS344);
      #line 288 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
      _M0L16file__and__rangeS345
      = _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN51moonbit__test__driver__internal__split__mbt__stringS332(_M0L51moonbit__test__driver__internal__split__mbt__stringS332, _M0L3argS344, 58);
      moonbit_incref(_M0L16file__and__rangeS345);
      #line 289 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
      _M0L4fileS346
      = _M0MPC15array5Array2atGsE(_M0L16file__and__rangeS345, 0);
      #line 290 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
      _M0L5rangeS347
      = _M0MPC15array5Array2atGsE(_M0L16file__and__rangeS345, 1);
      #line 291 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
      _M0L15start__and__endS348
      = _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN51moonbit__test__driver__internal__split__mbt__stringS332(_M0L51moonbit__test__driver__internal__split__mbt__stringS332, _M0L5rangeS347, 45);
      moonbit_incref(_M0L15start__and__endS348);
      #line 294 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
      _M0L6_2atmpS816
      = _M0MPC15array5Array2atGsE(_M0L15start__and__endS348, 0);
      #line 294 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
      _M0L5startS349
      = _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN45moonbit__test__driver__internal__parse__int__S314(_M0L45moonbit__test__driver__internal__parse__int__S314, _M0L6_2atmpS816);
      #line 295 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
      _M0L6_2atmpS815
      = _M0MPC15array5Array2atGsE(_M0L15start__and__endS348, 1);
      #line 295 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
      _M0L3endS350
      = _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN45moonbit__test__driver__internal__parse__int__S314(_M0L45moonbit__test__driver__internal__parse__int__S314, _M0L6_2atmpS815);
      _M0L1iS351 = _M0L5startS349;
      while (1) {
        if (_M0L1iS351 < _M0L3endS350) {
          struct _M0TUsiE* _M0L8_2atupleS813;
          int32_t _M0L6_2atmpS814;
          moonbit_incref(_M0L4fileS346);
          _M0L8_2atupleS813
          = (struct _M0TUsiE*)moonbit_malloc(sizeof(struct _M0TUsiE));
          Moonbit_object_header(_M0L8_2atupleS813)->meta
          = Moonbit_make_regular_object_header(offsetof(struct _M0TUsiE, $0) >> 2, 1, 0);
          _M0L8_2atupleS813->$0 = _M0L4fileS346;
          _M0L8_2atupleS813->$1 = _M0L1iS351;
          moonbit_incref(_M0L16file__and__indexS339);
          #line 297 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
          _M0MPC15array5Array4pushGUsiEE(_M0L16file__and__indexS339, _M0L8_2atupleS813);
          _M0L6_2atmpS814 = _M0L1iS351 + 1;
          _M0L1iS351 = _M0L6_2atmpS814;
          continue;
        } else {
          moonbit_decref(_M0L4fileS346);
        }
        break;
      }
      _M0L6_2atmpS817 = _M0L2__S343 + 1;
      _M0L2__S343 = _M0L6_2atmpS817;
      continue;
    } else {
      moonbit_decref(_M0L10test__argsS341);
    }
    break;
  }
  return _M0L16file__and__indexS339;
}

struct _M0TPB5ArrayGsE* _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN51moonbit__test__driver__internal__split__mbt__stringS332(
  int32_t _M0L6_2aenvS794,
  moonbit_string_t _M0L1sS333,
  int32_t _M0L3sepS334
) {
  moonbit_string_t* _M0L6_2atmpS812;
  struct _M0TPB5ArrayGsE* _M0L3resS335;
  struct _M0TPB8MutLocalGiE* _M0L1iS336;
  struct _M0TPB8MutLocalGiE* _M0L5startS337;
  int32_t _M0L3valS807;
  int32_t _M0L6_2atmpS808;
  #line 261 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L6_2atmpS812 = (moonbit_string_t*)moonbit_empty_ref_array;
  _M0L3resS335
  = (struct _M0TPB5ArrayGsE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGsE));
  Moonbit_object_header(_M0L3resS335)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGsE, $0) >> 2, 1, 0);
  _M0L3resS335->$0 = _M0L6_2atmpS812;
  _M0L3resS335->$1 = 0;
  _M0L1iS336
  = (struct _M0TPB8MutLocalGiE*)moonbit_malloc(sizeof(struct _M0TPB8MutLocalGiE));
  Moonbit_object_header(_M0L1iS336)->meta
  = Moonbit_make_regular_object_header(sizeof(struct _M0TPB8MutLocalGiE) >> 2, 0, 0);
  _M0L1iS336->$0 = 0;
  _M0L5startS337
  = (struct _M0TPB8MutLocalGiE*)moonbit_malloc(sizeof(struct _M0TPB8MutLocalGiE));
  Moonbit_object_header(_M0L5startS337)->meta
  = Moonbit_make_regular_object_header(sizeof(struct _M0TPB8MutLocalGiE) >> 2, 0, 0);
  _M0L5startS337->$0 = 0;
  while (1) {
    int32_t _M0L3valS795 = _M0L1iS336->$0;
    int32_t _M0L6_2atmpS796 = Moonbit_array_length(_M0L1sS333);
    if (_M0L3valS795 < _M0L6_2atmpS796) {
      int32_t _M0L3valS799 = _M0L1iS336->$0;
      int32_t _M0L6_2atmpS798;
      int32_t _M0L6_2atmpS797;
      int32_t _M0L3valS806;
      int32_t _M0L6_2atmpS805;
      if (
        _M0L3valS799 < 0 || _M0L3valS799 >= Moonbit_array_length(_M0L1sS333)
      ) {
        #line 269 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
        moonbit_panic();
      }
      _M0L6_2atmpS798 = _M0L1sS333[_M0L3valS799];
      _M0L6_2atmpS797 = _M0L6_2atmpS798;
      if (_M0L6_2atmpS797 == _M0L3sepS334) {
        int32_t _M0L3valS801 = _M0L5startS337->$0;
        int32_t _M0L3valS802 = _M0L1iS336->$0;
        moonbit_string_t _M0L6_2atmpS800;
        int32_t _M0L3valS804;
        int32_t _M0L6_2atmpS803;
        moonbit_incref(_M0L1sS333);
        #line 270 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
        _M0L6_2atmpS800
        = _M0MPC16string6String17unsafe__substring(_M0L1sS333, _M0L3valS801, _M0L3valS802);
        moonbit_incref(_M0L3resS335);
        #line 270 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
        _M0MPC15array5Array4pushGsE(_M0L3resS335, _M0L6_2atmpS800);
        _M0L3valS804 = _M0L1iS336->$0;
        _M0L6_2atmpS803 = _M0L3valS804 + 1;
        _M0L5startS337->$0 = _M0L6_2atmpS803;
      }
      _M0L3valS806 = _M0L1iS336->$0;
      _M0L6_2atmpS805 = _M0L3valS806 + 1;
      _M0L1iS336->$0 = _M0L6_2atmpS805;
      continue;
    } else {
      moonbit_decref(_M0L1iS336);
    }
    break;
  }
  _M0L3valS807 = _M0L5startS337->$0;
  _M0L6_2atmpS808 = Moonbit_array_length(_M0L1sS333);
  if (_M0L3valS807 < _M0L6_2atmpS808) {
    int32_t _M0L3valS810 = _M0L5startS337->$0;
    int32_t _M0L6_2atmpS811;
    moonbit_string_t _M0L6_2atmpS809;
    moonbit_decref(_M0L5startS337);
    _M0L6_2atmpS811 = Moonbit_array_length(_M0L1sS333);
    #line 276 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
    _M0L6_2atmpS809
    = _M0MPC16string6String17unsafe__substring(_M0L1sS333, _M0L3valS810, _M0L6_2atmpS811);
    moonbit_incref(_M0L3resS335);
    #line 276 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
    _M0MPC15array5Array4pushGsE(_M0L3resS335, _M0L6_2atmpS809);
  } else {
    moonbit_decref(_M0L5startS337);
    moonbit_decref(_M0L1sS333);
  }
  return _M0L3resS335;
}

struct _M0TPB5ArrayGsE* _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN57moonbit__test__driver__internal__get__cli__args__internalS327(
  int32_t _M0L61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS320
) {
  moonbit_bytes_t* _M0L3tmpS328;
  int32_t _M0L6_2atmpS793;
  struct _M0TPB5ArrayGsE* _M0L3resS329;
  int32_t _M0L1iS330;
  #line 250 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  #line 253 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L3tmpS328
  = _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__get__cli__args__ffi();
  _M0L6_2atmpS793 = Moonbit_array_length(_M0L3tmpS328);
  #line 254 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L3resS329 = _M0MPC15array5Array11new_2einnerGsE(_M0L6_2atmpS793);
  _M0L1iS330 = 0;
  while (1) {
    int32_t _M0L6_2atmpS789 = Moonbit_array_length(_M0L3tmpS328);
    if (_M0L1iS330 < _M0L6_2atmpS789) {
      moonbit_bytes_t _M0L6_2atmpS791;
      moonbit_string_t _M0L6_2atmpS790;
      int32_t _M0L6_2atmpS792;
      if (_M0L1iS330 < 0 || _M0L1iS330 >= Moonbit_array_length(_M0L3tmpS328)) {
        #line 256 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
        moonbit_panic();
      }
      _M0L6_2atmpS791 = (moonbit_bytes_t)_M0L3tmpS328[_M0L1iS330];
      moonbit_incref(_M0L6_2atmpS791);
      #line 256 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
      _M0L6_2atmpS790
      = _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS320(_M0L61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS320, _M0L6_2atmpS791);
      moonbit_incref(_M0L3resS329);
      #line 256 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
      _M0MPC15array5Array4pushGsE(_M0L3resS329, _M0L6_2atmpS790);
      _M0L6_2atmpS792 = _M0L1iS330 + 1;
      _M0L1iS330 = _M0L6_2atmpS792;
      continue;
    } else {
      moonbit_decref(_M0L3tmpS328);
    }
    break;
  }
  return _M0L3resS329;
}

moonbit_string_t _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN61moonbit__test__driver__internal__utf8__bytes__to__mbt__stringS320(
  int32_t _M0L6_2aenvS703,
  moonbit_bytes_t _M0L5bytesS321
) {
  struct _M0TPB13StringBuilder* _M0L3resS322;
  int32_t _M0L3lenS323;
  struct _M0TPB8MutLocalGiE* _M0L1iS324;
  #line 206 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  #line 209 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L3resS322 = _M0MPB13StringBuilder11new_2einner(0);
  _M0L3lenS323 = Moonbit_array_length(_M0L5bytesS321);
  _M0L1iS324
  = (struct _M0TPB8MutLocalGiE*)moonbit_malloc(sizeof(struct _M0TPB8MutLocalGiE));
  Moonbit_object_header(_M0L1iS324)->meta
  = Moonbit_make_regular_object_header(sizeof(struct _M0TPB8MutLocalGiE) >> 2, 0, 0);
  _M0L1iS324->$0 = 0;
  while (1) {
    int32_t _M0L3valS704 = _M0L1iS324->$0;
    if (_M0L3valS704 < _M0L3lenS323) {
      int32_t _M0L3valS788 = _M0L1iS324->$0;
      int32_t _M0L6_2atmpS787;
      int32_t _M0L6_2atmpS786;
      struct _M0TPB8MutLocalGiE* _M0L1cS325;
      int32_t _M0L3valS705;
      if (
        _M0L3valS788 < 0
        || _M0L3valS788 >= Moonbit_array_length(_M0L5bytesS321)
      ) {
        #line 213 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
        moonbit_panic();
      }
      _M0L6_2atmpS787 = _M0L5bytesS321[_M0L3valS788];
      _M0L6_2atmpS786 = (int32_t)_M0L6_2atmpS787;
      _M0L1cS325
      = (struct _M0TPB8MutLocalGiE*)moonbit_malloc(sizeof(struct _M0TPB8MutLocalGiE));
      Moonbit_object_header(_M0L1cS325)->meta
      = Moonbit_make_regular_object_header(sizeof(struct _M0TPB8MutLocalGiE) >> 2, 0, 0);
      _M0L1cS325->$0 = _M0L6_2atmpS786;
      _M0L3valS705 = _M0L1cS325->$0;
      if (_M0L3valS705 < 128) {
        int32_t _M0L3valS707 = _M0L1cS325->$0;
        int32_t _M0L6_2atmpS706;
        int32_t _M0L3valS709;
        int32_t _M0L6_2atmpS708;
        moonbit_decref(_M0L1cS325);
        _M0L6_2atmpS706 = _M0L3valS707;
        moonbit_incref(_M0L3resS322);
        #line 215 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
        _M0IPB13StringBuilderPB6Logger11write__char(_M0L3resS322, _M0L6_2atmpS706);
        _M0L3valS709 = _M0L1iS324->$0;
        _M0L6_2atmpS708 = _M0L3valS709 + 1;
        _M0L1iS324->$0 = _M0L6_2atmpS708;
      } else {
        int32_t _M0L3valS710 = _M0L1cS325->$0;
        if (_M0L3valS710 < 224) {
          int32_t _M0L3valS712 = _M0L1iS324->$0;
          int32_t _M0L6_2atmpS711 = _M0L3valS712 + 1;
          int32_t _M0L3valS721;
          int32_t _M0L6_2atmpS720;
          int32_t _M0L6_2atmpS714;
          int32_t _M0L3valS719;
          int32_t _M0L6_2atmpS718;
          int32_t _M0L6_2atmpS717;
          int32_t _M0L6_2atmpS716;
          int32_t _M0L6_2atmpS715;
          int32_t _M0L6_2atmpS713;
          int32_t _M0L3valS723;
          int32_t _M0L6_2atmpS722;
          int32_t _M0L3valS725;
          int32_t _M0L6_2atmpS724;
          if (_M0L6_2atmpS711 >= _M0L3lenS323) {
            moonbit_decref(_M0L1cS325);
            moonbit_decref(_M0L1iS324);
            moonbit_decref(_M0L5bytesS321);
            break;
          }
          _M0L3valS721 = _M0L1cS325->$0;
          _M0L6_2atmpS720 = _M0L3valS721 & 31;
          _M0L6_2atmpS714 = _M0L6_2atmpS720 << 6;
          _M0L3valS719 = _M0L1iS324->$0;
          _M0L6_2atmpS718 = _M0L3valS719 + 1;
          if (
            _M0L6_2atmpS718 < 0
            || _M0L6_2atmpS718 >= Moonbit_array_length(_M0L5bytesS321)
          ) {
            #line 221 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
            moonbit_panic();
          }
          _M0L6_2atmpS717 = _M0L5bytesS321[_M0L6_2atmpS718];
          _M0L6_2atmpS716 = (int32_t)_M0L6_2atmpS717;
          _M0L6_2atmpS715 = _M0L6_2atmpS716 & 63;
          _M0L6_2atmpS713 = _M0L6_2atmpS714 | _M0L6_2atmpS715;
          _M0L1cS325->$0 = _M0L6_2atmpS713;
          _M0L3valS723 = _M0L1cS325->$0;
          moonbit_decref(_M0L1cS325);
          _M0L6_2atmpS722 = _M0L3valS723;
          moonbit_incref(_M0L3resS322);
          #line 222 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
          _M0IPB13StringBuilderPB6Logger11write__char(_M0L3resS322, _M0L6_2atmpS722);
          _M0L3valS725 = _M0L1iS324->$0;
          _M0L6_2atmpS724 = _M0L3valS725 + 2;
          _M0L1iS324->$0 = _M0L6_2atmpS724;
        } else {
          int32_t _M0L3valS726 = _M0L1cS325->$0;
          if (_M0L3valS726 < 240) {
            int32_t _M0L3valS728 = _M0L1iS324->$0;
            int32_t _M0L6_2atmpS727 = _M0L3valS728 + 2;
            int32_t _M0L3valS744;
            int32_t _M0L6_2atmpS743;
            int32_t _M0L6_2atmpS736;
            int32_t _M0L3valS742;
            int32_t _M0L6_2atmpS741;
            int32_t _M0L6_2atmpS740;
            int32_t _M0L6_2atmpS739;
            int32_t _M0L6_2atmpS738;
            int32_t _M0L6_2atmpS737;
            int32_t _M0L6_2atmpS730;
            int32_t _M0L3valS735;
            int32_t _M0L6_2atmpS734;
            int32_t _M0L6_2atmpS733;
            int32_t _M0L6_2atmpS732;
            int32_t _M0L6_2atmpS731;
            int32_t _M0L6_2atmpS729;
            int32_t _M0L3valS746;
            int32_t _M0L6_2atmpS745;
            int32_t _M0L3valS748;
            int32_t _M0L6_2atmpS747;
            if (_M0L6_2atmpS727 >= _M0L3lenS323) {
              moonbit_decref(_M0L1cS325);
              moonbit_decref(_M0L1iS324);
              moonbit_decref(_M0L5bytesS321);
              break;
            }
            _M0L3valS744 = _M0L1cS325->$0;
            _M0L6_2atmpS743 = _M0L3valS744 & 15;
            _M0L6_2atmpS736 = _M0L6_2atmpS743 << 12;
            _M0L3valS742 = _M0L1iS324->$0;
            _M0L6_2atmpS741 = _M0L3valS742 + 1;
            if (
              _M0L6_2atmpS741 < 0
              || _M0L6_2atmpS741 >= Moonbit_array_length(_M0L5bytesS321)
            ) {
              #line 229 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
              moonbit_panic();
            }
            _M0L6_2atmpS740 = _M0L5bytesS321[_M0L6_2atmpS741];
            _M0L6_2atmpS739 = (int32_t)_M0L6_2atmpS740;
            _M0L6_2atmpS738 = _M0L6_2atmpS739 & 63;
            _M0L6_2atmpS737 = _M0L6_2atmpS738 << 6;
            _M0L6_2atmpS730 = _M0L6_2atmpS736 | _M0L6_2atmpS737;
            _M0L3valS735 = _M0L1iS324->$0;
            _M0L6_2atmpS734 = _M0L3valS735 + 2;
            if (
              _M0L6_2atmpS734 < 0
              || _M0L6_2atmpS734 >= Moonbit_array_length(_M0L5bytesS321)
            ) {
              #line 230 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
              moonbit_panic();
            }
            _M0L6_2atmpS733 = _M0L5bytesS321[_M0L6_2atmpS734];
            _M0L6_2atmpS732 = (int32_t)_M0L6_2atmpS733;
            _M0L6_2atmpS731 = _M0L6_2atmpS732 & 63;
            _M0L6_2atmpS729 = _M0L6_2atmpS730 | _M0L6_2atmpS731;
            _M0L1cS325->$0 = _M0L6_2atmpS729;
            _M0L3valS746 = _M0L1cS325->$0;
            moonbit_decref(_M0L1cS325);
            _M0L6_2atmpS745 = _M0L3valS746;
            moonbit_incref(_M0L3resS322);
            #line 231 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
            _M0IPB13StringBuilderPB6Logger11write__char(_M0L3resS322, _M0L6_2atmpS745);
            _M0L3valS748 = _M0L1iS324->$0;
            _M0L6_2atmpS747 = _M0L3valS748 + 3;
            _M0L1iS324->$0 = _M0L6_2atmpS747;
          } else {
            int32_t _M0L3valS750 = _M0L1iS324->$0;
            int32_t _M0L6_2atmpS749 = _M0L3valS750 + 3;
            int32_t _M0L3valS773;
            int32_t _M0L6_2atmpS772;
            int32_t _M0L6_2atmpS765;
            int32_t _M0L3valS771;
            int32_t _M0L6_2atmpS770;
            int32_t _M0L6_2atmpS769;
            int32_t _M0L6_2atmpS768;
            int32_t _M0L6_2atmpS767;
            int32_t _M0L6_2atmpS766;
            int32_t _M0L6_2atmpS758;
            int32_t _M0L3valS764;
            int32_t _M0L6_2atmpS763;
            int32_t _M0L6_2atmpS762;
            int32_t _M0L6_2atmpS761;
            int32_t _M0L6_2atmpS760;
            int32_t _M0L6_2atmpS759;
            int32_t _M0L6_2atmpS752;
            int32_t _M0L3valS757;
            int32_t _M0L6_2atmpS756;
            int32_t _M0L6_2atmpS755;
            int32_t _M0L6_2atmpS754;
            int32_t _M0L6_2atmpS753;
            int32_t _M0L6_2atmpS751;
            int32_t _M0L3valS775;
            int32_t _M0L6_2atmpS774;
            int32_t _M0L3valS779;
            int32_t _M0L6_2atmpS778;
            int32_t _M0L6_2atmpS777;
            int32_t _M0L6_2atmpS776;
            int32_t _M0L3valS783;
            int32_t _M0L6_2atmpS782;
            int32_t _M0L6_2atmpS781;
            int32_t _M0L6_2atmpS780;
            int32_t _M0L3valS785;
            int32_t _M0L6_2atmpS784;
            if (_M0L6_2atmpS749 >= _M0L3lenS323) {
              moonbit_decref(_M0L1cS325);
              moonbit_decref(_M0L1iS324);
              moonbit_decref(_M0L5bytesS321);
              break;
            }
            _M0L3valS773 = _M0L1cS325->$0;
            _M0L6_2atmpS772 = _M0L3valS773 & 7;
            _M0L6_2atmpS765 = _M0L6_2atmpS772 << 18;
            _M0L3valS771 = _M0L1iS324->$0;
            _M0L6_2atmpS770 = _M0L3valS771 + 1;
            if (
              _M0L6_2atmpS770 < 0
              || _M0L6_2atmpS770 >= Moonbit_array_length(_M0L5bytesS321)
            ) {
              #line 238 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
              moonbit_panic();
            }
            _M0L6_2atmpS769 = _M0L5bytesS321[_M0L6_2atmpS770];
            _M0L6_2atmpS768 = (int32_t)_M0L6_2atmpS769;
            _M0L6_2atmpS767 = _M0L6_2atmpS768 & 63;
            _M0L6_2atmpS766 = _M0L6_2atmpS767 << 12;
            _M0L6_2atmpS758 = _M0L6_2atmpS765 | _M0L6_2atmpS766;
            _M0L3valS764 = _M0L1iS324->$0;
            _M0L6_2atmpS763 = _M0L3valS764 + 2;
            if (
              _M0L6_2atmpS763 < 0
              || _M0L6_2atmpS763 >= Moonbit_array_length(_M0L5bytesS321)
            ) {
              #line 239 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
              moonbit_panic();
            }
            _M0L6_2atmpS762 = _M0L5bytesS321[_M0L6_2atmpS763];
            _M0L6_2atmpS761 = (int32_t)_M0L6_2atmpS762;
            _M0L6_2atmpS760 = _M0L6_2atmpS761 & 63;
            _M0L6_2atmpS759 = _M0L6_2atmpS760 << 6;
            _M0L6_2atmpS752 = _M0L6_2atmpS758 | _M0L6_2atmpS759;
            _M0L3valS757 = _M0L1iS324->$0;
            _M0L6_2atmpS756 = _M0L3valS757 + 3;
            if (
              _M0L6_2atmpS756 < 0
              || _M0L6_2atmpS756 >= Moonbit_array_length(_M0L5bytesS321)
            ) {
              #line 240 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
              moonbit_panic();
            }
            _M0L6_2atmpS755 = _M0L5bytesS321[_M0L6_2atmpS756];
            _M0L6_2atmpS754 = (int32_t)_M0L6_2atmpS755;
            _M0L6_2atmpS753 = _M0L6_2atmpS754 & 63;
            _M0L6_2atmpS751 = _M0L6_2atmpS752 | _M0L6_2atmpS753;
            _M0L1cS325->$0 = _M0L6_2atmpS751;
            _M0L3valS775 = _M0L1cS325->$0;
            _M0L6_2atmpS774 = _M0L3valS775 - 65536;
            _M0L1cS325->$0 = _M0L6_2atmpS774;
            _M0L3valS779 = _M0L1cS325->$0;
            _M0L6_2atmpS778 = _M0L3valS779 >> 10;
            _M0L6_2atmpS777 = _M0L6_2atmpS778 + 55296;
            _M0L6_2atmpS776 = _M0L6_2atmpS777;
            moonbit_incref(_M0L3resS322);
            #line 242 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
            _M0IPB13StringBuilderPB6Logger11write__char(_M0L3resS322, _M0L6_2atmpS776);
            _M0L3valS783 = _M0L1cS325->$0;
            moonbit_decref(_M0L1cS325);
            _M0L6_2atmpS782 = _M0L3valS783 & 1023;
            _M0L6_2atmpS781 = _M0L6_2atmpS782 + 56320;
            _M0L6_2atmpS780 = _M0L6_2atmpS781;
            moonbit_incref(_M0L3resS322);
            #line 243 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
            _M0IPB13StringBuilderPB6Logger11write__char(_M0L3resS322, _M0L6_2atmpS780);
            _M0L3valS785 = _M0L1iS324->$0;
            _M0L6_2atmpS784 = _M0L3valS785 + 4;
            _M0L1iS324->$0 = _M0L6_2atmpS784;
          }
        }
      }
      continue;
    } else {
      moonbit_decref(_M0L1iS324);
      moonbit_decref(_M0L5bytesS321);
    }
    break;
  }
  #line 247 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  return _M0MPB13StringBuilder10to__string(_M0L3resS322);
}

int32_t _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__argsN45moonbit__test__driver__internal__parse__int__S314(
  int32_t _M0L6_2aenvS696,
  moonbit_string_t _M0L1sS315
) {
  struct _M0TPB8MutLocalGiE* _M0L3resS316;
  int32_t _M0L3lenS317;
  int32_t _M0L1iS318;
  int32_t _result_944;
  #line 197 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L3resS316
  = (struct _M0TPB8MutLocalGiE*)moonbit_malloc(sizeof(struct _M0TPB8MutLocalGiE));
  Moonbit_object_header(_M0L3resS316)->meta
  = Moonbit_make_regular_object_header(sizeof(struct _M0TPB8MutLocalGiE) >> 2, 0, 0);
  _M0L3resS316->$0 = 0;
  _M0L3lenS317 = Moonbit_array_length(_M0L1sS315);
  _M0L1iS318 = 0;
  while (1) {
    if (_M0L1iS318 < _M0L3lenS317) {
      int32_t _M0L3valS701 = _M0L3resS316->$0;
      int32_t _M0L6_2atmpS698 = _M0L3valS701 * 10;
      int32_t _M0L6_2atmpS700;
      int32_t _M0L6_2atmpS699;
      int32_t _M0L6_2atmpS697;
      int32_t _M0L6_2atmpS702;
      if (_M0L1iS318 < 0 || _M0L1iS318 >= Moonbit_array_length(_M0L1sS315)) {
        #line 201 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
        moonbit_panic();
      }
      _M0L6_2atmpS700 = _M0L1sS315[_M0L1iS318];
      _M0L6_2atmpS699 = _M0L6_2atmpS700 - 48;
      _M0L6_2atmpS697 = _M0L6_2atmpS698 + _M0L6_2atmpS699;
      _M0L3resS316->$0 = _M0L6_2atmpS697;
      _M0L6_2atmpS702 = _M0L1iS318 + 1;
      _M0L1iS318 = _M0L6_2atmpS702;
      continue;
    } else {
      moonbit_decref(_M0L1sS315);
    }
    break;
  }
  _result_944 = _M0L3resS316->$0;
  moonbit_decref(_M0L3resS316);
  return _result_944;
}

struct moonbit_result_0 _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test41MoonBit__Test__Driver__Internal__No__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12_2adiscard__S289,
  moonbit_string_t _M0L12_2adiscard__S290,
  int32_t _M0L12_2adiscard__S291,
  struct _M0TWssbEu* _M0L12_2adiscard__S292,
  struct _M0TWRPC15error5ErrorEs* _M0L12_2adiscard__S293
) {
  struct moonbit_result_0 _result_945;
  #line 34 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  moonbit_decref(_M0L12_2adiscard__S293);
  moonbit_decref(_M0L12_2adiscard__S292);
  moonbit_decref(_M0L12_2adiscard__S290);
  moonbit_decref(_M0L12_2adiscard__S289);
  _result_945.tag = 1;
  _result_945.data.ok = 0;
  return _result_945;
}

struct moonbit_result_0 _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test43MoonBit__Test__Driver__Internal__With__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12_2adiscard__S294,
  moonbit_string_t _M0L12_2adiscard__S295,
  int32_t _M0L12_2adiscard__S296,
  struct _M0TWssbEu* _M0L12_2adiscard__S297,
  struct _M0TWRPC15error5ErrorEs* _M0L12_2adiscard__S298
) {
  struct moonbit_result_0 _result_946;
  #line 34 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  moonbit_decref(_M0L12_2adiscard__S298);
  moonbit_decref(_M0L12_2adiscard__S297);
  moonbit_decref(_M0L12_2adiscard__S295);
  moonbit_decref(_M0L12_2adiscard__S294);
  _result_946.tag = 1;
  _result_946.data.ok = 0;
  return _result_946;
}

struct moonbit_result_0 _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test48MoonBit__Test__Driver__Internal__Async__No__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12_2adiscard__S299,
  moonbit_string_t _M0L12_2adiscard__S300,
  int32_t _M0L12_2adiscard__S301,
  struct _M0TWssbEu* _M0L12_2adiscard__S302,
  struct _M0TWRPC15error5ErrorEs* _M0L12_2adiscard__S303
) {
  struct moonbit_result_0 _result_947;
  #line 34 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  moonbit_decref(_M0L12_2adiscard__S303);
  moonbit_decref(_M0L12_2adiscard__S302);
  moonbit_decref(_M0L12_2adiscard__S300);
  moonbit_decref(_M0L12_2adiscard__S299);
  _result_947.tag = 1;
  _result_947.data.ok = 0;
  return _result_947;
}

struct moonbit_result_0 _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test50MoonBit__Test__Driver__Internal__Async__With__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12_2adiscard__S304,
  moonbit_string_t _M0L12_2adiscard__S305,
  int32_t _M0L12_2adiscard__S306,
  struct _M0TWssbEu* _M0L12_2adiscard__S307,
  struct _M0TWRPC15error5ErrorEs* _M0L12_2adiscard__S308
) {
  struct moonbit_result_0 _result_948;
  #line 34 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  moonbit_decref(_M0L12_2adiscard__S308);
  moonbit_decref(_M0L12_2adiscard__S307);
  moonbit_decref(_M0L12_2adiscard__S305);
  moonbit_decref(_M0L12_2adiscard__S304);
  _result_948.tag = 1;
  _result_948.data.ok = 0;
  return _result_948;
}

struct moonbit_result_0 _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test21MoonBit__Test__Driver9run__testGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test50MoonBit__Test__Driver__Internal__With__Bench__ArgsE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12_2adiscard__S309,
  moonbit_string_t _M0L12_2adiscard__S310,
  int32_t _M0L12_2adiscard__S311,
  struct _M0TWssbEu* _M0L12_2adiscard__S312,
  struct _M0TWRPC15error5ErrorEs* _M0L12_2adiscard__S313
) {
  struct moonbit_result_0 _result_949;
  #line 34 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  moonbit_decref(_M0L12_2adiscard__S313);
  moonbit_decref(_M0L12_2adiscard__S312);
  moonbit_decref(_M0L12_2adiscard__S310);
  moonbit_decref(_M0L12_2adiscard__S309);
  _result_949.tag = 1;
  _result_949.data.ok = 0;
  return _result_949;
}

int32_t _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test28MoonBit__Async__Test__Driver17run__async__testsGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test34MoonBit__Async__Test__Driver__ImplE(
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12_2adiscard__S288
) {
  #line 12 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  moonbit_decref(_M0L12_2adiscard__S288);
  return 0;
}

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib6config11AgentConfig* _M0MP412hnlyxiaobing12MBOpenClacky3lib6config11AgentConfig7default(
  
) {
  struct _M0TP412hnlyxiaobing12MBOpenClacky3lib6config11ModelConfig** _M0L6_2atmpS695;
  struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib6config11ModelConfigE* _M0L6_2atmpS692;
  moonbit_string_t _M0L6_2atmpS693;
  void* _M0L6_2atmpS694;
  struct _M0TP412hnlyxiaobing12MBOpenClacky3lib6config11AgentConfig* _block_950;
  #line 17 "D:\\MoonBit\\MBOpenClacky\\lib\\config\\agent.mbt"
  _M0L6_2atmpS695
  = (struct _M0TP412hnlyxiaobing12MBOpenClacky3lib6config11ModelConfig**)moonbit_empty_ref_array;
  _M0L6_2atmpS692
  = (struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib6config11ModelConfigE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib6config11ModelConfigE));
  Moonbit_object_header(_M0L6_2atmpS692)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib6config11ModelConfigE, $0) >> 2, 1, 0);
  _M0L6_2atmpS692->$0 = _M0L6_2atmpS695;
  _M0L6_2atmpS692->$1 = 0;
  _M0L6_2atmpS693 = 0;
  _M0L6_2atmpS694 = 0;
  _block_950
  = (struct _M0TP412hnlyxiaobing12MBOpenClacky3lib6config11AgentConfig*)moonbit_malloc(sizeof(struct _M0TP412hnlyxiaobing12MBOpenClacky3lib6config11AgentConfig));
  Moonbit_object_header(_block_950)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TP412hnlyxiaobing12MBOpenClacky3lib6config11AgentConfig, $5) >> 2, 3, 0);
  _block_950->$0 = 1;
  _block_950->$1 = 16384;
  _block_950->$2 = 0;
  _block_950->$3 = 1;
  _block_950->$4 = 1;
  _block_950->$5 = _M0L6_2atmpS692;
  _block_950->$6 = _M0L6_2atmpS693;
  _block_950->$7 = 0;
  _block_950->$8 = _M0L6_2atmpS694;
  _block_950->$9 = 10;
  _block_950->$10 = 10;
  return _block_950;
}

moonbit_string_t _M0MP412hnlyxiaobing12MBOpenClacky3lib6config14PermissionMode17to__string__value(
  int32_t _M0L4selfS284
) {
  #line 10 "D:\\MoonBit\\MBOpenClacky\\lib\\config\\permission.mbt"
  switch (_M0L4selfS284) {
    case 0: {
      return (moonbit_string_t)moonbit_string_literal_9.data;
      break;
    }
    
    case 1: {
      return (moonbit_string_t)moonbit_string_literal_10.data;
      break;
    }
    default: {
      return (moonbit_string_t)moonbit_string_literal_11.data;
      break;
    }
  }
}

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib5agent5Agent* _M0MP412hnlyxiaobing12MBOpenClacky3lib5agent5Agent3new(
  moonbit_string_t _M0L11session__idS281,
  moonbit_string_t _M0L4nameS282,
  moonbit_string_t _M0L12working__dirS283
) {
  struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message7Message** _M0L6_2atmpS691;
  struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib7message7MessageE* _M0L6_2atmpS688;
  moonbit_string_t _M0L6_2atmpS689;
  moonbit_string_t _M0L6_2atmpS690;
  struct _M0TP412hnlyxiaobing12MBOpenClacky3lib5agent5Agent* _block_951;
  #line 18 "D:\\MoonBit\\MBOpenClacky\\lib\\agent\\agent.mbt"
  _M0L6_2atmpS691
  = (struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message7Message**)moonbit_empty_ref_array;
  _M0L6_2atmpS688
  = (struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib7message7MessageE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib7message7MessageE));
  Moonbit_object_header(_M0L6_2atmpS688)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib7message7MessageE, $0) >> 2, 1, 0);
  _M0L6_2atmpS688->$0 = _M0L6_2atmpS691;
  _M0L6_2atmpS688->$1 = 0;
  _M0L6_2atmpS689 = 0;
  _M0L6_2atmpS690 = 0;
  _block_951
  = (struct _M0TP412hnlyxiaobing12MBOpenClacky3lib5agent5Agent*)moonbit_malloc(sizeof(struct _M0TP412hnlyxiaobing12MBOpenClacky3lib5agent5Agent));
  Moonbit_object_header(_block_951)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TP412hnlyxiaobing12MBOpenClacky3lib5agent5Agent, $0) >> 2, 7, 0);
  _block_951->$0 = _M0L11session__idS281;
  _block_951->$1 = _M0L4nameS282;
  _block_951->$2 = _M0L6_2atmpS688;
  _block_951->$3 = 0;
  _block_951->$4 = 0x0p+0;
  _block_951->$5 = _M0L12working__dirS283;
  _block_951->$6 = (moonbit_string_t)moonbit_string_literal_0.data;
  _block_951->$7 = 0;
  _block_951->$8 = _M0L6_2atmpS689;
  _block_951->$9 = 0;
  _block_951->$10 = _M0L6_2atmpS690;
  _block_951->$11 = 0;
  return _block_951;
}

moonbit_string_t _M0MP412hnlyxiaobing12MBOpenClacky3lib5agent11AgentSource17to__string__value(
  int32_t _M0L4selfS280
) {
  #line 29 "D:\\MoonBit\\MBOpenClacky\\lib\\agent\\status.mbt"
  switch (_M0L4selfS280) {
    case 0: {
      return (moonbit_string_t)moonbit_string_literal_12.data;
      break;
    }
    
    case 1: {
      return (moonbit_string_t)moonbit_string_literal_13.data;
      break;
    }
    default: {
      return (moonbit_string_t)moonbit_string_literal_14.data;
      break;
    }
  }
}

moonbit_string_t _M0MP412hnlyxiaobing12MBOpenClacky3lib5agent11AgentStatus17to__string__value(
  int32_t _M0L4selfS279
) {
  #line 18 "D:\\MoonBit\\MBOpenClacky\\lib\\agent\\status.mbt"
  switch (_M0L4selfS279) {
    case 0: {
      return (moonbit_string_t)moonbit_string_literal_15.data;
      break;
    }
    
    case 1: {
      return (moonbit_string_t)moonbit_string_literal_16.data;
      break;
    }
    
    case 2: {
      return (moonbit_string_t)moonbit_string_literal_17.data;
      break;
    }
    
    case 3: {
      return (moonbit_string_t)moonbit_string_literal_18.data;
      break;
    }
    default: {
      return (moonbit_string_t)moonbit_string_literal_19.data;
      break;
    }
  }
}

struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message7Message* _M0MP412hnlyxiaobing12MBOpenClacky3lib7message7Message4user(
  moonbit_string_t _M0L7contentS278
) {
  void* _M0L4TextS677;
  struct _M0TPB5ArrayGRP412hnlyxiaobing12MBOpenClacky3lib7message8ToolCallE* _M0L6_2atmpS678;
  moonbit_string_t _M0L6_2atmpS679;
  moonbit_string_t _M0L6_2atmpS680;
  moonbit_string_t _M0L6_2atmpS681;
  moonbit_string_t _M0L6_2atmpS682;
  void* _M0L6_2atmpS683;
  moonbit_string_t _M0L6_2atmpS684;
  moonbit_string_t _M0L6_2atmpS685;
  void* _M0L6_2atmpS686;
  moonbit_string_t _M0L6_2atmpS687;
  struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message7Message* _block_952;
  #line 53 "D:\\MoonBit\\MBOpenClacky\\lib\\message\\message.mbt"
  _M0L4TextS677
  = (void*)moonbit_malloc(sizeof(struct _M0DTP412hnlyxiaobing12MBOpenClacky3lib7message14MessageContent4Text));
  Moonbit_object_header(_M0L4TextS677)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0DTP412hnlyxiaobing12MBOpenClacky3lib7message14MessageContent4Text, $0) >> 2, 1, 0);
  ((struct _M0DTP412hnlyxiaobing12MBOpenClacky3lib7message14MessageContent4Text*)_M0L4TextS677)->$0
  = _M0L7contentS278;
  _M0L6_2atmpS678 = 0;
  _M0L6_2atmpS679 = 0;
  _M0L6_2atmpS680 = 0;
  _M0L6_2atmpS681 = 0;
  _M0L6_2atmpS682 = 0;
  _M0L6_2atmpS683 = 0;
  _M0L6_2atmpS684 = 0;
  _M0L6_2atmpS685 = 0;
  _M0L6_2atmpS686 = 0;
  _M0L6_2atmpS687 = 0;
  _block_952
  = (struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message7Message*)moonbit_malloc(sizeof(struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message7Message));
  Moonbit_object_header(_block_952)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TP412hnlyxiaobing12MBOpenClacky3lib7message7Message, $1) >> 2, 11, 0);
  _block_952->$0 = 0;
  _block_952->$1 = _M0L4TextS677;
  _block_952->$2 = _M0L6_2atmpS678;
  _block_952->$3 = _M0L6_2atmpS679;
  _block_952->$4 = _M0L6_2atmpS680;
  _block_952->$5 = _M0L6_2atmpS681;
  _block_952->$6 = _M0L6_2atmpS682;
  _block_952->$7 = -1;
  _block_952->$8 = _M0L6_2atmpS683;
  _block_952->$9 = _M0L6_2atmpS684;
  _block_952->$10 = _M0L6_2atmpS685;
  _block_952->$11 = _M0L6_2atmpS686;
  _block_952->$12 = _M0L6_2atmpS687;
  _block_952->$13 = -1;
  return _block_952;
}

moonbit_string_t _M0MP412hnlyxiaobing12MBOpenClacky3lib7message4Role17to__string__value(
  int32_t _M0L4selfS277
) {
  #line 11 "D:\\MoonBit\\MBOpenClacky\\lib\\message\\role.mbt"
  switch (_M0L4selfS277) {
    case 0: {
      return (moonbit_string_t)moonbit_string_literal_20.data;
      break;
    }
    
    case 1: {
      return (moonbit_string_t)moonbit_string_literal_21.data;
      break;
    }
    
    case 2: {
      return (moonbit_string_t)moonbit_string_literal_22.data;
      break;
    }
    default: {
      return (moonbit_string_t)moonbit_string_literal_23.data;
      break;
    }
  }
}

moonbit_string_t _M0MPC15array5Array2atGsE(
  struct _M0TPB5ArrayGsE* _M0L4selfS275,
  int32_t _M0L5indexS276
) {
  int32_t _M0L3lenS274;
  int32_t _if__result_953;
  #line 183 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\array.mbt"
  _M0L3lenS274 = _M0L4selfS275->$1;
  if (_M0L5indexS276 >= 0) {
    _if__result_953 = _M0L5indexS276 < _M0L3lenS274;
  } else {
    _if__result_953 = 0;
  }
  if (_if__result_953) {
    moonbit_string_t* _M0L6_2atmpS676;
    moonbit_string_t _M0L6_2atmpS857;
    #line 188 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\array.mbt"
    _M0L6_2atmpS676 = _M0MPC15array5Array6bufferGsE(_M0L4selfS275);
    if (
      _M0L5indexS276 < 0
      || _M0L5indexS276 >= Moonbit_array_length(_M0L6_2atmpS676)
    ) {
      #line 188 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\array.mbt"
      moonbit_panic();
    }
    _M0L6_2atmpS857 = (moonbit_string_t)_M0L6_2atmpS676[_M0L5indexS276];
    moonbit_incref(_M0L6_2atmpS857);
    moonbit_decref(_M0L6_2atmpS676);
    return _M0L6_2atmpS857;
  } else {
    moonbit_decref(_M0L4selfS275);
    #line 187 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\array.mbt"
    moonbit_panic();
  }
}

int32_t _M0FPB7printlnGsE(moonbit_string_t _M0L5inputS273) {
  moonbit_string_t _M0L6_2atmpS675;
  #line 37 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  #line 38 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  _M0L6_2atmpS675 = _M0IPC16string6StringPB4Show10to__string(_M0L5inputS273);
  #line 38 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\console.mbt"
  moonbit_println(_M0L6_2atmpS675);
  moonbit_decref(_M0L6_2atmpS675);
  return 0;
}

int32_t _M0IPC16string6StringPB4Show6output(
  moonbit_string_t _M0L4selfS271,
  struct _M0TPB6Logger _M0L6loggerS272
) {
  int32_t _M0L6_2atmpS674;
  struct _M0TPC16string10StringView _M0L6_2atmpS673;
  #line 244 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L6_2atmpS674 = Moonbit_array_length(_M0L4selfS271);
  _M0L6_2atmpS673
  = (struct _M0TPC16string10StringView){
    0, _M0L6_2atmpS674, _M0L4selfS271
  };
  #line 245 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0MPC16string10StringView18escape__to_2einner(_M0L6_2atmpS673, _M0L6loggerS272, 1);
  return 0;
}

moonbit_string_t _M0IPC13int3IntPB4Show10to__string(int32_t _M0L4selfS270) {
  #line 45 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  #line 46 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  return _M0MPC13int3Int18to__string_2einner(_M0L4selfS270, 10);
}

int32_t _M0MPC15array5Array4pushGsE(
  struct _M0TPB5ArrayGsE* _M0L4selfS264,
  moonbit_string_t _M0L5valueS266
) {
  int32_t _M0L3lenS663;
  moonbit_string_t* _M0L6_2atmpS665;
  int32_t _M0L6_2atmpS664;
  int32_t _M0L6lengthS265;
  moonbit_string_t* _M0L3bufS666;
  moonbit_string_t _M0L6_2aoldS858;
  int32_t _M0L6_2atmpS667;
  #line 242 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L3lenS663 = _M0L4selfS264->$1;
  moonbit_incref(_M0L4selfS264);
  #line 243 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L6_2atmpS665 = _M0MPC15array5Array6bufferGsE(_M0L4selfS264);
  _M0L6_2atmpS664 = Moonbit_array_length(_M0L6_2atmpS665);
  moonbit_decref(_M0L6_2atmpS665);
  if (_M0L3lenS663 == _M0L6_2atmpS664) {
    moonbit_incref(_M0L4selfS264);
    #line 244 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
    _M0MPC15array5Array7reallocGsE(_M0L4selfS264);
  }
  _M0L6lengthS265 = _M0L4selfS264->$1;
  _M0L3bufS666 = _M0L4selfS264->$0;
  _M0L6_2aoldS858 = (moonbit_string_t)_M0L3bufS666[_M0L6lengthS265];
  moonbit_decref(_M0L6_2aoldS858);
  _M0L3bufS666[_M0L6lengthS265] = _M0L5valueS266;
  _M0L6_2atmpS667 = _M0L6lengthS265 + 1;
  _M0L4selfS264->$1 = _M0L6_2atmpS667;
  moonbit_decref(_M0L4selfS264);
  return 0;
}

int32_t _M0MPC15array5Array4pushGUsiEE(
  struct _M0TPB5ArrayGUsiEE* _M0L4selfS267,
  struct _M0TUsiE* _M0L5valueS269
) {
  int32_t _M0L3lenS668;
  struct _M0TUsiE** _M0L6_2atmpS670;
  int32_t _M0L6_2atmpS669;
  int32_t _M0L6lengthS268;
  struct _M0TUsiE** _M0L3bufS671;
  struct _M0TUsiE* _M0L6_2aoldS860;
  int32_t _M0L6_2atmpS672;
  #line 242 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L3lenS668 = _M0L4selfS267->$1;
  moonbit_incref(_M0L4selfS267);
  #line 243 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L6_2atmpS670 = _M0MPC15array5Array6bufferGUsiEE(_M0L4selfS267);
  _M0L6_2atmpS669 = Moonbit_array_length(_M0L6_2atmpS670);
  moonbit_decref(_M0L6_2atmpS670);
  if (_M0L3lenS668 == _M0L6_2atmpS669) {
    moonbit_incref(_M0L4selfS267);
    #line 244 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
    _M0MPC15array5Array7reallocGUsiEE(_M0L4selfS267);
  }
  _M0L6lengthS268 = _M0L4selfS267->$1;
  _M0L3bufS671 = _M0L4selfS267->$0;
  _M0L6_2aoldS860 = (struct _M0TUsiE*)_M0L3bufS671[_M0L6lengthS268];
  if (_M0L6_2aoldS860) {
    moonbit_decref(_M0L6_2aoldS860);
  }
  _M0L3bufS671[_M0L6lengthS268] = _M0L5valueS269;
  _M0L6_2atmpS672 = _M0L6lengthS268 + 1;
  _M0L4selfS267->$1 = _M0L6_2atmpS672;
  moonbit_decref(_M0L4selfS267);
  return 0;
}

int32_t _M0MPC15array5Array7reallocGsE(struct _M0TPB5ArrayGsE* _M0L4selfS259) {
  int32_t _M0L8old__capS258;
  int32_t _M0L8new__capS260;
  #line 182 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L8old__capS258 = _M0L4selfS259->$1;
  if (_M0L8old__capS258 == 0) {
    _M0L8new__capS260 = 8;
  } else {
    _M0L8new__capS260 = _M0L8old__capS258 * 2;
  }
  #line 185 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0MPC15array5Array14resize__bufferGsE(_M0L4selfS259, _M0L8new__capS260);
  return 0;
}

int32_t _M0MPC15array5Array7reallocGUsiEE(
  struct _M0TPB5ArrayGUsiEE* _M0L4selfS262
) {
  int32_t _M0L8old__capS261;
  int32_t _M0L8new__capS263;
  #line 182 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L8old__capS261 = _M0L4selfS262->$1;
  if (_M0L8old__capS261 == 0) {
    _M0L8new__capS263 = 8;
  } else {
    _M0L8new__capS263 = _M0L8old__capS261 * 2;
  }
  #line 185 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0MPC15array5Array14resize__bufferGUsiEE(_M0L4selfS262, _M0L8new__capS263);
  return 0;
}

int32_t _M0MPC15array5Array14resize__bufferGsE(
  struct _M0TPB5ArrayGsE* _M0L4selfS249,
  int32_t _M0L13new__capacityS247
) {
  moonbit_string_t* _M0L8new__bufS246;
  moonbit_string_t* _M0L8old__bufS248;
  int32_t _M0L8old__capS250;
  int32_t _M0L9copy__lenS251;
  moonbit_string_t* _M0L6_2aoldS862;
  #line 129 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L8new__bufS246
  = (moonbit_string_t*)moonbit_make_ref_array(_M0L13new__capacityS247, (moonbit_string_t)moonbit_string_literal_0.data);
  _M0L8old__bufS248 = _M0L4selfS249->$0;
  _M0L8old__capS250 = Moonbit_array_length(_M0L8old__bufS248);
  if (_M0L8old__capS250 < _M0L13new__capacityS247) {
    _M0L9copy__lenS251 = _M0L8old__capS250;
  } else {
    _M0L9copy__lenS251 = _M0L13new__capacityS247;
  }
  moonbit_incref(_M0L8old__bufS248);
  moonbit_incref(_M0L8new__bufS246);
  #line 134 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0MPB18UninitializedArray12unsafe__blitGsE(_M0L8new__bufS246, 0, _M0L8old__bufS248, 0, _M0L9copy__lenS251);
  _M0L6_2aoldS862 = _M0L4selfS249->$0;
  moonbit_decref(_M0L6_2aoldS862);
  _M0L4selfS249->$0 = _M0L8new__bufS246;
  moonbit_decref(_M0L4selfS249);
  return 0;
}

int32_t _M0MPC15array5Array14resize__bufferGUsiEE(
  struct _M0TPB5ArrayGUsiEE* _M0L4selfS255,
  int32_t _M0L13new__capacityS253
) {
  struct _M0TUsiE** _M0L8new__bufS252;
  struct _M0TUsiE** _M0L8old__bufS254;
  int32_t _M0L8old__capS256;
  int32_t _M0L9copy__lenS257;
  struct _M0TUsiE** _M0L6_2aoldS864;
  #line 129 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L8new__bufS252
  = (struct _M0TUsiE**)moonbit_make_ref_array(_M0L13new__capacityS253, 0);
  _M0L8old__bufS254 = _M0L4selfS255->$0;
  _M0L8old__capS256 = Moonbit_array_length(_M0L8old__bufS254);
  if (_M0L8old__capS256 < _M0L13new__capacityS253) {
    _M0L9copy__lenS257 = _M0L8old__capS256;
  } else {
    _M0L9copy__lenS257 = _M0L13new__capacityS253;
  }
  moonbit_incref(_M0L8old__bufS254);
  moonbit_incref(_M0L8new__bufS252);
  #line 134 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0MPB18UninitializedArray12unsafe__blitGUsiEE(_M0L8new__bufS252, 0, _M0L8old__bufS254, 0, _M0L9copy__lenS257);
  _M0L6_2aoldS864 = _M0L4selfS255->$0;
  moonbit_decref(_M0L6_2aoldS864);
  _M0L4selfS255->$0 = _M0L8new__bufS252;
  moonbit_decref(_M0L4selfS255);
  return 0;
}

moonbit_string_t* _M0MPC15array5Array6bufferGsE(
  struct _M0TPB5ArrayGsE* _M0L4selfS244
) {
  moonbit_string_t* _M0L8_2afieldS866;
  int32_t _M0L6_2acntS911;
  #line 124 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L8_2afieldS866 = _M0L4selfS244->$0;
  _M0L6_2acntS911 = Moonbit_object_header(_M0L4selfS244)->rc;
  if (_M0L6_2acntS911 > 1) {
    int32_t _M0L11_2anew__cntS912 = _M0L6_2acntS911 - 1;
    Moonbit_object_header(_M0L4selfS244)->rc = _M0L11_2anew__cntS912;
    moonbit_incref(_M0L8_2afieldS866);
  } else if (_M0L6_2acntS911 == 1) {
    #line 125 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
    moonbit_free(_M0L4selfS244);
  }
  return _M0L8_2afieldS866;
}

struct _M0TUsiE** _M0MPC15array5Array6bufferGUsiEE(
  struct _M0TPB5ArrayGUsiEE* _M0L4selfS245
) {
  struct _M0TUsiE** _M0L8_2afieldS867;
  int32_t _M0L6_2acntS913;
  #line 124 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  _M0L8_2afieldS867 = _M0L4selfS245->$0;
  _M0L6_2acntS913 = Moonbit_object_header(_M0L4selfS245)->rc;
  if (_M0L6_2acntS913 > 1) {
    int32_t _M0L11_2anew__cntS914 = _M0L6_2acntS913 - 1;
    Moonbit_object_header(_M0L4selfS245)->rc = _M0L11_2anew__cntS914;
    moonbit_incref(_M0L8_2afieldS867);
  } else if (_M0L6_2acntS913 == 1) {
    #line 125 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
    moonbit_free(_M0L4selfS245);
  }
  return _M0L8_2afieldS867;
}

struct _M0TPB5ArrayGsE* _M0MPC15array5Array11new_2einnerGsE(
  int32_t _M0L8capacityS243
) {
  #line 53 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\arraycore_nonjs.mbt"
  if (_M0L8capacityS243 == 0) {
    moonbit_string_t* _M0L6_2atmpS661 =
      (moonbit_string_t*)moonbit_empty_ref_array;
    struct _M0TPB5ArrayGsE* _block_954 =
      (struct _M0TPB5ArrayGsE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGsE));
    Moonbit_object_header(_block_954)->meta
    = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGsE, $0) >> 2, 1, 0);
    _block_954->$0 = _M0L6_2atmpS661;
    _block_954->$1 = 0;
    return _block_954;
  } else {
    moonbit_string_t* _M0L6_2atmpS662 =
      (moonbit_string_t*)moonbit_make_ref_array(_M0L8capacityS243, (moonbit_string_t)moonbit_string_literal_0.data);
    struct _M0TPB5ArrayGsE* _block_955 =
      (struct _M0TPB5ArrayGsE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGsE));
    Moonbit_object_header(_block_955)->meta
    = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGsE, $0) >> 2, 1, 0);
    _block_955->$0 = _M0L6_2atmpS662;
    _block_955->$1 = 0;
    return _block_955;
  }
}

moonbit_string_t _M0IPC16string6StringPB4Show10to__string(
  moonbit_string_t _M0L4selfS242
) {
  #line 262 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  return _M0L4selfS242;
}

int32_t _M0IPB13StringBuilderPB6Logger11write__view(
  struct _M0TPB13StringBuilder* _M0L4selfS241,
  struct _M0TPC16string10StringView _M0L3strS240
) {
  int32_t _M0L8str__lenS239;
  int32_t _M0L3lenS654;
  int32_t _M0L6_2atmpS653;
  uint16_t* _M0L4dataS655;
  int32_t _M0L3lenS656;
  moonbit_string_t _M0L6_2atmpS657;
  int32_t _M0L6_2atmpS658;
  int32_t _M0L3lenS660;
  int32_t _M0L6_2atmpS659;
  #line 126 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  moonbit_incref(_M0L3strS240.$0);
  #line 130 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L8str__lenS239 = _M0MPC16string10StringView6length(_M0L3strS240);
  _M0L3lenS654 = _M0L4selfS241->$1;
  _M0L6_2atmpS653 = _M0L3lenS654 + _M0L8str__lenS239;
  moonbit_incref(_M0L4selfS241);
  #line 131 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0MPB13StringBuilder19grow__if__necessary(_M0L4selfS241, _M0L6_2atmpS653);
  _M0L4dataS655 = _M0L4selfS241->$0;
  _M0L3lenS656 = _M0L4selfS241->$1;
  moonbit_incref(_M0L4dataS655);
  moonbit_incref(_M0L3strS240.$0);
  #line 134 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L6_2atmpS657 = _M0MPC16string10StringView4data(_M0L3strS240);
  #line 135 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L6_2atmpS658 = _M0MPC16string10StringView13start__offset(_M0L3strS240);
  #line 132 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0MPC15array10FixedArray26unsafe__blit__from__string(_M0L4dataS655, _M0L3lenS656, _M0L6_2atmpS657, _M0L6_2atmpS658, _M0L8str__lenS239);
  _M0L3lenS660 = _M0L4selfS241->$1;
  _M0L6_2atmpS659 = _M0L3lenS660 + _M0L8str__lenS239;
  _M0L4selfS241->$1 = _M0L6_2atmpS659;
  moonbit_decref(_M0L4selfS241);
  return 0;
}

moonbit_string_t _M0MPC16string6String17unsafe__substring(
  moonbit_string_t _M0L3strS236,
  int32_t _M0L5startS234,
  int32_t _M0L3endS235
) {
  int32_t _if__result_956;
  int32_t _M0L3lenS237;
  int32_t _M0L6_2atmpS651;
  int32_t _M0L6_2atmpS652;
  moonbit_bytes_t _M0L5bytesS238;
  moonbit_bytes_t _M0L6_2atmpS650;
  #line 91 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
  if (_M0L5startS234 == 0) {
    int32_t _M0L6_2atmpS649 = Moonbit_array_length(_M0L3strS236);
    _if__result_956 = _M0L3endS235 == _M0L6_2atmpS649;
  } else {
    _if__result_956 = 0;
  }
  if (_if__result_956) {
    return _M0L3strS236;
  }
  _M0L3lenS237 = _M0L3endS235 - _M0L5startS234;
  _M0L6_2atmpS651 = _M0L3lenS237 * 2;
  #line 101 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
  _M0L6_2atmpS652 = _M0IPC14byte4BytePB7Default7default();
  _M0L5bytesS238
  = (moonbit_bytes_t)moonbit_make_bytes(_M0L6_2atmpS651, _M0L6_2atmpS652);
  moonbit_incref(_M0L5bytesS238);
  #line 102 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
  _M0MPC15array10FixedArray18blit__from__string(_M0L5bytesS238, 0, _M0L3strS236, _M0L5startS234, _M0L3lenS237);
  _M0L6_2atmpS650 = _M0L5bytesS238;
  #line 103 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\string.mbt"
  return _M0MPC15bytes5Bytes29to__unchecked__string_2einner(_M0L6_2atmpS650, 0, 4294967296ll);
}

int32_t _M0IPC14byte4BytePB7Default7default() {
  #line 231 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\byte.mbt"
  return 0;
}

moonbit_string_t _M0MPC15bytes5Bytes29to__unchecked__string_2einner(
  moonbit_bytes_t _M0L4selfS229,
  int32_t _M0L6offsetS233,
  int64_t _M0L6lengthS231
) {
  int32_t _M0L3lenS228;
  int32_t _M0L6lengthS230;
  int32_t _if__result_957;
  #line 76 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
  _M0L3lenS228 = Moonbit_array_length(_M0L4selfS229);
  if (_M0L6lengthS231 == 4294967296ll) {
    _M0L6lengthS230 = _M0L3lenS228 - _M0L6offsetS233;
  } else {
    int64_t _M0L7_2aSomeS232 = _M0L6lengthS231;
    _M0L6lengthS230 = (int32_t)_M0L7_2aSomeS232;
  }
  if (_M0L6offsetS233 >= 0) {
    if (_M0L6lengthS230 >= 0) {
      int32_t _M0L6_2atmpS648 = _M0L6offsetS233 + _M0L6lengthS230;
      _if__result_957 = _M0L6_2atmpS648 <= _M0L3lenS228;
    } else {
      _if__result_957 = 0;
    }
  } else {
    _if__result_957 = 0;
  }
  if (_if__result_957) {
    #line 84 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
    return _M0FPB19unsafe__sub__string(_M0L4selfS229, _M0L6offsetS233, _M0L6lengthS230);
  } else {
    moonbit_decref(_M0L4selfS229);
    #line 83 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
    moonbit_panic();
  }
}

int32_t _M0MPC15array10FixedArray18blit__from__string(
  moonbit_bytes_t _M0L4selfS220,
  int32_t _M0L13bytes__offsetS215,
  moonbit_string_t _M0L3strS222,
  int32_t _M0L11str__offsetS218,
  int32_t _M0L6lengthS216
) {
  int32_t _M0L6_2atmpS647;
  int32_t _M0L6_2atmpS646;
  int32_t _M0L2e1S214;
  int32_t _M0L6_2atmpS645;
  int32_t _M0L2e2S217;
  int32_t _M0L4len1S219;
  int32_t _M0L4len2S221;
  int32_t _if__result_958;
  #line 124 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
  _M0L6_2atmpS647 = _M0L6lengthS216 * 2;
  _M0L6_2atmpS646 = _M0L13bytes__offsetS215 + _M0L6_2atmpS647;
  _M0L2e1S214 = _M0L6_2atmpS646 - 1;
  _M0L6_2atmpS645 = _M0L11str__offsetS218 + _M0L6lengthS216;
  _M0L2e2S217 = _M0L6_2atmpS645 - 1;
  _M0L4len1S219 = Moonbit_array_length(_M0L4selfS220);
  _M0L4len2S221 = Moonbit_array_length(_M0L3strS222);
  if (_M0L6lengthS216 >= 0) {
    if (_M0L13bytes__offsetS215 >= 0) {
      if (_M0L2e1S214 < _M0L4len1S219) {
        if (_M0L11str__offsetS218 >= 0) {
          _if__result_958 = _M0L2e2S217 < _M0L4len2S221;
        } else {
          _if__result_958 = 0;
        }
      } else {
        _if__result_958 = 0;
      }
    } else {
      _if__result_958 = 0;
    }
  } else {
    _if__result_958 = 0;
  }
  if (_if__result_958) {
    int32_t _M0L16end__str__offsetS223 =
      _M0L11str__offsetS218 + _M0L6lengthS216;
    int32_t _M0L1iS224 = _M0L11str__offsetS218;
    int32_t _M0L1jS225 = _M0L13bytes__offsetS215;
    while (1) {
      if (_M0L1iS224 < _M0L16end__str__offsetS223) {
        int32_t _M0L6_2atmpS642 = _M0L3strS222[_M0L1iS224];
        int32_t _M0L6_2atmpS641 = (int32_t)_M0L6_2atmpS642;
        uint32_t _M0L1cS226 = *(uint32_t*)&_M0L6_2atmpS641;
        uint32_t _M0L6_2atmpS637 = _M0L1cS226 & 255u;
        int32_t _M0L6_2atmpS636;
        int32_t _M0L6_2atmpS638;
        uint32_t _M0L6_2atmpS640;
        int32_t _M0L6_2atmpS639;
        int32_t _M0L6_2atmpS643;
        int32_t _M0L6_2atmpS644;
        #line 141 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
        _M0L6_2atmpS636 = _M0MPC14uint4UInt8to__byte(_M0L6_2atmpS637);
        if (
          _M0L1jS225 < 0 || _M0L1jS225 >= Moonbit_array_length(_M0L4selfS220)
        ) {
          #line 141 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
          moonbit_panic();
        }
        _M0L4selfS220[_M0L1jS225] = _M0L6_2atmpS636;
        _M0L6_2atmpS638 = _M0L1jS225 + 1;
        _M0L6_2atmpS640 = _M0L1cS226 >> 8;
        #line 142 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
        _M0L6_2atmpS639 = _M0MPC14uint4UInt8to__byte(_M0L6_2atmpS640);
        if (
          _M0L6_2atmpS638 < 0
          || _M0L6_2atmpS638 >= Moonbit_array_length(_M0L4selfS220)
        ) {
          #line 142 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
          moonbit_panic();
        }
        _M0L4selfS220[_M0L6_2atmpS638] = _M0L6_2atmpS639;
        _M0L6_2atmpS643 = _M0L1iS224 + 1;
        _M0L6_2atmpS644 = _M0L1jS225 + 2;
        _M0L1iS224 = _M0L6_2atmpS643;
        _M0L1jS225 = _M0L6_2atmpS644;
        continue;
      } else {
        moonbit_decref(_M0L3strS222);
        moonbit_decref(_M0L4selfS220);
      }
      break;
    }
  } else {
    moonbit_decref(_M0L3strS222);
    moonbit_decref(_M0L4selfS220);
    #line 137 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\bytes.mbt"
    moonbit_panic();
  }
  return 0;
}

int32_t _M0MPC14uint4UInt8to__byte(uint32_t _M0L4selfS213) {
  int32_t _M0L6_2atmpS635;
  #line 2518 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\intrinsics.mbt"
  _M0L6_2atmpS635 = *(int32_t*)&_M0L4selfS213;
  return _M0L6_2atmpS635 & 0xff;
}

moonbit_string_t _M0MPC13int3Int18to__string_2einner(
  int32_t _M0L4selfS197,
  int32_t _M0L5radixS196
) {
  int32_t _if__result_960;
  int32_t _M0L12is__negativeS198;
  uint32_t _M0L3numS199;
  uint16_t* _M0L6bufferS200;
  #line 209 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
  if (_M0L5radixS196 < 2) {
    _if__result_960 = 1;
  } else {
    _if__result_960 = _M0L5radixS196 > 36;
  }
  if (_if__result_960) {
    #line 213 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
    _M0FPC15abort5abortGuE((moonbit_string_t)moonbit_string_literal_24.data);
  }
  if (_M0L4selfS197 == 0) {
    return (moonbit_string_t)moonbit_string_literal_25.data;
  }
  _M0L12is__negativeS198 = _M0L4selfS197 < 0;
  if (_M0L12is__negativeS198) {
    int32_t _M0L6_2atmpS634 = -_M0L4selfS197;
    _M0L3numS199 = *(uint32_t*)&_M0L6_2atmpS634;
  } else {
    _M0L3numS199 = *(uint32_t*)&_M0L4selfS197;
  }
  switch (_M0L5radixS196) {
    case 10: {
      int32_t _M0L10digit__lenS201;
      int32_t _M0L6_2atmpS631;
      int32_t _M0L10total__lenS202;
      uint16_t* _M0L6bufferS203;
      int32_t _M0L12digit__startS204;
      #line 235 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
      _M0L10digit__lenS201 = _M0FPB12dec__count32(_M0L3numS199);
      if (_M0L12is__negativeS198) {
        _M0L6_2atmpS631 = 1;
      } else {
        _M0L6_2atmpS631 = 0;
      }
      _M0L10total__lenS202 = _M0L10digit__lenS201 + _M0L6_2atmpS631;
      _M0L6bufferS203
      = (uint16_t*)moonbit_make_string(_M0L10total__lenS202, 0);
      if (_M0L12is__negativeS198) {
        _M0L12digit__startS204 = 1;
      } else {
        _M0L12digit__startS204 = 0;
      }
      moonbit_incref(_M0L6bufferS203);
      #line 239 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
      _M0FPB20int__to__string__dec(_M0L6bufferS203, _M0L3numS199, _M0L12digit__startS204, _M0L10total__lenS202);
      _M0L6bufferS200 = _M0L6bufferS203;
      break;
    }
    
    case 16: {
      int32_t _M0L10digit__lenS205;
      int32_t _M0L6_2atmpS632;
      int32_t _M0L10total__lenS206;
      uint16_t* _M0L6bufferS207;
      int32_t _M0L12digit__startS208;
      #line 243 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
      _M0L10digit__lenS205 = _M0FPB12hex__count32(_M0L3numS199);
      if (_M0L12is__negativeS198) {
        _M0L6_2atmpS632 = 1;
      } else {
        _M0L6_2atmpS632 = 0;
      }
      _M0L10total__lenS206 = _M0L10digit__lenS205 + _M0L6_2atmpS632;
      _M0L6bufferS207
      = (uint16_t*)moonbit_make_string(_M0L10total__lenS206, 0);
      if (_M0L12is__negativeS198) {
        _M0L12digit__startS208 = 1;
      } else {
        _M0L12digit__startS208 = 0;
      }
      moonbit_incref(_M0L6bufferS207);
      #line 247 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
      _M0FPB20int__to__string__hex(_M0L6bufferS207, _M0L3numS199, _M0L12digit__startS208, _M0L10total__lenS206);
      _M0L6bufferS200 = _M0L6bufferS207;
      break;
    }
    default: {
      int32_t _M0L10digit__lenS209;
      int32_t _M0L6_2atmpS633;
      int32_t _M0L10total__lenS210;
      uint16_t* _M0L6bufferS211;
      int32_t _M0L12digit__startS212;
      #line 251 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
      _M0L10digit__lenS209
      = _M0FPB14radix__count32(_M0L3numS199, _M0L5radixS196);
      if (_M0L12is__negativeS198) {
        _M0L6_2atmpS633 = 1;
      } else {
        _M0L6_2atmpS633 = 0;
      }
      _M0L10total__lenS210 = _M0L10digit__lenS209 + _M0L6_2atmpS633;
      _M0L6bufferS211
      = (uint16_t*)moonbit_make_string(_M0L10total__lenS210, 0);
      if (_M0L12is__negativeS198) {
        _M0L12digit__startS212 = 1;
      } else {
        _M0L12digit__startS212 = 0;
      }
      moonbit_incref(_M0L6bufferS211);
      #line 255 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
      _M0FPB24int__to__string__generic(_M0L6bufferS211, _M0L3numS199, _M0L12digit__startS212, _M0L10total__lenS210, _M0L5radixS196);
      _M0L6bufferS200 = _M0L6bufferS211;
      break;
    }
  }
  if (_M0L12is__negativeS198) {
    _M0L6bufferS200[0] = 45;
  }
  return _M0L6bufferS200;
}

int32_t _M0FPB14radix__count32(
  uint32_t _M0L5valueS190,
  int32_t _M0L5radixS192
) {
  uint32_t _M0L4baseS191;
  uint32_t _M0L3numS193;
  int32_t _M0L5countS194;
  #line 189 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
  if (_M0L5valueS190 == 0u) {
    return 1;
  }
  _M0L4baseS191 = *(uint32_t*)&_M0L5radixS192;
  _M0L3numS193 = _M0L5valueS190;
  _M0L5countS194 = 0;
  while (1) {
    if (_M0L3numS193 > 0u) {
      uint32_t _M0L6_2atmpS629 = _M0L3numS193 / _M0L4baseS191;
      int32_t _M0L6_2atmpS630 = _M0L5countS194 + 1;
      _M0L3numS193 = _M0L6_2atmpS629;
      _M0L5countS194 = _M0L6_2atmpS630;
      continue;
    } else {
      return _M0L5countS194;
    }
    break;
  }
}

int32_t _M0FPB12hex__count32(uint32_t _M0L5valueS188) {
  #line 177 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
  if (_M0L5valueS188 == 0u) {
    return 1;
  } else {
    int32_t _M0L14leading__zerosS189;
    int32_t _M0L6_2atmpS628;
    int32_t _M0L6_2atmpS627;
    #line 182 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
    _M0L14leading__zerosS189 = moonbit_clz32(_M0L5valueS188);
    _M0L6_2atmpS628 = 31 - _M0L14leading__zerosS189;
    _M0L6_2atmpS627 = _M0L6_2atmpS628 / 4;
    return _M0L6_2atmpS627 + 1;
  }
}

int32_t _M0FPB12dec__count32(uint32_t _M0L5valueS187) {
  #line 143 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
  if (_M0L5valueS187 >= 100000u) {
    if (_M0L5valueS187 >= 10000000u) {
      if (_M0L5valueS187 >= 1000000000u) {
        return 10;
      } else if (_M0L5valueS187 >= 100000000u) {
        return 9;
      } else {
        return 8;
      }
    } else if (_M0L5valueS187 >= 1000000u) {
      return 7;
    } else {
      return 6;
    }
  } else if (_M0L5valueS187 >= 1000u) {
    if (_M0L5valueS187 >= 10000u) {
      return 5;
    } else {
      return 4;
    }
  } else if (_M0L5valueS187 >= 100u) {
    return 3;
  } else if (_M0L5valueS187 >= 10u) {
    return 2;
  } else {
    return 1;
  }
}

int32_t _M0FPB20int__to__string__dec(
  uint16_t* _M0L6bufferS173,
  uint32_t _M0L3numS185,
  int32_t _M0L12digit__startS174,
  int32_t _M0L10total__lenS186
) {
  int32_t _M0L6_2atmpS626;
  uint32_t _M0L3numS163;
  int32_t _M0L6offsetS164;
  #line 88 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
  _M0L6_2atmpS626 = _M0L10total__lenS186 - _M0L12digit__startS174;
  _M0L3numS163 = _M0L3numS185;
  _M0L6offsetS164 = _M0L6_2atmpS626;
  while (1) {
    if (_M0L3numS163 >= 10000u) {
      uint32_t _M0L1tS165 = _M0L3numS163 / 10000u;
      uint32_t _M0L6_2atmpS603 = _M0L3numS163 % 10000u;
      int32_t _M0L1rS166 = *(int32_t*)&_M0L6_2atmpS603;
      int32_t _M0L2d1S167 = _M0L1rS166 / 100;
      int32_t _M0L2d2S168 = _M0L1rS166 % 100;
      int32_t _M0L6_2atmpS602 = _M0L2d1S167 / 10;
      int32_t _M0L6_2atmpS601 = 48 + _M0L6_2atmpS602;
      int32_t _M0L6d1__hiS169 = (uint16_t)_M0L6_2atmpS601;
      int32_t _M0L6_2atmpS600 = _M0L2d1S167 % 10;
      int32_t _M0L6_2atmpS599 = 48 + _M0L6_2atmpS600;
      int32_t _M0L6d1__loS170 = (uint16_t)_M0L6_2atmpS599;
      int32_t _M0L6_2atmpS598 = _M0L2d2S168 / 10;
      int32_t _M0L6_2atmpS597 = 48 + _M0L6_2atmpS598;
      int32_t _M0L6d2__hiS171 = (uint16_t)_M0L6_2atmpS597;
      int32_t _M0L6_2atmpS596 = _M0L2d2S168 % 10;
      int32_t _M0L6_2atmpS595 = 48 + _M0L6_2atmpS596;
      int32_t _M0L6d2__loS172 = (uint16_t)_M0L6_2atmpS595;
      int32_t _M0L6_2atmpS587 = _M0L12digit__startS174 + _M0L6offsetS164;
      int32_t _M0L6_2atmpS586 = _M0L6_2atmpS587 - 4;
      int32_t _M0L6_2atmpS589;
      int32_t _M0L6_2atmpS588;
      int32_t _M0L6_2atmpS591;
      int32_t _M0L6_2atmpS590;
      int32_t _M0L6_2atmpS593;
      int32_t _M0L6_2atmpS592;
      int32_t _M0L6_2atmpS594;
      _M0L6bufferS173[_M0L6_2atmpS586] = _M0L6d1__hiS169;
      _M0L6_2atmpS589 = _M0L12digit__startS174 + _M0L6offsetS164;
      _M0L6_2atmpS588 = _M0L6_2atmpS589 - 3;
      _M0L6bufferS173[_M0L6_2atmpS588] = _M0L6d1__loS170;
      _M0L6_2atmpS591 = _M0L12digit__startS174 + _M0L6offsetS164;
      _M0L6_2atmpS590 = _M0L6_2atmpS591 - 2;
      _M0L6bufferS173[_M0L6_2atmpS590] = _M0L6d2__hiS171;
      _M0L6_2atmpS593 = _M0L12digit__startS174 + _M0L6offsetS164;
      _M0L6_2atmpS592 = _M0L6_2atmpS593 - 1;
      _M0L6bufferS173[_M0L6_2atmpS592] = _M0L6d2__loS172;
      _M0L6_2atmpS594 = _M0L6offsetS164 - 4;
      _M0L3numS163 = _M0L1tS165;
      _M0L6offsetS164 = _M0L6_2atmpS594;
      continue;
    } else {
      int32_t _M0L6_2atmpS625 = *(int32_t*)&_M0L3numS163;
      int32_t _M0L9remainingS176 = _M0L6_2atmpS625;
      int32_t _M0L6offsetS177 = _M0L6offsetS164;
      while (1) {
        if (_M0L9remainingS176 >= 100) {
          int32_t _M0L1tS178 = _M0L9remainingS176 / 100;
          int32_t _M0L1dS179 = _M0L9remainingS176 % 100;
          int32_t _M0L6_2atmpS612 = _M0L1dS179 / 10;
          int32_t _M0L6_2atmpS611 = 48 + _M0L6_2atmpS612;
          int32_t _M0L5d__hiS180 = (uint16_t)_M0L6_2atmpS611;
          int32_t _M0L6_2atmpS610 = _M0L1dS179 % 10;
          int32_t _M0L6_2atmpS609 = 48 + _M0L6_2atmpS610;
          int32_t _M0L5d__loS181 = (uint16_t)_M0L6_2atmpS609;
          int32_t _M0L6_2atmpS605 = _M0L12digit__startS174 + _M0L6offsetS177;
          int32_t _M0L6_2atmpS604 = _M0L6_2atmpS605 - 2;
          int32_t _M0L6_2atmpS607;
          int32_t _M0L6_2atmpS606;
          int32_t _M0L6_2atmpS608;
          _M0L6bufferS173[_M0L6_2atmpS604] = _M0L5d__hiS180;
          _M0L6_2atmpS607 = _M0L12digit__startS174 + _M0L6offsetS177;
          _M0L6_2atmpS606 = _M0L6_2atmpS607 - 1;
          _M0L6bufferS173[_M0L6_2atmpS606] = _M0L5d__loS181;
          _M0L6_2atmpS608 = _M0L6offsetS177 - 2;
          _M0L9remainingS176 = _M0L1tS178;
          _M0L6offsetS177 = _M0L6_2atmpS608;
          continue;
        } else if (_M0L9remainingS176 >= 10) {
          int32_t _M0L6_2atmpS620 = _M0L9remainingS176 / 10;
          int32_t _M0L6_2atmpS619 = 48 + _M0L6_2atmpS620;
          int32_t _M0L5d__hiS183 = (uint16_t)_M0L6_2atmpS619;
          int32_t _M0L6_2atmpS618 = _M0L9remainingS176 % 10;
          int32_t _M0L6_2atmpS617 = 48 + _M0L6_2atmpS618;
          int32_t _M0L5d__loS184 = (uint16_t)_M0L6_2atmpS617;
          int32_t _M0L6_2atmpS614 = _M0L12digit__startS174 + _M0L6offsetS177;
          int32_t _M0L6_2atmpS613 = _M0L6_2atmpS614 - 2;
          int32_t _M0L6_2atmpS616;
          int32_t _M0L6_2atmpS615;
          _M0L6bufferS173[_M0L6_2atmpS613] = _M0L5d__hiS183;
          _M0L6_2atmpS616 = _M0L12digit__startS174 + _M0L6offsetS177;
          _M0L6_2atmpS615 = _M0L6_2atmpS616 - 1;
          _M0L6bufferS173[_M0L6_2atmpS615] = _M0L5d__loS184;
          moonbit_decref(_M0L6bufferS173);
        } else {
          int32_t _M0L6_2atmpS624 = _M0L12digit__startS174 + _M0L6offsetS177;
          int32_t _M0L6_2atmpS621 = _M0L6_2atmpS624 - 1;
          int32_t _M0L6_2atmpS623 = 48 + _M0L9remainingS176;
          int32_t _M0L6_2atmpS622 = (uint16_t)_M0L6_2atmpS623;
          _M0L6bufferS173[_M0L6_2atmpS621] = _M0L6_2atmpS622;
          moonbit_decref(_M0L6bufferS173);
        }
        break;
      }
    }
    break;
  }
  return 0;
}

int32_t _M0FPB24int__to__string__generic(
  uint16_t* _M0L6bufferS153,
  uint32_t _M0L3numS157,
  int32_t _M0L12digit__startS154,
  int32_t _M0L10total__lenS156,
  int32_t _M0L5radixS147
) {
  uint32_t _M0L4baseS146;
  int32_t _M0L6_2atmpS571;
  int32_t _M0L6_2atmpS570;
  #line 57 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
  _M0L4baseS146 = *(uint32_t*)&_M0L5radixS147;
  _M0L6_2atmpS571 = _M0L5radixS147 - 1;
  _M0L6_2atmpS570 = _M0L5radixS147 & _M0L6_2atmpS571;
  if (_M0L6_2atmpS570 == 0) {
    int32_t _M0L5shiftS148;
    uint32_t _M0L4maskS149;
    int32_t _M0L6_2atmpS578;
    int32_t _M0L6offsetS150;
    uint32_t _M0L1nS151;
    #line 68 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
    _M0L5shiftS148 = moonbit_ctz32(_M0L5radixS147);
    _M0L4maskS149 = _M0L4baseS146 - 1u;
    _M0L6_2atmpS578 = _M0L10total__lenS156 - _M0L12digit__startS154;
    _M0L6offsetS150 = _M0L6_2atmpS578;
    _M0L1nS151 = _M0L3numS157;
    while (1) {
      if (_M0L1nS151 > 0u) {
        uint32_t _M0L6_2atmpS577 = _M0L1nS151 & _M0L4maskS149;
        int32_t _M0L5digitS152 = *(int32_t*)&_M0L6_2atmpS577;
        int32_t _M0L6_2atmpS574 = _M0L12digit__startS154 + _M0L6offsetS150;
        int32_t _M0L6_2atmpS572 = _M0L6_2atmpS574 - 1;
        int32_t _M0L6_2atmpS573 =
          ((moonbit_string_t)moonbit_string_literal_26.data)[_M0L5digitS152];
        int32_t _M0L6_2atmpS575;
        uint32_t _M0L6_2atmpS576;
        _M0L6bufferS153[_M0L6_2atmpS572] = _M0L6_2atmpS573;
        _M0L6_2atmpS575 = _M0L6offsetS150 - 1;
        _M0L6_2atmpS576 = _M0L1nS151 >> (_M0L5shiftS148 & 31);
        _M0L6offsetS150 = _M0L6_2atmpS575;
        _M0L1nS151 = _M0L6_2atmpS576;
        continue;
      } else {
        moonbit_decref(_M0L6bufferS153);
      }
      break;
    }
  } else {
    int32_t _M0L6_2atmpS585 = _M0L10total__lenS156 - _M0L12digit__startS154;
    int32_t _M0L6offsetS158 = _M0L6_2atmpS585;
    uint32_t _M0L1nS159 = _M0L3numS157;
    while (1) {
      if (_M0L1nS159 > 0u) {
        uint32_t _M0L1qS160 = _M0L1nS159 / _M0L4baseS146;
        uint32_t _M0L6_2atmpS584 = _M0L1qS160 * _M0L4baseS146;
        uint32_t _M0L6_2atmpS583 = _M0L1nS159 - _M0L6_2atmpS584;
        int32_t _M0L5digitS161 = *(int32_t*)&_M0L6_2atmpS583;
        int32_t _M0L6_2atmpS581 = _M0L12digit__startS154 + _M0L6offsetS158;
        int32_t _M0L6_2atmpS579 = _M0L6_2atmpS581 - 1;
        int32_t _M0L6_2atmpS580 =
          ((moonbit_string_t)moonbit_string_literal_26.data)[_M0L5digitS161];
        int32_t _M0L6_2atmpS582;
        _M0L6bufferS153[_M0L6_2atmpS579] = _M0L6_2atmpS580;
        _M0L6_2atmpS582 = _M0L6offsetS158 - 1;
        _M0L6offsetS158 = _M0L6_2atmpS582;
        _M0L1nS159 = _M0L1qS160;
        continue;
      } else {
        moonbit_decref(_M0L6bufferS153);
      }
      break;
    }
  }
  return 0;
}

int32_t _M0FPB20int__to__string__hex(
  uint16_t* _M0L6bufferS140,
  uint32_t _M0L3numS145,
  int32_t _M0L12digit__startS141,
  int32_t _M0L10total__lenS144
) {
  int32_t _M0L6_2atmpS569;
  int32_t _M0L6offsetS135;
  uint32_t _M0L1nS136;
  #line 29 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\to_string.mbt"
  _M0L6_2atmpS569 = _M0L10total__lenS144 - _M0L12digit__startS141;
  _M0L6offsetS135 = _M0L6_2atmpS569;
  _M0L1nS136 = _M0L3numS145;
  while (1) {
    if (_M0L6offsetS135 >= 2) {
      uint32_t _M0L6_2atmpS566 = _M0L1nS136 & 255u;
      int32_t _M0L9byte__valS137 = *(int32_t*)&_M0L6_2atmpS566;
      int32_t _M0L2hiS138 = _M0L9byte__valS137 / 16;
      int32_t _M0L2loS139 = _M0L9byte__valS137 % 16;
      int32_t _M0L6_2atmpS560 = _M0L12digit__startS141 + _M0L6offsetS135;
      int32_t _M0L6_2atmpS558 = _M0L6_2atmpS560 - 2;
      int32_t _M0L6_2atmpS559 =
        ((moonbit_string_t)moonbit_string_literal_26.data)[_M0L2hiS138];
      int32_t _M0L6_2atmpS563;
      int32_t _M0L6_2atmpS561;
      int32_t _M0L6_2atmpS562;
      int32_t _M0L6_2atmpS564;
      uint32_t _M0L6_2atmpS565;
      _M0L6bufferS140[_M0L6_2atmpS558] = _M0L6_2atmpS559;
      _M0L6_2atmpS563 = _M0L12digit__startS141 + _M0L6offsetS135;
      _M0L6_2atmpS561 = _M0L6_2atmpS563 - 1;
      _M0L6_2atmpS562
      = ((moonbit_string_t)moonbit_string_literal_26.data)[
        _M0L2loS139
      ];
      _M0L6bufferS140[_M0L6_2atmpS561] = _M0L6_2atmpS562;
      _M0L6_2atmpS564 = _M0L6offsetS135 - 2;
      _M0L6_2atmpS565 = _M0L1nS136 >> 8;
      _M0L6offsetS135 = _M0L6_2atmpS564;
      _M0L1nS136 = _M0L6_2atmpS565;
      continue;
    } else if (_M0L6offsetS135 == 1) {
      uint32_t _M0L6_2atmpS568 = _M0L1nS136 & 15u;
      int32_t _M0L6nibbleS143 = *(int32_t*)&_M0L6_2atmpS568;
      int32_t _M0L6_2atmpS567 =
        ((moonbit_string_t)moonbit_string_literal_26.data)[_M0L6nibbleS143];
      _M0L6bufferS140[_M0L12digit__startS141] = _M0L6_2atmpS567;
      moonbit_decref(_M0L6bufferS140);
    } else {
      moonbit_decref(_M0L6bufferS140);
    }
    break;
  }
  return 0;
}

moonbit_string_t _M0IP016_24default__implPB4Show10to__stringGRPB7FailureE(
  void* _M0L4selfS134
) {
  struct _M0TPB13StringBuilder* _M0L6loggerS133;
  struct _M0TPB6Logger _M0L6_2atmpS557;
  #line 140 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  #line 141 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0L6loggerS133 = _M0MPB13StringBuilder11new_2einner(0);
  moonbit_incref(_M0L6loggerS133);
  _M0L6_2atmpS557
  = (struct _M0TPB6Logger){
    _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id,
      _M0L6loggerS133
  };
  #line 142 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0IPB7FailurePB4Show6output(_M0L4selfS134, _M0L6_2atmpS557);
  #line 143 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  return _M0MPB13StringBuilder10to__string(_M0L6loggerS133);
}

int32_t _M0MPC16string10StringView13start__offset(
  struct _M0TPC16string10StringView _M0L4selfS132
) {
  int32_t _result_967;
  #line 98 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  _result_967 = _M0L4selfS132.$1;
  moonbit_decref(_M0L4selfS132.$0);
  return _result_967;
}

moonbit_string_t _M0MPC16string10StringView4data(
  struct _M0TPC16string10StringView _M0L4selfS131
) {
  #line 91 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  return _M0L4selfS131.$0;
}

int32_t _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE(
  struct _M0TPB13StringBuilder* _M0L4selfS127,
  moonbit_string_t _M0L5valueS128,
  int32_t _M0L5startS129,
  int32_t _M0L3lenS130
) {
  int32_t _M0L6_2atmpS556;
  int64_t _M0L6_2atmpS555;
  struct _M0TPC16string10StringView _M0L6_2atmpS554;
  #line 102 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0L6_2atmpS556 = _M0L5startS129 + _M0L3lenS130;
  _M0L6_2atmpS555 = (int64_t)_M0L6_2atmpS556;
  #line 103 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0L6_2atmpS554
  = _M0MPC16string6String11sub_2einner(_M0L5valueS128, _M0L5startS129, _M0L6_2atmpS555);
  #line 103 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0IPB13StringBuilderPB6Logger11write__view(_M0L4selfS127, _M0L6_2atmpS554);
  return 0;
}

struct _M0TPC16string10StringView _M0MPC16string6String11sub_2einner(
  moonbit_string_t _M0L4selfS120,
  int32_t _M0L5startS126,
  int64_t _M0L3endS122
) {
  int32_t _M0L3lenS119;
  int32_t _M0L3endS121;
  int32_t _M0L5startS125;
  int32_t _if__result_968;
  #line 639 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  _M0L3lenS119 = Moonbit_array_length(_M0L4selfS120);
  if (_M0L3endS122 == 4294967296ll) {
    _M0L3endS121 = _M0L3lenS119;
  } else {
    int64_t _M0L7_2aSomeS123 = _M0L3endS122;
    int32_t _M0L6_2aendS124 = (int32_t)_M0L7_2aSomeS123;
    if (_M0L6_2aendS124 < 0) {
      _M0L3endS121 = _M0L3lenS119 + _M0L6_2aendS124;
    } else {
      _M0L3endS121 = _M0L6_2aendS124;
    }
  }
  if (_M0L5startS126 < 0) {
    _M0L5startS125 = _M0L3lenS119 + _M0L5startS126;
  } else {
    _M0L5startS125 = _M0L5startS126;
  }
  if (_M0L5startS125 >= 0) {
    if (_M0L5startS125 <= _M0L3endS121) {
      _if__result_968 = _M0L3endS121 <= _M0L3lenS119;
    } else {
      _if__result_968 = 0;
    }
  } else {
    _if__result_968 = 0;
  }
  if (_if__result_968) {
    if (_M0L5startS125 < _M0L3lenS119) {
      int32_t _M0L6_2atmpS551 = _M0L4selfS120[_M0L5startS125];
      int32_t _M0L6_2atmpS550;
      #line 649 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
      _M0L6_2atmpS550
      = _M0MPC16uint166UInt1623is__trailing__surrogate(_M0L6_2atmpS551);
      if (!_M0L6_2atmpS550) {
        
      } else {
        #line 649 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
        moonbit_panic();
      }
    }
    if (_M0L3endS121 < _M0L3lenS119) {
      int32_t _M0L6_2atmpS553 = _M0L4selfS120[_M0L3endS121];
      int32_t _M0L6_2atmpS552;
      #line 652 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
      _M0L6_2atmpS552
      = _M0MPC16uint166UInt1623is__trailing__surrogate(_M0L6_2atmpS553);
      if (!_M0L6_2atmpS552) {
        
      } else {
        #line 652 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
        moonbit_panic();
      }
    }
    return (struct _M0TPC16string10StringView){_M0L5startS125,
                                                 _M0L3endS121,
                                                 _M0L4selfS120};
  } else {
    moonbit_decref(_M0L4selfS120);
    #line 647 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
    moonbit_panic();
  }
}

int32_t _M0IPB13StringBuilderPB6Logger13write__string(
  struct _M0TPB13StringBuilder* _M0L4selfS118,
  moonbit_string_t _M0L3strS117
) {
  int32_t _M0L8str__lenS116;
  int32_t _M0L3lenS545;
  int32_t _M0L6_2atmpS544;
  uint16_t* _M0L4dataS546;
  int32_t _M0L3lenS547;
  int32_t _M0L3lenS549;
  int32_t _M0L6_2atmpS548;
  #line 81 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L8str__lenS116 = Moonbit_array_length(_M0L3strS117);
  _M0L3lenS545 = _M0L4selfS118->$1;
  _M0L6_2atmpS544 = _M0L3lenS545 + _M0L8str__lenS116;
  moonbit_incref(_M0L4selfS118);
  #line 83 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0MPB13StringBuilder19grow__if__necessary(_M0L4selfS118, _M0L6_2atmpS544);
  _M0L4dataS546 = _M0L4selfS118->$0;
  _M0L3lenS547 = _M0L4selfS118->$1;
  moonbit_incref(_M0L4dataS546);
  #line 84 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0MPC15array10FixedArray26unsafe__blit__from__string(_M0L4dataS546, _M0L3lenS547, _M0L3strS117, 0, _M0L8str__lenS116);
  _M0L3lenS549 = _M0L4selfS118->$1;
  _M0L6_2atmpS548 = _M0L3lenS549 + _M0L8str__lenS116;
  _M0L4selfS118->$1 = _M0L6_2atmpS548;
  moonbit_decref(_M0L4selfS118);
  return 0;
}

int32_t _M0MPC15array10FixedArray26unsafe__blit__from__string(
  uint16_t* _M0L4selfS112,
  int32_t _M0L11dst__offsetS115,
  moonbit_string_t _M0L3strS113,
  int32_t _M0L11str__offsetS108,
  int32_t _M0L3lenS109
) {
  int32_t _M0L16end__str__offsetS107;
  int32_t _M0L1iS110;
  int32_t _M0L1jS111;
  #line 66 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L16end__str__offsetS107 = _M0L11str__offsetS108 + _M0L3lenS109;
  _M0L1iS110 = _M0L11str__offsetS108;
  _M0L1jS111 = _M0L11dst__offsetS115;
  while (1) {
    if (_M0L1iS110 < _M0L16end__str__offsetS107) {
      int32_t _M0L6_2atmpS541 = _M0L3strS113[_M0L1iS110];
      int32_t _M0L6_2atmpS542;
      int32_t _M0L6_2atmpS543;
      if (
        _M0L1jS111 < 0 || _M0L1jS111 >= Moonbit_array_length(_M0L4selfS112)
      ) {
        #line 75 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
        moonbit_panic();
      }
      _M0L4selfS112[_M0L1jS111] = _M0L6_2atmpS541;
      _M0L6_2atmpS542 = _M0L1iS110 + 1;
      _M0L6_2atmpS543 = _M0L1jS111 + 1;
      _M0L1iS110 = _M0L6_2atmpS542;
      _M0L1jS111 = _M0L6_2atmpS543;
      continue;
    } else {
      moonbit_decref(_M0L3strS113);
      moonbit_decref(_M0L4selfS112);
    }
    break;
  }
  return 0;
}

moonbit_string_t _M0MPC16string6String14escape_2einner(
  moonbit_string_t _M0L4selfS105,
  int32_t _M0L5quoteS106
) {
  struct _M0TPB13StringBuilder* _M0L3bufS104;
  int32_t _M0L6_2atmpS540;
  struct _M0TPC16string10StringView _M0L6_2atmpS538;
  struct _M0TPB6Logger _M0L6_2atmpS539;
  #line 145 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  #line 146 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L3bufS104 = _M0MPB13StringBuilder11new_2einner(0);
  _M0L6_2atmpS540 = Moonbit_array_length(_M0L4selfS105);
  _M0L6_2atmpS538
  = (struct _M0TPC16string10StringView){
    0, _M0L6_2atmpS540, _M0L4selfS105
  };
  moonbit_incref(_M0L3bufS104);
  _M0L6_2atmpS539
  = (struct _M0TPB6Logger){
    _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id,
      _M0L3bufS104
  };
  #line 147 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0MPC16string10StringView18escape__to_2einner(_M0L6_2atmpS538, _M0L6_2atmpS539, _M0L5quoteS106);
  #line 148 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  return _M0MPB13StringBuilder10to__string(_M0L3bufS104);
}

int32_t _M0MPC16string10StringView18escape__to_2einner(
  struct _M0TPC16string10StringView _M0L4selfS96,
  struct _M0TPB6Logger _M0L6loggerS94,
  int32_t _M0L5quoteS93
) {
  int32_t _M0L3lenS95;
  struct _M0TURPB6LoggerRPC16string10StringViewE* _M0L6_2aenvS97;
  int32_t _M0L1iS98;
  int32_t _M0L3segS99;
  #line 179 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  if (_M0L5quoteS93) {
    if (_M0L6loggerS94.$1) {
      moonbit_incref(_M0L6loggerS94.$1);
    }
    #line 185 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6loggerS94.$0->$method_3(_M0L6loggerS94.$1, 34);
  }
  moonbit_incref(_M0L4selfS96.$0);
  #line 187 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L3lenS95 = _M0MPC16string10StringView6length(_M0L4selfS96);
  if (_M0L6loggerS94.$1) {
    moonbit_incref(_M0L6loggerS94.$1);
  }
  moonbit_incref(_M0L4selfS96.$0);
  _M0L6_2aenvS97
  = (struct _M0TURPB6LoggerRPC16string10StringViewE*)moonbit_malloc(sizeof(struct _M0TURPB6LoggerRPC16string10StringViewE));
  Moonbit_object_header(_M0L6_2aenvS97)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TURPB6LoggerRPC16string10StringViewE, $0_0) >> 2, 3, 0);
  _M0L6_2aenvS97->$0_0 = _M0L6loggerS94.$0;
  _M0L6_2aenvS97->$0_1 = _M0L6loggerS94.$1;
  _M0L6_2aenvS97->$1_0 = _M0L4selfS96.$0;
  _M0L6_2aenvS97->$1_1 = _M0L4selfS96.$1;
  _M0L6_2aenvS97->$1_2 = _M0L4selfS96.$2;
  _M0L1iS98 = 0;
  _M0L3segS99 = 0;
  _2afor_100:;
  while (1) {
    int32_t _M0L4codeS101;
    int32_t _M0L1cS103;
    int32_t _M0L6_2atmpS522;
    int32_t _M0L6_2atmpS523;
    int32_t _M0L6_2atmpS524;
    int32_t _tmp_973;
    int32_t _tmp_974;
    if (_M0L1iS98 >= _M0L3lenS95) {
      moonbit_decref(_M0L4selfS96.$0);
      #line 195 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
      _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(_M0L6_2aenvS97, _M0L3segS99, _M0L1iS98);
      break;
    }
    moonbit_incref(_M0L4selfS96.$0);
    #line 198 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L4codeS101
    = _M0MPC16string10StringView11unsafe__get(_M0L4selfS96, _M0L1iS98);
    switch (_M0L4codeS101) {
      case 34: {
        _M0L1cS103 = _M0L4codeS101;
        goto join_102;
        break;
      }
      
      case 92: {
        _M0L1cS103 = _M0L4codeS101;
        goto join_102;
        break;
      }
      
      case 10: {
        int32_t _M0L6_2atmpS525;
        int32_t _M0L6_2atmpS526;
        moonbit_incref(_M0L6_2aenvS97);
        #line 207 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(_M0L6_2aenvS97, _M0L3segS99, _M0L1iS98);
        if (_M0L6loggerS94.$1) {
          moonbit_incref(_M0L6loggerS94.$1);
        }
        #line 208 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0L6loggerS94.$0->$method_0(_M0L6loggerS94.$1, (moonbit_string_t)moonbit_string_literal_27.data);
        _M0L6_2atmpS525 = _M0L1iS98 + 1;
        _M0L6_2atmpS526 = _M0L1iS98 + 1;
        _M0L1iS98 = _M0L6_2atmpS525;
        _M0L3segS99 = _M0L6_2atmpS526;
        goto _2afor_100;
        break;
      }
      
      case 13: {
        int32_t _M0L6_2atmpS527;
        int32_t _M0L6_2atmpS528;
        moonbit_incref(_M0L6_2aenvS97);
        #line 212 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(_M0L6_2aenvS97, _M0L3segS99, _M0L1iS98);
        if (_M0L6loggerS94.$1) {
          moonbit_incref(_M0L6loggerS94.$1);
        }
        #line 213 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0L6loggerS94.$0->$method_0(_M0L6loggerS94.$1, (moonbit_string_t)moonbit_string_literal_28.data);
        _M0L6_2atmpS527 = _M0L1iS98 + 1;
        _M0L6_2atmpS528 = _M0L1iS98 + 1;
        _M0L1iS98 = _M0L6_2atmpS527;
        _M0L3segS99 = _M0L6_2atmpS528;
        goto _2afor_100;
        break;
      }
      
      case 8: {
        int32_t _M0L6_2atmpS529;
        int32_t _M0L6_2atmpS530;
        moonbit_incref(_M0L6_2aenvS97);
        #line 217 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(_M0L6_2aenvS97, _M0L3segS99, _M0L1iS98);
        if (_M0L6loggerS94.$1) {
          moonbit_incref(_M0L6loggerS94.$1);
        }
        #line 218 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0L6loggerS94.$0->$method_0(_M0L6loggerS94.$1, (moonbit_string_t)moonbit_string_literal_29.data);
        _M0L6_2atmpS529 = _M0L1iS98 + 1;
        _M0L6_2atmpS530 = _M0L1iS98 + 1;
        _M0L1iS98 = _M0L6_2atmpS529;
        _M0L3segS99 = _M0L6_2atmpS530;
        goto _2afor_100;
        break;
      }
      
      case 9: {
        int32_t _M0L6_2atmpS531;
        int32_t _M0L6_2atmpS532;
        moonbit_incref(_M0L6_2aenvS97);
        #line 222 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(_M0L6_2aenvS97, _M0L3segS99, _M0L1iS98);
        if (_M0L6loggerS94.$1) {
          moonbit_incref(_M0L6loggerS94.$1);
        }
        #line 223 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
        _M0L6loggerS94.$0->$method_0(_M0L6loggerS94.$1, (moonbit_string_t)moonbit_string_literal_30.data);
        _M0L6_2atmpS531 = _M0L1iS98 + 1;
        _M0L6_2atmpS532 = _M0L1iS98 + 1;
        _M0L1iS98 = _M0L6_2atmpS531;
        _M0L3segS99 = _M0L6_2atmpS532;
        goto _2afor_100;
        break;
      }
      default: {
        if (_M0L4codeS101 < 32) {
          int32_t _M0L6_2atmpS534;
          moonbit_string_t _M0L6_2atmpS533;
          int32_t _M0L6_2atmpS535;
          int32_t _M0L6_2atmpS536;
          moonbit_incref(_M0L6_2aenvS97);
          #line 228 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
          _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(_M0L6_2aenvS97, _M0L3segS99, _M0L1iS98);
          if (_M0L6loggerS94.$1) {
            moonbit_incref(_M0L6loggerS94.$1);
          }
          #line 229 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
          _M0L6loggerS94.$0->$method_0(_M0L6loggerS94.$1, (moonbit_string_t)moonbit_string_literal_31.data);
          _M0L6_2atmpS534 = _M0L4codeS101 & 0xff;
          #line 230 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
          _M0L6_2atmpS533 = _M0MPC14byte4Byte7to__hex(_M0L6_2atmpS534);
          if (_M0L6loggerS94.$1) {
            moonbit_incref(_M0L6loggerS94.$1);
          }
          #line 230 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
          _M0L6loggerS94.$0->$method_0(_M0L6loggerS94.$1, _M0L6_2atmpS533);
          if (_M0L6loggerS94.$1) {
            moonbit_incref(_M0L6loggerS94.$1);
          }
          #line 231 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
          _M0L6loggerS94.$0->$method_3(_M0L6loggerS94.$1, 125);
          _M0L6_2atmpS535 = _M0L1iS98 + 1;
          _M0L6_2atmpS536 = _M0L1iS98 + 1;
          _M0L1iS98 = _M0L6_2atmpS535;
          _M0L3segS99 = _M0L6_2atmpS536;
          goto _2afor_100;
        } else {
          int32_t _M0L6_2atmpS537 = _M0L1iS98 + 1;
          int32_t _tmp_972 = _M0L3segS99;
          _M0L1iS98 = _M0L6_2atmpS537;
          _M0L3segS99 = _tmp_972;
          goto _2afor_100;
        }
        break;
      }
    }
    goto joinlet_971;
    join_102:;
    moonbit_incref(_M0L6_2aenvS97);
    #line 201 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(_M0L6_2aenvS97, _M0L3segS99, _M0L1iS98);
    if (_M0L6loggerS94.$1) {
      moonbit_incref(_M0L6loggerS94.$1);
    }
    #line 202 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6loggerS94.$0->$method_3(_M0L6loggerS94.$1, 92);
    #line 203 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6_2atmpS522 = _M0MPC16uint166UInt1616unsafe__to__char(_M0L1cS103);
    if (_M0L6loggerS94.$1) {
      moonbit_incref(_M0L6loggerS94.$1);
    }
    #line 203 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6loggerS94.$0->$method_3(_M0L6loggerS94.$1, _M0L6_2atmpS522);
    _M0L6_2atmpS523 = _M0L1iS98 + 1;
    _M0L6_2atmpS524 = _M0L1iS98 + 1;
    _M0L1iS98 = _M0L6_2atmpS523;
    _M0L3segS99 = _M0L6_2atmpS524;
    continue;
    joinlet_971:;
    _tmp_973 = _M0L1iS98;
    _tmp_974 = _M0L3segS99;
    _M0L1iS98 = _tmp_973;
    _M0L3segS99 = _tmp_974;
    continue;
    break;
  }
  if (_M0L5quoteS93) {
    #line 239 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6loggerS94.$0->$method_3(_M0L6loggerS94.$1, 34);
  } else if (_M0L6loggerS94.$1) {
    moonbit_decref(_M0L6loggerS94.$1);
  }
  return 0;
}

int32_t _M0MPC16string10StringView18escape__to_2einnerN14flush__segmentS3615(
  struct _M0TURPB6LoggerRPC16string10StringViewE* _M0L6_2aenvS89,
  int32_t _M0L3segS92,
  int32_t _M0L1iS91
) {
  struct _M0TPC16string10StringView _M0L4selfS88;
  struct _M0TPB6Logger _M0L8_2afieldS871;
  int32_t _M0L6_2acntS915;
  struct _M0TPB6Logger _M0L6loggerS90;
  #line 188 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L4selfS88
  = (struct _M0TPC16string10StringView){
    _M0L6_2aenvS89->$1_1, _M0L6_2aenvS89->$1_2, _M0L6_2aenvS89->$1_0
  };
  _M0L8_2afieldS871
  = (struct _M0TPB6Logger){
    _M0L6_2aenvS89->$0_0, _M0L6_2aenvS89->$0_1
  };
  _M0L6_2acntS915 = Moonbit_object_header(_M0L6_2aenvS89)->rc;
  if (_M0L6_2acntS915 > 1) {
    int32_t _M0L11_2anew__cntS916 = _M0L6_2acntS915 - 1;
    Moonbit_object_header(_M0L6_2aenvS89)->rc = _M0L11_2anew__cntS916;
    moonbit_incref(_M0L4selfS88.$0);
    if (_M0L8_2afieldS871.$1) {
      moonbit_incref(_M0L8_2afieldS871.$1);
    }
  } else if (_M0L6_2acntS915 == 1) {
    #line 188 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    moonbit_free(_M0L6_2aenvS89);
  }
  _M0L6loggerS90 = _M0L8_2afieldS871;
  if (_M0L1iS91 > _M0L3segS92) {
    int64_t _M0L6_2atmpS521 = (int64_t)_M0L1iS91;
    struct _M0TPC16string10StringView _M0L6_2atmpS520;
    #line 190 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6_2atmpS520
    = _M0MPC16string10StringView11sub_2einner(_M0L4selfS88, _M0L3segS92, _M0L6_2atmpS521);
    #line 190 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6loggerS90.$0->$method_2(_M0L6loggerS90.$1, _M0L6_2atmpS520);
  } else {
    if (_M0L6loggerS90.$1) {
      moonbit_decref(_M0L6loggerS90.$1);
    }
    moonbit_decref(_M0L4selfS88.$0);
  }
  return 0;
}

int32_t _M0MPC16string10StringView11unsafe__get(
  struct _M0TPC16string10StringView _M0L4selfS86,
  int32_t _M0L5indexS87
) {
  moonbit_string_t _M0L3strS517;
  int32_t _M0L5startS519;
  int32_t _M0L6_2atmpS518;
  int32_t _result_975;
  #line 127 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  _M0L3strS517 = _M0L4selfS86.$0;
  _M0L5startS519 = _M0L4selfS86.$1;
  _M0L6_2atmpS518 = _M0L5startS519 + _M0L5indexS87;
  _result_975 = _M0L3strS517[_M0L6_2atmpS518];
  moonbit_decref(_M0L3strS517);
  return _result_975;
}

struct _M0TPC16string10StringView _M0MPC16string10StringView11sub_2einner(
  struct _M0TPC16string10StringView _M0L4selfS79,
  int32_t _M0L5startS85,
  int64_t _M0L3endS81
) {
  moonbit_string_t _M0L3strS516;
  int32_t _M0L8str__lenS78;
  int32_t _M0L8abs__endS80;
  int32_t _M0L10abs__startS84;
  int32_t _M0L5startS504;
  int32_t _if__result_976;
  #line 698 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  _M0L3strS516 = _M0L4selfS79.$0;
  _M0L8str__lenS78 = Moonbit_array_length(_M0L3strS516);
  if (_M0L3endS81 == 4294967296ll) {
    _M0L8abs__endS80 = _M0L4selfS79.$2;
  } else {
    int64_t _M0L7_2aSomeS82 = _M0L3endS81;
    int32_t _M0L6_2aendS83 = (int32_t)_M0L7_2aSomeS82;
    if (_M0L6_2aendS83 < 0) {
      int32_t _M0L3endS514 = _M0L4selfS79.$2;
      _M0L8abs__endS80 = _M0L3endS514 + _M0L6_2aendS83;
    } else {
      int32_t _M0L5startS515 = _M0L4selfS79.$1;
      _M0L8abs__endS80 = _M0L5startS515 + _M0L6_2aendS83;
    }
  }
  if (_M0L5startS85 < 0) {
    int32_t _M0L3endS512 = _M0L4selfS79.$2;
    _M0L10abs__startS84 = _M0L3endS512 + _M0L5startS85;
  } else {
    int32_t _M0L5startS513 = _M0L4selfS79.$1;
    _M0L10abs__startS84 = _M0L5startS513 + _M0L5startS85;
  }
  _M0L5startS504 = _M0L4selfS79.$1;
  if (_M0L10abs__startS84 >= _M0L5startS504) {
    if (_M0L10abs__startS84 <= _M0L8abs__endS80) {
      int32_t _M0L3endS503 = _M0L4selfS79.$2;
      _if__result_976 = _M0L8abs__endS80 <= _M0L3endS503;
    } else {
      _if__result_976 = 0;
    }
  } else {
    _if__result_976 = 0;
  }
  if (_if__result_976) {
    moonbit_string_t _M0L3strS511;
    if (_M0L10abs__startS84 < _M0L8str__lenS78) {
      moonbit_string_t _M0L3strS507 = _M0L4selfS79.$0;
      int32_t _M0L6_2atmpS506 = _M0L3strS507[_M0L10abs__startS84];
      int32_t _M0L6_2atmpS505;
      #line 724 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
      _M0L6_2atmpS505
      = _M0MPC16uint166UInt1623is__trailing__surrogate(_M0L6_2atmpS506);
      if (!_M0L6_2atmpS505) {
        
      } else {
        #line 724 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
        moonbit_panic();
      }
    }
    if (_M0L8abs__endS80 < _M0L8str__lenS78) {
      moonbit_string_t _M0L3strS510 = _M0L4selfS79.$0;
      int32_t _M0L6_2atmpS509 = _M0L3strS510[_M0L8abs__endS80];
      int32_t _M0L6_2atmpS508;
      #line 727 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
      _M0L6_2atmpS508
      = _M0MPC16uint166UInt1623is__trailing__surrogate(_M0L6_2atmpS509);
      if (!_M0L6_2atmpS508) {
        
      } else {
        #line 727 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
        moonbit_panic();
      }
    }
    _M0L3strS511 = _M0L4selfS79.$0;
    return (struct _M0TPC16string10StringView){_M0L10abs__startS84,
                                                 _M0L8abs__endS80,
                                                 _M0L3strS511};
  } else {
    moonbit_decref(_M0L4selfS79.$0);
    #line 718 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
    moonbit_panic();
  }
}

int32_t _M0MPC16string10StringView6length(
  struct _M0TPC16string10StringView _M0L4selfS77
) {
  int32_t _M0L3endS501;
  int32_t _M0L5startS502;
  #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringview.mbt"
  _M0L3endS501 = _M0L4selfS77.$2;
  _M0L5startS502 = _M0L4selfS77.$1;
  moonbit_decref(_M0L4selfS77.$0);
  return _M0L3endS501 - _M0L5startS502;
}

moonbit_string_t _M0MPC14byte4Byte7to__hex(int32_t _M0L1bS76) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS75;
  int32_t _M0L6_2atmpS498;
  int32_t _M0L6_2atmpS497;
  int32_t _M0L6_2atmpS500;
  int32_t _M0L6_2atmpS499;
  struct _M0TPB13StringBuilder* _M0L6_2atmpS496;
  #line 109 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L7_2aselfS75 = _M0MPB13StringBuilder11new_2einner(0);
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L6_2atmpS498 = _M0IPC14byte4BytePB3Div3div(_M0L1bS76, 16);
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L6_2atmpS497
  = _M0MPC14byte4Byte7to__hexN14to__hex__digitS3630(_M0L6_2atmpS498);
  moonbit_incref(_M0L7_2aselfS75);
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0IPB13StringBuilderPB6Logger11write__char(_M0L7_2aselfS75, _M0L6_2atmpS497);
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L6_2atmpS500 = _M0IPC14byte4BytePB3Mod3mod(_M0L1bS76, 16);
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0L6_2atmpS499
  = _M0MPC14byte4Byte7to__hexN14to__hex__digitS3630(_M0L6_2atmpS500);
  moonbit_incref(_M0L7_2aselfS75);
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  _M0IPB13StringBuilderPB6Logger11write__char(_M0L7_2aselfS75, _M0L6_2atmpS499);
  _M0L6_2atmpS496 = _M0L7_2aselfS75;
  #line 118 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  return _M0MPB13StringBuilder10to__string(_M0L6_2atmpS496);
}

int32_t _M0MPC14byte4Byte7to__hexN14to__hex__digitS3630(int32_t _M0L1iS74) {
  #line 110 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
  if (_M0L1iS74 < 10) {
    int32_t _M0L6_2atmpS493;
    #line 112 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6_2atmpS493 = _M0IPC14byte4BytePB3Add3add(_M0L1iS74, 48);
    #line 112 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    return _M0MPC14byte4Byte8to__char(_M0L6_2atmpS493);
  } else {
    int32_t _M0L6_2atmpS495;
    int32_t _M0L6_2atmpS494;
    #line 114 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6_2atmpS495 = _M0IPC14byte4BytePB3Add3add(_M0L1iS74, 97);
    #line 114 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    _M0L6_2atmpS494 = _M0IPC14byte4BytePB3Sub3sub(_M0L6_2atmpS495, 10);
    #line 114 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\show.mbt"
    return _M0MPC14byte4Byte8to__char(_M0L6_2atmpS494);
  }
}

int32_t _M0IPC14byte4BytePB3Sub3sub(
  int32_t _M0L4selfS72,
  int32_t _M0L4thatS73
) {
  int32_t _M0L6_2atmpS491;
  int32_t _M0L6_2atmpS492;
  int32_t _M0L6_2atmpS490;
  #line 120 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\byte.mbt"
  _M0L6_2atmpS491 = (int32_t)_M0L4selfS72;
  _M0L6_2atmpS492 = (int32_t)_M0L4thatS73;
  _M0L6_2atmpS490 = _M0L6_2atmpS491 - _M0L6_2atmpS492;
  return _M0L6_2atmpS490 & 0xff;
}

int32_t _M0IPC14byte4BytePB3Mod3mod(
  int32_t _M0L4selfS70,
  int32_t _M0L4thatS71
) {
  int32_t _M0L6_2atmpS488;
  int32_t _M0L6_2atmpS489;
  int32_t _M0L6_2atmpS487;
  #line 67 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\byte.mbt"
  _M0L6_2atmpS488 = (int32_t)_M0L4selfS70;
  _M0L6_2atmpS489 = (int32_t)_M0L4thatS71;
  _M0L6_2atmpS487 = _M0L6_2atmpS488 % _M0L6_2atmpS489;
  return _M0L6_2atmpS487 & 0xff;
}

int32_t _M0IPC14byte4BytePB3Div3div(
  int32_t _M0L4selfS68,
  int32_t _M0L4thatS69
) {
  int32_t _M0L6_2atmpS485;
  int32_t _M0L6_2atmpS486;
  int32_t _M0L6_2atmpS484;
  #line 62 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\byte.mbt"
  _M0L6_2atmpS485 = (int32_t)_M0L4selfS68;
  _M0L6_2atmpS486 = (int32_t)_M0L4thatS69;
  _M0L6_2atmpS484 = _M0L6_2atmpS485 / _M0L6_2atmpS486;
  return _M0L6_2atmpS484 & 0xff;
}

int32_t _M0IPC14byte4BytePB3Add3add(
  int32_t _M0L4selfS66,
  int32_t _M0L4thatS67
) {
  int32_t _M0L6_2atmpS482;
  int32_t _M0L6_2atmpS483;
  int32_t _M0L6_2atmpS481;
  #line 106 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\byte.mbt"
  _M0L6_2atmpS482 = (int32_t)_M0L4selfS66;
  _M0L6_2atmpS483 = (int32_t)_M0L4thatS67;
  _M0L6_2atmpS481 = _M0L6_2atmpS482 + _M0L6_2atmpS483;
  return _M0L6_2atmpS481 & 0xff;
}

int32_t _M0MPC16uint166UInt1616unsafe__to__char(int32_t _M0L4selfS65) {
  int32_t _M0L6_2atmpS480;
  #line 68 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uint16_char.mbt"
  _M0L6_2atmpS480 = (int32_t)_M0L4selfS65;
  return _M0L6_2atmpS480;
}

int32_t _M0MPC16uint166UInt1623is__trailing__surrogate(int32_t _M0L4selfS64) {
  #line 45 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uint16_char.mbt"
  if (_M0L4selfS64 >= 56320) {
    return _M0L4selfS64 <= 57343;
  } else {
    return 0;
  }
}

int32_t _M0IPB13StringBuilderPB6Logger11write__char(
  struct _M0TPB13StringBuilder* _M0L4selfS62,
  int32_t _M0L2chS61
) {
  uint32_t _M0L4codeS60;
  #line 90 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  #line 91 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L4codeS60 = _M0MPC14char4Char8to__uint(_M0L2chS61);
  if (_M0L4codeS60 <= 65535u) {
    int32_t _M0L3lenS459 = _M0L4selfS62->$1;
    int32_t _M0L6_2atmpS458 = _M0L3lenS459 + 1;
    uint16_t* _M0L4dataS460;
    int32_t _M0L3lenS461;
    int32_t _M0L6_2atmpS462;
    int32_t _M0L3lenS464;
    int32_t _M0L6_2atmpS463;
    moonbit_incref(_M0L4selfS62);
    #line 93 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0MPB13StringBuilder19grow__if__necessary(_M0L4selfS62, _M0L6_2atmpS458);
    _M0L4dataS460 = _M0L4selfS62->$0;
    _M0L3lenS461 = _M0L4selfS62->$1;
    moonbit_incref(_M0L4dataS460);
    #line 94 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0L6_2atmpS462 = _M0MPC14uint4UInt10to__uint16(_M0L4codeS60);
    if (
      _M0L3lenS461 < 0 || _M0L3lenS461 >= Moonbit_array_length(_M0L4dataS460)
    ) {
      #line 94 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
      moonbit_panic();
    }
    _M0L4dataS460[_M0L3lenS461] = _M0L6_2atmpS462;
    moonbit_decref(_M0L4dataS460);
    _M0L3lenS464 = _M0L4selfS62->$1;
    _M0L6_2atmpS463 = _M0L3lenS464 + 1;
    _M0L4selfS62->$1 = _M0L6_2atmpS463;
    moonbit_decref(_M0L4selfS62);
  } else if (_M0L4codeS60 <= 1114111u) {
    int32_t _M0L3lenS466 = _M0L4selfS62->$1;
    int32_t _M0L6_2atmpS465 = _M0L3lenS466 + 2;
    uint32_t _M0L4codeS63;
    uint16_t* _M0L4dataS467;
    int32_t _M0L3lenS468;
    uint32_t _M0L6_2atmpS471;
    uint32_t _M0L6_2atmpS470;
    int32_t _M0L6_2atmpS469;
    uint16_t* _M0L4dataS472;
    int32_t _M0L3lenS477;
    int32_t _M0L6_2atmpS473;
    uint32_t _M0L6_2atmpS476;
    uint32_t _M0L6_2atmpS475;
    int32_t _M0L6_2atmpS474;
    int32_t _M0L3lenS479;
    int32_t _M0L6_2atmpS478;
    moonbit_incref(_M0L4selfS62);
    #line 97 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0MPB13StringBuilder19grow__if__necessary(_M0L4selfS62, _M0L6_2atmpS465);
    _M0L4codeS63 = _M0L4codeS60 - 65536u;
    _M0L4dataS467 = _M0L4selfS62->$0;
    _M0L3lenS468 = _M0L4selfS62->$1;
    _M0L6_2atmpS471 = _M0L4codeS63 >> 10;
    _M0L6_2atmpS470 = 55296u + _M0L6_2atmpS471;
    moonbit_incref(_M0L4dataS467);
    #line 99 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0L6_2atmpS469 = _M0MPC14uint4UInt10to__uint16(_M0L6_2atmpS470);
    if (
      _M0L3lenS468 < 0 || _M0L3lenS468 >= Moonbit_array_length(_M0L4dataS467)
    ) {
      #line 99 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
      moonbit_panic();
    }
    _M0L4dataS467[_M0L3lenS468] = _M0L6_2atmpS469;
    moonbit_decref(_M0L4dataS467);
    _M0L4dataS472 = _M0L4selfS62->$0;
    _M0L3lenS477 = _M0L4selfS62->$1;
    _M0L6_2atmpS473 = _M0L3lenS477 + 1;
    _M0L6_2atmpS476 = _M0L4codeS63 & 1023u;
    _M0L6_2atmpS475 = 56320u + _M0L6_2atmpS476;
    moonbit_incref(_M0L4dataS472);
    #line 100 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0L6_2atmpS474 = _M0MPC14uint4UInt10to__uint16(_M0L6_2atmpS475);
    if (
      _M0L6_2atmpS473 < 0
      || _M0L6_2atmpS473 >= Moonbit_array_length(_M0L4dataS472)
    ) {
      #line 100 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
      moonbit_panic();
    }
    _M0L4dataS472[_M0L6_2atmpS473] = _M0L6_2atmpS474;
    moonbit_decref(_M0L4dataS472);
    _M0L3lenS479 = _M0L4selfS62->$1;
    _M0L6_2atmpS478 = _M0L3lenS479 + 2;
    _M0L4selfS62->$1 = _M0L6_2atmpS478;
    moonbit_decref(_M0L4selfS62);
  } else {
    moonbit_decref(_M0L4selfS62);
    #line 103 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0FPC15abort5abortGuE((moonbit_string_t)moonbit_string_literal_32.data);
  }
  return 0;
}

int32_t _M0MPB13StringBuilder19grow__if__necessary(
  struct _M0TPB13StringBuilder* _M0L4selfS54,
  int32_t _M0L8requiredS55
) {
  uint16_t* _M0L4dataS457;
  int32_t _M0L12current__lenS53;
  int32_t _M0L13enough__spaceS56;
  int32_t _M0L13enough__spaceS57;
  int32_t _M0L6_2atmpS455;
  uint16_t* _M0L9new__dataS59;
  uint16_t* _M0L4dataS453;
  int32_t _M0L3lenS454;
  uint16_t* _M0L6_2aoldS881;
  #line 45 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L4dataS457 = _M0L4selfS54->$0;
  _M0L12current__lenS53 = Moonbit_array_length(_M0L4dataS457);
  if (_M0L8requiredS55 <= _M0L12current__lenS53) {
    moonbit_decref(_M0L4selfS54);
    return 0;
  }
  _M0L13enough__spaceS57 = _M0L12current__lenS53;
  while (1) {
    if (_M0L13enough__spaceS57 < _M0L8requiredS55) {
      int32_t _M0L6_2atmpS456 = _M0L13enough__spaceS57 * 2;
      _M0L13enough__spaceS57 = _M0L6_2atmpS456;
      continue;
    } else {
      _M0L13enough__spaceS56 = _M0L13enough__spaceS57;
    }
    break;
  }
  #line 60 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L6_2atmpS455 = _M0IPC16uint166UInt16PB7Default7default();
  _M0L9new__dataS59
  = (uint16_t*)moonbit_make_string(_M0L13enough__spaceS56, _M0L6_2atmpS455);
  _M0L4dataS453 = _M0L4selfS54->$0;
  _M0L3lenS454 = _M0L4selfS54->$1;
  moonbit_incref(_M0L4dataS453);
  moonbit_incref(_M0L9new__dataS59);
  #line 61 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0MPC15array10FixedArray12unsafe__blitGkE(_M0L9new__dataS59, 0, _M0L4dataS453, 0, _M0L3lenS454);
  _M0L6_2aoldS881 = _M0L4selfS54->$0;
  moonbit_decref(_M0L6_2aoldS881);
  _M0L4selfS54->$0 = _M0L9new__dataS59;
  moonbit_decref(_M0L4selfS54);
  return 0;
}

int32_t _M0MPC14uint4UInt10to__uint16(uint32_t _M0L4selfS52) {
  int32_t _M0L6_2atmpS452;
  #line 2675 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\intrinsics.mbt"
  _M0L6_2atmpS452 = *(int32_t*)&_M0L4selfS52;
  return (uint16_t)_M0L6_2atmpS452;
}

uint32_t _M0MPC14char4Char8to__uint(int32_t _M0L4selfS51) {
  int32_t _M0L6_2atmpS451;
  #line 1254 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\intrinsics.mbt"
  _M0L6_2atmpS451 = _M0L4selfS51;
  return *(uint32_t*)&_M0L6_2atmpS451;
}

moonbit_string_t _M0MPB13StringBuilder10to__string(
  struct _M0TPB13StringBuilder* _M0L4selfS49
) {
  int32_t _M0L3lenS443;
  uint16_t* _M0L4dataS445;
  int32_t _M0L6_2atmpS444;
  #line 143 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  _M0L3lenS443 = _M0L4selfS49->$1;
  _M0L4dataS445 = _M0L4selfS49->$0;
  _M0L6_2atmpS444 = Moonbit_array_length(_M0L4dataS445);
  if (_M0L3lenS443 == _M0L6_2atmpS444) {
    uint16_t* _M0L8_2afieldS884 = _M0L4selfS49->$0;
    int32_t _M0L6_2acntS917 = Moonbit_object_header(_M0L4selfS49)->rc;
    uint16_t* _M0L4dataS446;
    if (_M0L6_2acntS917 > 1) {
      int32_t _M0L11_2anew__cntS918 = _M0L6_2acntS917 - 1;
      Moonbit_object_header(_M0L4selfS49)->rc = _M0L11_2anew__cntS918;
      moonbit_incref(_M0L8_2afieldS884);
    } else if (_M0L6_2acntS917 == 1) {
      #line 145 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
      moonbit_free(_M0L4selfS49);
    }
    _M0L4dataS446 = _M0L8_2afieldS884;
    return _M0L4dataS446;
  } else {
    int32_t _M0L3lenS449 = _M0L4selfS49->$1;
    int32_t _M0L6_2atmpS450;
    uint16_t* _M0L4dataS50;
    uint16_t* _M0L4dataS447;
    int32_t _M0L3lenS448;
    int32_t _M0L6_2acntS919;
    #line 147 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0L6_2atmpS450 = _M0IPC16uint166UInt16PB7Default7default();
    _M0L4dataS50
    = (uint16_t*)moonbit_make_string(_M0L3lenS449, _M0L6_2atmpS450);
    _M0L4dataS447 = _M0L4selfS49->$0;
    _M0L3lenS448 = _M0L4selfS49->$1;
    _M0L6_2acntS919 = Moonbit_object_header(_M0L4selfS49)->rc;
    if (_M0L6_2acntS919 > 1) {
      int32_t _M0L11_2anew__cntS920 = _M0L6_2acntS919 - 1;
      Moonbit_object_header(_M0L4selfS49)->rc = _M0L11_2anew__cntS920;
      moonbit_incref(_M0L4dataS447);
    } else if (_M0L6_2acntS919 == 1) {
      #line 148 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
      moonbit_free(_M0L4selfS49);
    }
    moonbit_incref(_M0L4dataS50);
    #line 148 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
    _M0MPC15array10FixedArray12unsafe__blitGkE(_M0L4dataS50, 0, _M0L4dataS447, 0, _M0L3lenS448);
    return _M0L4dataS50;
  }
}

int32_t _M0IPC16uint166UInt16PB7Default7default() {
  #line 153 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uint16_char.mbt"
  return 0;
}

struct _M0TPB13StringBuilder* _M0MPB13StringBuilder11new_2einner(
  int32_t _M0L10size__hintS47
) {
  int32_t _M0L7initialS46;
  uint16_t* _M0L4dataS48;
  struct _M0TPB13StringBuilder* _block_978;
  #line 32 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\stringbuilder_buffer.mbt"
  if (_M0L10size__hintS47 < 1) {
    _M0L7initialS46 = 1;
  } else {
    int32_t _M0L6_2atmpS442 = _M0L10size__hintS47 + 1;
    _M0L7initialS46 = _M0L6_2atmpS442 / 2;
  }
  _M0L4dataS48 = (uint16_t*)moonbit_make_string(_M0L7initialS46, 0);
  _block_978
  = (struct _M0TPB13StringBuilder*)moonbit_malloc(sizeof(struct _M0TPB13StringBuilder));
  Moonbit_object_header(_block_978)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB13StringBuilder, $0) >> 2, 1, 0);
  _block_978->$0 = _M0L4dataS48;
  _block_978->$1 = 0;
  return _block_978;
}

int32_t _M0MPC14byte4Byte8to__char(int32_t _M0L4selfS45) {
  int32_t _M0L6_2atmpS441;
  #line 1867 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\intrinsics.mbt"
  _M0L6_2atmpS441 = (int32_t)_M0L4selfS45;
  return _M0L6_2atmpS441;
}

int32_t _M0MPB18UninitializedArray12unsafe__blitGsE(
  moonbit_string_t* _M0L3dstS35,
  int32_t _M0L11dst__offsetS36,
  moonbit_string_t* _M0L3srcS37,
  int32_t _M0L11src__offsetS38,
  int32_t _M0L3lenS39
) {
  #line 104 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uninitialized_array.mbt"
  #line 113 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uninitialized_array.mbt"
  _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGsEE(_M0L3dstS35, _M0L11dst__offsetS36, _M0L3srcS37, _M0L11src__offsetS38, _M0L3lenS39);
  return 0;
}

int32_t _M0MPB18UninitializedArray12unsafe__blitGUsiEE(
  struct _M0TUsiE** _M0L3dstS40,
  int32_t _M0L11dst__offsetS41,
  struct _M0TUsiE** _M0L3srcS42,
  int32_t _M0L11src__offsetS43,
  int32_t _M0L3lenS44
) {
  #line 104 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uninitialized_array.mbt"
  #line 113 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\uninitialized_array.mbt"
  _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGUsiEEE(_M0L3dstS40, _M0L11dst__offsetS41, _M0L3srcS42, _M0L11src__offsetS43, _M0L3lenS44);
  return 0;
}

int32_t _M0MPC15array10FixedArray12unsafe__blitGkE(
  uint16_t* _M0L3dstS8,
  int32_t _M0L11dst__offsetS10,
  uint16_t* _M0L3srcS9,
  int32_t _M0L11src__offsetS11,
  int32_t _M0L3lenS13
) {
  int32_t _if__result_979;
  #line 38 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
  if (_M0L3dstS8 == _M0L3srcS9) {
    _if__result_979 = _M0L11dst__offsetS10 < _M0L11src__offsetS11;
  } else {
    _if__result_979 = 0;
  }
  if (_if__result_979) {
    int32_t _M0L1iS12 = 0;
    while (1) {
      if (_M0L1iS12 < _M0L3lenS13) {
        int32_t _M0L6_2atmpS414 = _M0L11dst__offsetS10 + _M0L1iS12;
        int32_t _M0L6_2atmpS416 = _M0L11src__offsetS11 + _M0L1iS12;
        int32_t _M0L6_2atmpS415;
        int32_t _M0L6_2atmpS417;
        if (
          _M0L6_2atmpS416 < 0
          || _M0L6_2atmpS416 >= Moonbit_array_length(_M0L3srcS9)
        ) {
          #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2atmpS415 = (int32_t)_M0L3srcS9[_M0L6_2atmpS416];
        if (
          _M0L6_2atmpS414 < 0
          || _M0L6_2atmpS414 >= Moonbit_array_length(_M0L3dstS8)
        ) {
          #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L3dstS8[_M0L6_2atmpS414] = _M0L6_2atmpS415;
        _M0L6_2atmpS417 = _M0L1iS12 + 1;
        _M0L1iS12 = _M0L6_2atmpS417;
        continue;
      } else {
        moonbit_decref(_M0L3srcS9);
        moonbit_decref(_M0L3dstS8);
      }
      break;
    }
  } else {
    int32_t _M0L6_2atmpS422 = _M0L3lenS13 - 1;
    int32_t _M0L1iS15 = _M0L6_2atmpS422;
    while (1) {
      if (_M0L1iS15 >= 0) {
        int32_t _M0L6_2atmpS418 = _M0L11dst__offsetS10 + _M0L1iS15;
        int32_t _M0L6_2atmpS420 = _M0L11src__offsetS11 + _M0L1iS15;
        int32_t _M0L6_2atmpS419;
        int32_t _M0L6_2atmpS421;
        if (
          _M0L6_2atmpS420 < 0
          || _M0L6_2atmpS420 >= Moonbit_array_length(_M0L3srcS9)
        ) {
          #line 53 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2atmpS419 = (int32_t)_M0L3srcS9[_M0L6_2atmpS420];
        if (
          _M0L6_2atmpS418 < 0
          || _M0L6_2atmpS418 >= Moonbit_array_length(_M0L3dstS8)
        ) {
          #line 53 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L3dstS8[_M0L6_2atmpS418] = _M0L6_2atmpS419;
        _M0L6_2atmpS421 = _M0L1iS15 - 1;
        _M0L1iS15 = _M0L6_2atmpS421;
        continue;
      } else {
        moonbit_decref(_M0L3srcS9);
        moonbit_decref(_M0L3dstS8);
      }
      break;
    }
  }
  return 0;
}

int32_t _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGsEE(
  moonbit_string_t* _M0L3dstS17,
  int32_t _M0L11dst__offsetS19,
  moonbit_string_t* _M0L3srcS18,
  int32_t _M0L11src__offsetS20,
  int32_t _M0L3lenS22
) {
  int32_t _if__result_982;
  #line 38 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
  if (_M0L3dstS17 == _M0L3srcS18) {
    _if__result_982 = _M0L11dst__offsetS19 < _M0L11src__offsetS20;
  } else {
    _if__result_982 = 0;
  }
  if (_if__result_982) {
    int32_t _M0L1iS21 = 0;
    while (1) {
      if (_M0L1iS21 < _M0L3lenS22) {
        int32_t _M0L6_2atmpS423 = _M0L11dst__offsetS19 + _M0L1iS21;
        int32_t _M0L6_2atmpS425 = _M0L11src__offsetS20 + _M0L1iS21;
        moonbit_string_t _M0L6_2atmpS424;
        moonbit_string_t _M0L6_2aoldS887;
        int32_t _M0L6_2atmpS426;
        if (
          _M0L6_2atmpS425 < 0
          || _M0L6_2atmpS425 >= Moonbit_array_length(_M0L3srcS18)
        ) {
          #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2atmpS424 = (moonbit_string_t)_M0L3srcS18[_M0L6_2atmpS425];
        if (
          _M0L6_2atmpS423 < 0
          || _M0L6_2atmpS423 >= Moonbit_array_length(_M0L3dstS17)
        ) {
          #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2aoldS887 = (moonbit_string_t)_M0L3dstS17[_M0L6_2atmpS423];
        moonbit_incref(_M0L6_2atmpS424);
        moonbit_decref(_M0L6_2aoldS887);
        _M0L3dstS17[_M0L6_2atmpS423] = _M0L6_2atmpS424;
        _M0L6_2atmpS426 = _M0L1iS21 + 1;
        _M0L1iS21 = _M0L6_2atmpS426;
        continue;
      } else {
        moonbit_decref(_M0L3srcS18);
        moonbit_decref(_M0L3dstS17);
      }
      break;
    }
  } else {
    int32_t _M0L6_2atmpS431 = _M0L3lenS22 - 1;
    int32_t _M0L1iS24 = _M0L6_2atmpS431;
    while (1) {
      if (_M0L1iS24 >= 0) {
        int32_t _M0L6_2atmpS427 = _M0L11dst__offsetS19 + _M0L1iS24;
        int32_t _M0L6_2atmpS429 = _M0L11src__offsetS20 + _M0L1iS24;
        moonbit_string_t _M0L6_2atmpS428;
        moonbit_string_t _M0L6_2aoldS889;
        int32_t _M0L6_2atmpS430;
        if (
          _M0L6_2atmpS429 < 0
          || _M0L6_2atmpS429 >= Moonbit_array_length(_M0L3srcS18)
        ) {
          #line 53 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2atmpS428 = (moonbit_string_t)_M0L3srcS18[_M0L6_2atmpS429];
        if (
          _M0L6_2atmpS427 < 0
          || _M0L6_2atmpS427 >= Moonbit_array_length(_M0L3dstS17)
        ) {
          #line 53 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2aoldS889 = (moonbit_string_t)_M0L3dstS17[_M0L6_2atmpS427];
        moonbit_incref(_M0L6_2atmpS428);
        moonbit_decref(_M0L6_2aoldS889);
        _M0L3dstS17[_M0L6_2atmpS427] = _M0L6_2atmpS428;
        _M0L6_2atmpS430 = _M0L1iS24 - 1;
        _M0L1iS24 = _M0L6_2atmpS430;
        continue;
      } else {
        moonbit_decref(_M0L3srcS18);
        moonbit_decref(_M0L3dstS17);
      }
      break;
    }
  }
  return 0;
}

int32_t _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGUsiEEE(
  struct _M0TUsiE** _M0L3dstS26,
  int32_t _M0L11dst__offsetS28,
  struct _M0TUsiE** _M0L3srcS27,
  int32_t _M0L11src__offsetS29,
  int32_t _M0L3lenS31
) {
  int32_t _if__result_985;
  #line 38 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
  if (_M0L3dstS26 == _M0L3srcS27) {
    _if__result_985 = _M0L11dst__offsetS28 < _M0L11src__offsetS29;
  } else {
    _if__result_985 = 0;
  }
  if (_if__result_985) {
    int32_t _M0L1iS30 = 0;
    while (1) {
      if (_M0L1iS30 < _M0L3lenS31) {
        int32_t _M0L6_2atmpS432 = _M0L11dst__offsetS28 + _M0L1iS30;
        int32_t _M0L6_2atmpS434 = _M0L11src__offsetS29 + _M0L1iS30;
        struct _M0TUsiE* _M0L6_2atmpS433;
        struct _M0TUsiE* _M0L6_2aoldS891;
        int32_t _M0L6_2atmpS435;
        if (
          _M0L6_2atmpS434 < 0
          || _M0L6_2atmpS434 >= Moonbit_array_length(_M0L3srcS27)
        ) {
          #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2atmpS433 = (struct _M0TUsiE*)_M0L3srcS27[_M0L6_2atmpS434];
        if (
          _M0L6_2atmpS432 < 0
          || _M0L6_2atmpS432 >= Moonbit_array_length(_M0L3dstS26)
        ) {
          #line 49 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2aoldS891 = (struct _M0TUsiE*)_M0L3dstS26[_M0L6_2atmpS432];
        if (_M0L6_2atmpS433) {
          moonbit_incref(_M0L6_2atmpS433);
        }
        if (_M0L6_2aoldS891) {
          moonbit_decref(_M0L6_2aoldS891);
        }
        _M0L3dstS26[_M0L6_2atmpS432] = _M0L6_2atmpS433;
        _M0L6_2atmpS435 = _M0L1iS30 + 1;
        _M0L1iS30 = _M0L6_2atmpS435;
        continue;
      } else {
        moonbit_decref(_M0L3srcS27);
        moonbit_decref(_M0L3dstS26);
      }
      break;
    }
  } else {
    int32_t _M0L6_2atmpS440 = _M0L3lenS31 - 1;
    int32_t _M0L1iS33 = _M0L6_2atmpS440;
    while (1) {
      if (_M0L1iS33 >= 0) {
        int32_t _M0L6_2atmpS436 = _M0L11dst__offsetS28 + _M0L1iS33;
        int32_t _M0L6_2atmpS438 = _M0L11src__offsetS29 + _M0L1iS33;
        struct _M0TUsiE* _M0L6_2atmpS437;
        struct _M0TUsiE* _M0L6_2aoldS893;
        int32_t _M0L6_2atmpS439;
        if (
          _M0L6_2atmpS438 < 0
          || _M0L6_2atmpS438 >= Moonbit_array_length(_M0L3srcS27)
        ) {
          #line 53 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2atmpS437 = (struct _M0TUsiE*)_M0L3srcS27[_M0L6_2atmpS438];
        if (
          _M0L6_2atmpS436 < 0
          || _M0L6_2atmpS436 >= Moonbit_array_length(_M0L3dstS26)
        ) {
          #line 53 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2aoldS893 = (struct _M0TUsiE*)_M0L3dstS26[_M0L6_2atmpS436];
        if (_M0L6_2atmpS437) {
          moonbit_incref(_M0L6_2atmpS437);
        }
        if (_M0L6_2aoldS893) {
          moonbit_decref(_M0L6_2aoldS893);
        }
        _M0L3dstS26[_M0L6_2atmpS436] = _M0L6_2atmpS437;
        _M0L6_2atmpS439 = _M0L1iS33 - 1;
        _M0L1iS33 = _M0L6_2atmpS439;
        continue;
      } else {
        moonbit_decref(_M0L3srcS27);
        moonbit_decref(_M0L3dstS26);
      }
      break;
    }
  }
  return 0;
}

int32_t _M0IPB7FailurePB4Show6output(
  void* _M0L10_2ax__5120S4,
  struct _M0TPB6Logger _M0L10_2ax__5121S7
) {
  struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure* _M0L10_2aFailureS5;
  moonbit_string_t _M0L8_2afieldS895;
  int32_t _M0L6_2acntS921;
  moonbit_string_t _M0L15_2a_2aarg__5122S6;
  #line 37 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
  _M0L10_2aFailureS5
  = (struct _M0DTPC15error5Error48moonbitlang_2fcore_2fbuiltin_2eFailure_2eFailure*)_M0L10_2ax__5120S4;
  _M0L8_2afieldS895 = _M0L10_2aFailureS5->$0;
  _M0L6_2acntS921 = Moonbit_object_header(_M0L10_2aFailureS5)->rc;
  if (_M0L6_2acntS921 > 1) {
    int32_t _M0L11_2anew__cntS922 = _M0L6_2acntS921 - 1;
    Moonbit_object_header(_M0L10_2aFailureS5)->rc = _M0L11_2anew__cntS922;
    moonbit_incref(_M0L8_2afieldS895);
  } else if (_M0L6_2acntS921 == 1) {
    #line 37 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
    moonbit_free(_M0L10_2aFailureS5);
  }
  _M0L15_2a_2aarg__5122S6 = _M0L8_2afieldS895;
  if (_M0L10_2ax__5121S7.$1) {
    moonbit_incref(_M0L10_2ax__5121S7.$1);
  }
  #line 37 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
  _M0L10_2ax__5121S7.$0->$method_0(_M0L10_2ax__5121S7.$1, (moonbit_string_t)moonbit_string_literal_33.data);
  if (_M0L10_2ax__5121S7.$1) {
    moonbit_incref(_M0L10_2ax__5121S7.$1);
  }
  #line 37 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
  _M0MPB6Logger13write__objectGsE(_M0L10_2ax__5121S7, _M0L15_2a_2aarg__5122S6);
  #line 37 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\failure.mbt"
  _M0L10_2ax__5121S7.$0->$method_0(_M0L10_2ax__5121S7.$1, (moonbit_string_t)moonbit_string_literal_34.data);
  return 0;
}

int32_t _M0MPB6Logger13write__objectGsE(
  struct _M0TPB6Logger _M0L4selfS3,
  moonbit_string_t _M0L3objS2
) {
  #line 148 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  #line 149 "C:\\Users\\hnlyh\\.moon\\lib\\core\\builtin\\traits.mbt"
  _M0IPC16string6StringPB4Show6output(_M0L3objS2, _M0L4selfS3);
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

moonbit_string_t _M0FP15Error10to__string(void* _M0L4_2aeS391) {
  switch (Moonbit_object_tag(_M0L4_2aeS391)) {
    case 3: {
      moonbit_decref(_M0L4_2aeS391);
      return (moonbit_string_t)moonbit_string_literal_35.data;
      break;
    }
    
    case 1: {
      moonbit_decref(_M0L4_2aeS391);
      return (moonbit_string_t)moonbit_string_literal_36.data;
      break;
    }
    
    case 0: {
      return _M0IP016_24default__implPB4Show10to__stringGRPB7FailureE(_M0L4_2aeS391);
      break;
    }
    
    case 2: {
      moonbit_decref(_M0L4_2aeS391);
      return (moonbit_string_t)moonbit_string_literal_37.data;
      break;
    }
    default: {
      moonbit_decref(_M0L4_2aeS391);
      return (moonbit_string_t)moonbit_string_literal_38.data;
      break;
    }
  }
}

int32_t _M0IPB13StringBuilderPB6Logger67write__char_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void* _M0L11_2aobj__ptrS408,
  int32_t _M0L8_2aparamS407
) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS406 =
    (struct _M0TPB13StringBuilder*)_M0L11_2aobj__ptrS408;
  _M0IPB13StringBuilderPB6Logger11write__char(_M0L7_2aselfS406, _M0L8_2aparamS407);
  return 0;
}

int32_t _M0IPB13StringBuilderPB6Logger67write__view_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void* _M0L11_2aobj__ptrS405,
  struct _M0TPC16string10StringView _M0L8_2aparamS404
) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS403 =
    (struct _M0TPB13StringBuilder*)_M0L11_2aobj__ptrS405;
  _M0IPB13StringBuilderPB6Logger11write__view(_M0L7_2aselfS403, _M0L8_2aparamS404);
  return 0;
}

int32_t _M0IP016_24default__implPB6Logger72write__substring_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLoggerGRPB13StringBuilderE(
  void* _M0L11_2aobj__ptrS402,
  moonbit_string_t _M0L8_2aparamS399,
  int32_t _M0L8_2aparamS400,
  int32_t _M0L8_2aparamS401
) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS398 =
    (struct _M0TPB13StringBuilder*)_M0L11_2aobj__ptrS402;
  _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE(_M0L7_2aselfS398, _M0L8_2aparamS399, _M0L8_2aparamS400, _M0L8_2aparamS401);
  return 0;
}

int32_t _M0IPB13StringBuilderPB6Logger69write__string_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void* _M0L11_2aobj__ptrS397,
  moonbit_string_t _M0L8_2aparamS396
) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS395 =
    (struct _M0TPB13StringBuilder*)_M0L11_2aobj__ptrS397;
  _M0IPB13StringBuilderPB6Logger13write__string(_M0L7_2aselfS395, _M0L8_2aparamS396);
  return 0;
}

void moonbit_init() {
  
}

int main(int argc, char** argv) {
  struct _M0TWWuEuWRPC15error5ErrorEuEOuQRPC15error5Error** _M0L6_2atmpS413;
  struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE* _M0L12async__testsS385;
  struct _M0TPB5ArrayGUsiEE* _M0L7_2abindS386;
  int32_t _M0L7_2abindS387;
  int32_t _M0L2__S388;
  moonbit_runtime_init(argc, argv);
  moonbit_init();
  _M0L6_2atmpS413
  = (struct _M0TWWuEuWRPC15error5ErrorEuEOuQRPC15error5Error**)moonbit_empty_ref_array;
  _M0L12async__testsS385
  = (struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE));
  Moonbit_object_header(_M0L12async__testsS385)->meta
  = Moonbit_make_regular_object_header(offsetof(struct _M0TPB5ArrayGVWEuQRPC15error5ErrorE, $0) >> 2, 1, 0);
  _M0L12async__testsS385->$0 = _M0L6_2atmpS413;
  _M0L12async__testsS385->$1 = 0;
  #line 397 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0L7_2abindS386
  = _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test52moonbit__test__driver__internal__native__parse__args();
  _M0L7_2abindS387 = _M0L7_2abindS386->$1;
  _M0L2__S388 = 0;
  while (1) {
    if (_M0L2__S388 < _M0L7_2abindS387) {
      struct _M0TUsiE** _M0L3bufS412 = _M0L7_2abindS386->$0;
      struct _M0TUsiE* _M0L3argS389 =
        (struct _M0TUsiE*)_M0L3bufS412[_M0L2__S388];
      moonbit_string_t _M0L6_2atmpS409 = _M0L3argS389->$0;
      int32_t _M0L6_2atmpS410 = _M0L3argS389->$1;
      int32_t _M0L6_2atmpS411;
      moonbit_incref(_M0L6_2atmpS409);
      moonbit_incref(_M0L12async__testsS385);
      #line 398 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
      _M0FP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test44moonbit__test__driver__internal__do__execute(_M0L12async__testsS385, _M0L6_2atmpS409, _M0L6_2atmpS410);
      _M0L6_2atmpS411 = _M0L2__S388 + 1;
      _M0L2__S388 = _M0L6_2atmpS411;
      continue;
    } else {
      moonbit_decref(_M0L7_2abindS386);
    }
    break;
  }
  #line 400 "D:\\MoonBit\\MBOpenClacky\\cmd\\__generated_driver_for_blackbox_test.mbt"
  _M0IP016_24default__implP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test28MoonBit__Async__Test__Driver17run__async__testsGRP312hnlyxiaobing12MBOpenClacky19cmd__blackbox__test34MoonBit__Async__Test__Driver__ImplE(_M0L12async__testsS385);
  return 0;
}