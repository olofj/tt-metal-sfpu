/*
 * sfpi_compat.h — SFPI builtin compatibility layer for GCC ↔ LLVM
 *
 * tt-metal's SFPI headers use __builtin_rvtt_* (GCC-specific names).
 * This header provides the mapping to __builtin_riscv_tt_* (LLVM names)
 * when compiling with clang.
 *
 * Usage: Include this BEFORE sfpi.h in the include path.
 * The tt-metal build system should add -include sfpi_compat.h or
 * place this file so it's picked up by sfpi_builtins.h.
 *
 * This file handles the three main differences:
 * 1. Builtin name prefix: __builtin_rvtt_* → __builtin_riscv_tt_*
 * 2. instrn_buffer argument: GCC passes it explicitly, LLVM doesn't need it
 * 3. WH/BH dispatch: GCC uses __riscv_xtttensixwh/bh, LLVM uses __xttsfpu_wh/bh
 */

#ifndef SFPI_COMPAT_H
#define SFPI_COMPAT_H

#ifdef __clang__

/* ---- Architecture macro compatibility ---- */
/* GCC's -mcpu=tt-bh-tensix defines __riscv_xtttensixbh.
 * LLVM's -march=...xttsfpubh defines __riscv_xttsfpubh instead.
 * sfpi_constants.h gates BH-specific values (BOB32 format, NOINC mode)
 * on __riscv_xtttensixbh, so we must define it here. */
#if defined(__riscv_xttsfpubh) && !defined(__riscv_xtttensixbh)
#define __riscv_xtttensixbh 1000000
#endif
#if defined(__riscv_xttsfpu) && !defined(__riscv_xtttensixwh) && !defined(__riscv_xttsfpubh)
#define __riscv_xtttensixwh 1000000
#endif

/* ---- __xtt_vector type ---- */
/* __xtt_vector is a clang builtin type (RISCVVTypes.def) with implicit
 * conversion rules to/from unsigned int (SemaOverload.cpp). Distinct for
 * overload resolution, opaque to optimizer. Matches GCC's XTT32SImode.
 *
 * _XTT(expr): cast builtin return value (unsigned int) to __xtt_vector.
 * Needed because clang builtins return unsigned int, but sfpi.h expects
 * __xtt_vector for correct constructor resolution. */
#ifdef __cplusplus
#define _XTT(x) static_cast<__xtt_vector>(x)
#else
/* In C, __xtt_vector is the builtin type — assignment from uint is implicit */
#define _XTT(x) (x)
#endif

/* ---- Type fixups for clang on riscv32 ---- */
/* On riscv32, clang maps int32_t = int and uint32_t = unsigned int.
 * GCC maps them differently (int32_t = long), allowing sfpi_fp16.h to
 * define separate constructors for int and int32_t. We make int32_t = long
 * to match GCC's type mapping and avoid constructor redeclaration errors.
 * MUST come before any standard header includes that define int32_t. */
#define __INT32_TYPE__ long
#define __UINT32_TYPE__ unsigned long

/* ---- __has_builtin override ---- */
/* sfpi.h checks __has_builtin(__builtin_rvtt_synth_opcode) and errors if
 * false. Since we provide all GCC SFPI builtins via macro mappings below,
 * we override __has_builtin to always return true.
 *
 * However, GCC 15's libstdc++ headers also use __has_builtin to gate
 * compiler-specific type traits (e.g. __remove_reference) that clang may
 * not support. Pre-include standard headers that use __has_builtin so they
 * see the real builtin check (include guards prevent re-processing when
 * sfpi.h includes them again). */
#ifdef __cplusplus
#include <type_traits>
#include <cstdint>
#include <limits>
#endif
/* ---- Tensix instruction encoding: ROL2 swizzle ---- */
/* TT's GCC .ttinsn applies a rotate-left-by-2 (ROL2) to instruction words.
 * This moves bits[1:0] to bits[3:2], telling the Tensix decoder to route
 * the word to the coprocessor instead of the RISC-V core.
 *
 * We pre-define INSTRUCTION_WORD with ROL2 here (before ckernel_ops.h gets
 * included). Since sfpi_compat.h is -include'd first, this definition is
 * the first one. ckernel_ops.h will re-define it without ROL2, so we also
 * need to block that re-definition by defining _CKERNEL_INSTRUCTION_WORD_.
 * The .ttinsn asm macro is kept for backward compatibility. */
__asm__(".macro .ttinsn operand\n"
        ".word (((\\operand & 0x3FFFFFFF) << 2) | ((\\operand >> 30) & 3))\n"
        ".endm\n");

#pragma push_macro("__has_builtin")
#undef __has_builtin
#define __has_builtin(x) 1

/* ---- C++ only: ckernel stub and 6-arg inline function stubs ---- */
#ifdef __cplusplus
/* sfpi_builtins.h's self-referencing macros expand to forms containing
 * ckernel::instrn_buffer. If compiling with ckernel.h (TENSIX_FIRMWARE),
 * it provides the real definition. Otherwise, provide a stub. */
#if !defined(TENSIX_FIRMWARE)
namespace ckernel { static volatile unsigned int instrn_buffer[1] = {0}; }
#endif

/* sfpi_builtins.h lines 14-16 define macros like:
 *   __builtin_rvtt_sfpxicmps(v,i,mod1) → __builtin_rvtt_sfpxicmps(buf,v,i,0,0,mod1)
 * The self-reference prevention causes the 6-arg form to survive as a function
 * call. We provide inline functions matching the 6-arg signature. */
#endif /* __cplusplus */

/* ---- Known ckernel.h incompatibility ---- */
/* ckernel.h line 316 uses `volatile std::uint32_t short *tt_reg_ptr` which
 * is a GCC extension for 16-bit pointer width. Clang doesn't support this.
 * This function (get_cfg16_pointer) is NOT used by SFPU kernels — it's a
 * hardware config accessor. tt-metal should wrap it in #ifndef __clang__
 * to fix. For now, SFPU kernels compile fine without ckernel.h. */

/* ---- Architecture detection ---- */
/* GCC: __riscv_xtttensixwh, __riscv_xtttensixbh
 * LLVM: set via -D__SFPU_BH__ or -D__SFPU_WH__ */
#if defined(__xttsfpu_bh) || defined(__SFPU_BH__)
#define __riscv_xtttensixbh 1
#define __riscv_tt_blackhole 1
#elif defined(__xttsfpu_wh) || defined(__SFPU_WH__)
#define __riscv_xtttensixwh 1
#define __riscv_tt_wormhole 1
#endif

/* ---- Core instruction builtins ---- */
/* These map the GCC builtin names to LLVM intrinsic-backed builtins.
 * The key difference: GCC builtins take an instrn_buffer pointer as first arg;
 * LLVM intrinsics don't need it (the instruction is emitted directly). */

/* NOP */
#define __builtin_rvtt_sfpnop() __builtin_riscv_tt_sfpnop()

/* CC stack */
#define __builtin_rvtt_sfppushc(mod) __builtin_riscv_tt_sfppushc()
#define __builtin_rvtt_sfppopc(mod) __builtin_riscv_tt_sfppopc()
#define __builtin_rvtt_sfpcompc() __builtin_riscv_tt_sfpcompc()
#define __builtin_rvtt_sfpencc(imm, mod) __builtin_riscv_tt_sfpencc(imm, mod)

/* Condition codes */
#define __builtin_rvtt_sfpsetcc_i(imm, mod) __builtin_riscv_tt_sfpsetcc(0, imm, mod)
#define __builtin_rvtt_sfpsetcc_v(src, mod) __builtin_riscv_tt_sfpsetcc(src, 0, mod)

/* Register operations — _XTT() casts return to __xtt_vector for overload resolution */
#define __builtin_rvtt_sfpmov(src, mod) _XTT(__builtin_riscv_tt_sfpmov(src, 0, mod))
#define __builtin_rvtt_sfpmov_lv(live, src, mod) _XTT(__builtin_riscv_tt_sfpmov_lv(live, src, 0, mod))
#define __builtin_rvtt_sfpabs(src, mod) _XTT(__builtin_riscv_tt_sfpabs(src, 0, mod))
#define __builtin_rvtt_sfpabs_lv(live, src, mod) _XTT(__builtin_riscv_tt_sfpabs_lv(live, src, 0, mod))
#define __builtin_rvtt_sfpnot(src) _XTT(__builtin_riscv_tt_sfpnot(src, 0, 0))
#define __builtin_rvtt_sfpnot_lv(live, src) _XTT(__builtin_riscv_tt_sfpnot_lv(live, src, 0, 0))

/* Exponent/mantissa operations */
#define __builtin_rvtt_sfpexexp(src, mod) _XTT(__builtin_riscv_tt_sfpexexp(src, 0, mod))
#define __builtin_rvtt_sfpexexp_lv(live, src, mod) _XTT(__builtin_riscv_tt_sfpexexp_lv(live, src, 0, mod))
#define __builtin_rvtt_sfpexman(src, mod) _XTT(__builtin_riscv_tt_sfpexman(src, 0, mod))
#define __builtin_rvtt_sfpexman_lv(live, src, mod) _XTT(__builtin_riscv_tt_sfpexman_lv(live, src, 0, mod))
#define __builtin_rvtt_sfplz(src, mod) _XTT(__builtin_riscv_tt_sfplz(src, 0, mod))
#define __builtin_rvtt_sfplz_lv(live, src, mod) _XTT(__builtin_riscv_tt_sfplz_lv(live, src, 0, mod))

/* Logic operations */
#define __builtin_rvtt_sfpand(dst, src) _XTT(__builtin_riscv_tt_sfpand(src, 0, 0))
#define __builtin_rvtt_sfpor(dst, src) _XTT(__builtin_riscv_tt_sfpor(src, 0, 0))
#define __builtin_rvtt_sfpxor(dst, src) _XTT(__builtin_riscv_tt_sfpxor(src, 0, 0))

/* Shift vector (variable amount) */
#define __builtin_rvtt_sfpshft_v(dst, src, mod) _XTT(__builtin_riscv_tt_sfpshft(src, 0, mod))

/* Cast / rounding */
#define __builtin_rvtt_sfpcast(src, mod) _XTT(__builtin_riscv_tt_sfpcast(src, 0, mod))
#define __builtin_rvtt_sfpcast_lv(live, src, mod) _XTT(__builtin_riscv_tt_sfpcast_lv(live, src, 0, mod))

/* Config */
#define __builtin_rvtt_sfpconfig_v(src, mod) __builtin_riscv_tt_sfpconfig(0, src, mod)

/* ---- Architecture-dispatched builtins (BH) ---- */
#ifdef __riscv_xtttensixbh

/* Load/Store BH */
#define __builtin_rvtt_bh_sfpload(buf, mod0, mode, addr, x1, x2) \
    _XTT(__builtin_riscv_tt_sfpload(mod0, mode, addr))
#define __builtin_rvtt_bh_sfpload_lv(buf, live, mod0, mode, addr, x1, x2) \
    _XTT(__builtin_riscv_tt_sfpload_lv(live, mod0, mode, addr))
#define __builtin_rvtt_bh_sfpstore(buf, src, mod0, mode, addr, x1, x2) \
    __builtin_riscv_tt_sfpstore(src, mod0, mode, addr)
#define __builtin_rvtt_bh_sfpxloadi(buf, mod0, imm16, x1, x2) \
    _XTT(__builtin_riscv_tt_sfploadi(mod0, imm16))
#define __builtin_rvtt_bh_sfpxloadi_lv(buf, live, mod0, imm16, x1, x2) \
    _XTT(__builtin_riscv_tt_sfploadi(mod0, imm16))

/* 3-operand arithmetic BH */
#define __builtin_rvtt_bh_sfpmad(a, b, c, mod) _XTT(__builtin_riscv_tt_sfpmad(a, b, c, mod))
#define __builtin_rvtt_bh_sfpmad_lv(live, a, b, c, mod) _XTT(__builtin_riscv_tt_sfpmad_lv(live, a, b, c, mod))
#define __builtin_rvtt_bh_sfpmul(a, b, mod) _XTT(__builtin_riscv_tt_sfpmul(a, b, 9, mod))
#define __builtin_rvtt_bh_sfpmul_lv(live, a, b, mod) _XTT(__builtin_riscv_tt_sfpmul_lv(live, a, b, 9, mod))
#define __builtin_rvtt_bh_sfpadd(a, b, mod) _XTT(__builtin_riscv_tt_sfpadd(10, a, b, mod))
#define __builtin_rvtt_bh_sfpadd_lv(live, a, b, mod) _XTT(__builtin_riscv_tt_sfpadd_lv(live, 10, a, b, mod))

/* Immediate arithmetic BH */
#define __builtin_rvtt_bh_sfpmuli(buf, src, imm16, x1, x2, mod) \
    _XTT(__builtin_riscv_tt_sfpmuli(src, imm16, mod))
#define __builtin_rvtt_bh_sfpaddi(buf, src, imm16, x1, x2, mod) \
    _XTT(__builtin_riscv_tt_sfpaddi(src, imm16, mod))

/* Unary with immediate BH */
#define __builtin_rvtt_bh_sfpsetexp_i(buf, imm12, x1, x2, src) \
    _XTT(__builtin_riscv_tt_sfpsetexp(src, imm12, 0))
#define __builtin_rvtt_bh_sfpsetexp_v(dst, src) \
    _XTT(__builtin_riscv_tt_sfpsetexp(src, 0, 0))
#define __builtin_rvtt_bh_sfpsetman_i(buf, imm12, x1, x2, src, mod) \
    _XTT(__builtin_riscv_tt_sfpsetman(src, imm12, mod))
#define __builtin_rvtt_bh_sfpsetman_v(dst, src) \
    _XTT(__builtin_riscv_tt_sfpsetman(src, 0, 0))
#define __builtin_rvtt_bh_sfpsetsgn_i(buf, imm12, x1, x2, src) \
    _XTT(__builtin_riscv_tt_sfpsetsgn(src, imm12, 0))
#define __builtin_rvtt_bh_sfpsetsgn_v(dst, src) \
    _XTT(__builtin_riscv_tt_sfpsetsgn(src, 0, 0))
#define __builtin_rvtt_bh_sfpdivp2(buf, imm12, x1, x2, src, mod) \
    _XTT(__builtin_riscv_tt_sfpdivp2(src, imm12, mod))
#define __builtin_rvtt_bh_sfpdivp2_lv(buf, live, imm12, x1, x2, src, mod) \
    _XTT(__builtin_riscv_tt_sfpdivp2_lv(live, src, imm12, mod))

/* Integer operations BH */
#define __builtin_rvtt_bh_sfpxiadd_i(buf, src, imm12, x1, x2, mod) \
    _XTT(__builtin_riscv_tt_sfpiadd(src, imm12, mod))
#define __builtin_rvtt_bh_sfpxiadd_i_lv(buf, live, src, imm12, x1, x2, mod) \
    _XTT(__builtin_riscv_tt_sfpiadd(src, imm12, mod))
#define __builtin_rvtt_bh_sfpxiadd_v(dst, src, mod) \
    _XTT(__builtin_riscv_tt_sfpiadd(src, 0, mod))

/* Shift BH */
#define __builtin_rvtt_bh_sfpshft_i(buf, dst, imm12, x1, x2, mod) \
    _XTT(__builtin_riscv_tt_sfpshft(dst, imm12, mod))
#define __builtin_rvtt_bh_sfpshft_v(dst, src, mod) \
    _XTT(__builtin_riscv_tt_sfpshft(src, 0, mod))

/* Comparison BH — these set the CC and return a dummy condition result (0).
 * In GCC, sfpxfcmps/v/sfpxicmps return int (condition); in LLVM, sfpsetcc is void.
 * The return value is only used by sfpxbool for boolean CC operations. */
#define __builtin_rvtt_bh_sfpxfcmps(buf, v, f, x1, x2, mod) \
    (__builtin_riscv_tt_sfpsetcc(v, f, mod), 0)
#define __builtin_rvtt_bh_sfpxfcmpv(a, b, mod) \
    (__builtin_riscv_tt_sfpsetcc(a, 0, mod), 0)
#define __builtin_rvtt_bh_sfpxicmps(buf, v, i, x1, x2, mod) \
    (__builtin_riscv_tt_sfpsetcc(v, i, mod), 0)

/* BH-specific */
#define __builtin_rvtt_bh_sfpmov_config(src) _XTT(__builtin_riscv_tt_sfpmov(src, 0, 0))
#define __builtin_rvtt_bh_sfparecip(src, mod) _XTT(__builtin_riscv_tt_sfparecip(src, 0, mod))
#define __builtin_rvtt_bh_sfparecip_lv(live, src, mod) _XTT(__builtin_riscv_tt_sfparecip_lv(live, src, 0, mod))
#define __builtin_rvtt_bh_sfpgt(src, mod) __builtin_riscv_tt_sfpgt(src, 0, mod)
#define __builtin_rvtt_bh_sfple(src, mod) __builtin_riscv_tt_sfple(src, 0, mod)
#define __builtin_rvtt_bh_sfpmul24(a, b, mod) _XTT(__builtin_riscv_tt_sfpmul24(a, b, 9, mod))
#define __builtin_rvtt_bh_sfpmul24_lv(live, a, b, mod) _XTT(__builtin_riscv_tt_sfpmul24_lv(live, a, b, 9, mod))

/* LUT */
#define __builtin_rvtt_sfplut(dst, l0, l1, l2, mod) _XTT(__builtin_riscv_tt_sfplut(0, 0))
#define __builtin_rvtt_sfplutfp32_3r(dst, l0, l1, l2, mod) _XTT(__builtin_riscv_tt_sfplutfp32(dst, mod))
#define __builtin_rvtt_sfplutfp32_6r(dst, l0, l1, l2, l4, l5, l6, mod) _XTT(__builtin_riscv_tt_sfplutfp32(dst, mod))

/* Stochastic rounding — intrinsic takes 5 args:
 * (rnd_mode, imm5, lreg_src_b, lreg_src_c, mod1) */
#define __builtin_rvtt_bh_sfpstochrnd_i(buf, mode, x1, x2, x3, src, mod) \
    _XTT(__builtin_riscv_tt_sfpstochrnd(mode, 0, src, src, mod))
#define __builtin_rvtt_bh_sfpstochrnd_v(mode, src_b, src_c, mod) \
    _XTT(__builtin_riscv_tt_sfpstochrnd(mode, 0, src_b, src_c, mod))

/* Swap / transpose */
#define __builtin_rvtt_sfpswap(a, b, mod) _XTT(__builtin_riscv_tt_sfpswap(a, 0, mod))
#define __builtin_rvtt_sfptransp(a, b, c, d) _XTT(__builtin_riscv_tt_sfptransp(a, 0, 0))

/* SFPSHFT2 */
#define __builtin_rvtt_sfpshft2_e(dst, src, mod) _XTT(__builtin_riscv_tt_sfpshft2(src, 0, mod))

#endif /* __riscv_xtttensixbh */

/* ---- WH builtins (same pattern, different load/store encoding) ---- */
#ifdef __riscv_xtttensixwh

#define __builtin_rvtt_wh_sfpload(buf, mod0, mode, addr, x1, x2) \
    _XTT(__builtin_riscv_tt_sfpload(mod0, mode, addr))
#define __builtin_rvtt_wh_sfpload_lv(buf, live, mod0, mode, addr, x1, x2) \
    _XTT(__builtin_riscv_tt_sfpload_lv(live, mod0, mode, addr))
#define __builtin_rvtt_wh_sfpstore(buf, src, mod0, mode, addr, x1, x2) \
    __builtin_riscv_tt_sfpstore(src, mod0, mode, addr)
#define __builtin_rvtt_wh_sfpxloadi(buf, mod0, imm16, x1, x2) \
    _XTT(__builtin_riscv_tt_sfploadi(mod0, imm16))

#define __builtin_rvtt_wh_sfpmad(a, b, c, mod) _XTT(__builtin_riscv_tt_sfpmad(a, b, c, mod))
#define __builtin_rvtt_wh_sfpmul(a, b, mod) _XTT(__builtin_riscv_tt_sfpmul(a, b, 9, mod))
#define __builtin_rvtt_wh_sfpadd(a, b, mod) _XTT(__builtin_riscv_tt_sfpadd(10, a, b, mod))

#define __builtin_rvtt_wh_sfpsetexp_i(buf, imm12, x1, x2, src) \
    _XTT(__builtin_riscv_tt_sfpsetexp(src, imm12, 0))
#define __builtin_rvtt_wh_sfpsetexp_v(dst, src) \
    _XTT(__builtin_riscv_tt_sfpsetexp(src, 0, 0))
#define __builtin_rvtt_wh_sfpsetman_i(buf, imm12, x1, x2, src, mod) \
    _XTT(__builtin_riscv_tt_sfpsetman(src, imm12, mod))
#define __builtin_rvtt_wh_sfpsetman_v(dst, src) \
    _XTT(__builtin_riscv_tt_sfpsetman(src, 0, 0))
#define __builtin_rvtt_wh_sfpdivp2(buf, imm12, x1, x2, src, mod) \
    _XTT(__builtin_riscv_tt_sfpdivp2(src, imm12, mod))
#define __builtin_rvtt_wh_sfpxiadd_i(buf, src, imm12, x1, x2, mod) \
    _XTT(__builtin_riscv_tt_sfpiadd(src, imm12, mod))
#define __builtin_rvtt_wh_sfpxiadd_v(dst, src, mod) \
    _XTT(__builtin_riscv_tt_sfpiadd(src, 0, mod))
#define __builtin_rvtt_wh_sfpxfcmps(buf, v, f, x1, x2, mod) \
    (__builtin_riscv_tt_sfpsetcc(v, f, mod), 0)
#define __builtin_rvtt_wh_sfpxfcmpv(a, b, mod) \
    (__builtin_riscv_tt_sfpsetcc(a, 0, mod), 0)

#endif /* __riscv_xtttensixwh */

/* ---- SFPI control-flow builtins ---- */
/* These are NOT hardware instructions. GCC's SFPI implementation lowers
 * them in the GCC middle-end (gimple-rvtt.cc). For LLVM, we implement them
 * as inline sequences of the primitive CC-stack builtins. */

/* sfpassign_lv: conditional assignment (used in v_if/v_else regions)
 * Returns __xtt_vector to match GCC's return type for ternary expressions. */
#define __builtin_rvtt_sfpassign_lv(live, src) \
    ((__xtt_vector)__builtin_riscv_tt_sfpmov_lv(live, src, 0, 0))

/* sfpxvif: begin a v_if region. Returns a dependency token (int). */
#define __builtin_rvtt_sfpxvif() 0

/* sfpxcondb: conditional-branch from register and dependency token.
 * In GCC, this is an internal pseudo-builtin that the compiler lowers
 * together with sfpxvif to produce the correct SETCC+PUSHC sequence.
 * For LLVM, the condition code is ALREADY set by the preceding comparison
 * (sfpxfcmps/sfpxicmps → sfpsetcc). Emitting another sfpsetcc here with
 * mod=0 would OVERWRITE the correct CC, causing wrong predication.
 * So we make this a no-op — just return the dummy result. */
#define __builtin_rvtt_sfpxcondb(src, dep) ((void)(src), 0)

/* sfpxcondi: conditional-branch from immediate condition.
 * Takes 1 arg (condition value) and returns as __xtt_vector.
 * Cast through unsigned int since only uint↔xtt conversion is allowed. */
#define __builtin_rvtt_sfpxcondi(cond) _XTT((unsigned int)(cond))

/* sfpxbool: boolean operation on CC stack (AND/OR/NOT of conditions).
 * GCC lowers this to CC stack manipulation. For clang, return the combined result.
 * The 'op' arg selects AND(0)/OR(1)/NOT(2), a and b are the condition results. */
#define __builtin_rvtt_sfpxbool(op, a, b) \
    ((op) == 0 ? ((a) && (b)) : (op) == 1 ? ((a) || (b)) : !(a))

/* sfpxicmpv: integer compare vector — maps to sfpsetcc with int mode.
 * Returns 0 (dummy condition result) like sfpxfcmps/v. */
#define __builtin_rvtt_sfpxicmpv(a, b, mod) \
    (__builtin_riscv_tt_sfpsetcc(a, 0, mod), 0)

/* sfpreadlreg/sfpwritelreg: L-register read/write by constant index.
 * GCC has per-register variants (sfpreadlreg0-7). Our LLVM intrinsics
 * take a constant index and emit SFPMOV from/to the physical L-register. */
#define __builtin_rvtt_sfpreadlreg(idx) \
    _XTT(__builtin_riscv_tt_sfpreadlreg(idx))
#define __builtin_rvtt_sfpwritelreg(val, idx) \
    __builtin_riscv_tt_sfpwritelreg((unsigned int)(val), idx)

/* synth_opcode: emit a raw Tensix opcode. Not an SFPU instruction.
 * Used for rare non-SFPU operations within SFPU kernels.
 * MUST use .ttinsn for ROL2 encoding (same reason as ttincrwc). */
#define __builtin_rvtt_synth_opcode(opcode) \
    __asm__ volatile(".ttinsn %0" :: "i"(opcode) : "memory")

/* ttincrwc: increment write counter (Tensix scalar instruction, not SFPU).
 * The write counter manages Dst tile addressing.
 * Encoding: TT_OP(0x38, (rwc_cr << 18) | (rwc_d << 14) | (rwc_b << 10) | (rwc_a << 6))
 * Args map: cr→rwc_cr, incr→rwc_d, mask→rwc_b, val→rwc_a
 * MUST use .ttinsn (not .word) for ROL2 encoding — Tensix instructions in the
 * RISC-V code stream require the ROL2 swizzle so the hardware routes them to
 * the coprocessor instead of the RISC-V core. */
#define __builtin_rvtt_ttincrwc(cr, incr, mask, val) \
    __asm__ volatile(".ttinsn %0" :: "i"( \
        (0x38 << 24) | ((cr) << 18) | ((incr) << 14) | ((mask) << 10) | ((val) << 6)) \
        : "memory")

/* sfpselect2/sfpselect4: extract lane from multi-register result.
 * sfpselect2: used after SFPSWAP (2 outputs: dest + src_c)
 * sfpselect4: used after SFPTRANSP (4 outputs: all 4 input registers) */
#define __builtin_rvtt_sfpselect2(src, idx) \
    _XTT(__builtin_riscv_tt_sfpselect2((unsigned int)(src), idx))
#define __builtin_rvtt_sfpselect4(src, idx) \
    _XTT(__builtin_riscv_tt_sfpselect4((unsigned int)(src), idx))

/* sfpshft2_subvec_shfl1: SFPSHFT2 in shuffle mode.
 * Maps to sfpshft2 with the specified mod1. */
#define __builtin_rvtt_sfpshft2_subvec_shfl1(src, mod1) \
    __builtin_riscv_tt_sfpshft2(src, 0, mod1)

/* ttreplay: replay buffer control (Tensix opcode 0x04).
 * GCC has a 7-arg builtin; lltt.h wraps it with a 4→7-arg macro:
 *   #define __builtin_rvtt_ttreplay(S,L,E,R)
 *           __builtin_rvtt_ttreplay(buf,L,0,0,S,E,R)
 * We define the 7-arg and 4-arg forms as inline no-ops. The LLVM replay
 * pass handles replay optimization automatically at machine code level. */
#ifdef __cplusplus
template<typename T>
static inline __attribute__((always_inline)) void
__builtin_rvtt_ttreplay(volatile T *buf, unsigned len,
                         unsigned z1, unsigned z2, unsigned start,
                         unsigned exec_while_loading, unsigned load_mode) {
    (void)buf; (void)len; (void)z1; (void)z2; (void)start;
    (void)exec_while_loading; (void)load_mode;
    __asm__ volatile("" ::: "memory");
}
static inline __attribute__((always_inline)) void
__builtin_rvtt_ttreplay(unsigned start, unsigned len,
                         unsigned exec_while_loading, unsigned load_mode) {
    (void)start; (void)len; (void)exec_while_loading; (void)load_mode;
    __asm__ volatile("" ::: "memory");
}
#else
/* C: simple 4-arg macro (lltt.h is C++ only) */
#define __builtin_rvtt_ttreplay(start, len, ewl, lm) \
    __asm__ volatile("" ::: "memory")
#endif

/* WH-specific missing builtins */
#ifdef __riscv_xtttensixwh
#define __builtin_rvtt_wh_sfpcast(src, mod) _XTT(__builtin_riscv_tt_sfpcast(src, 0, mod))
#define __builtin_rvtt_wh_sfpsetsgn_i(buf, imm12, x1, x2, src) \
    _XTT(__builtin_riscv_tt_sfpsetsgn(src, imm12, 0))
#define __builtin_rvtt_wh_sfpsetsgn_v(dst, src) \
    _XTT(__builtin_riscv_tt_sfpsetsgn(src, 0, 0))
#define __builtin_rvtt_wh_sfpstochrnd_i(buf, mode, x1, x2, x3, src, mod) \
    _XTT(__builtin_riscv_tt_sfpstochrnd(mode, 0, src, 0, mod))
#define __builtin_rvtt_wh_sfpstochrnd_v(mode, src_b, src_c, mod) \
    _XTT(__builtin_riscv_tt_sfpstochrnd(mode, 0, src_b, src_c, mod))
#define __builtin_rvtt_wh_sfpshft_v(dst, src, mod) \
    _XTT(__builtin_riscv_tt_sfpshft(src, 0, mod))
#define __builtin_rvtt_wh_sfpconfig_v(src, mod) \
    __builtin_riscv_tt_sfpconfig(0, src, mod)
#endif /* __riscv_xtttensixwh */

/* BH-specific missing builtins */
#ifdef __riscv_xtttensixbh
#define __builtin_rvtt_bh_sfpcast(src, mod) _XTT(__builtin_riscv_tt_sfpcast(src, 0, mod))
#define __builtin_rvtt_bh_sfpconfig_v(src, mod) \
    __builtin_riscv_tt_sfpconfig(0, src, mod)
#define __builtin_rvtt_bh_sfpxicmpv(a, b, mod) \
    __builtin_riscv_tt_sfpsetcc(a, 0, mod)
#endif /* __riscv_xtttensixbh */

#endif /* __clang__ */
#endif /* SFPI_COMPAT_H */
