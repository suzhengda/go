// Copyright 2015 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#include "go_asm.h"
#include "go_tls.h"
#include "funcdata.h"
#include "textflag.h"
#include "tls_arm64.h"

TEXT runtime·load_g(SB),NOSPLIT,$0 // -16
#ifndef GOOS_darwin
#ifndef GOOS_openbsd
#ifndef GOOS_windows
	MOVB	runtime·iscgo(SB), R0
	CBZ	R0, nocgo
#endif
#endif
#endif

// IE模式
// mrs x0, TPIDR_EL0
// add x0, x0, :tprel_hi12:v1
// add x0, x0, :tprel_lo12_nc:v1

//  MOVD R1, r1+8(FP) // 压栈，应该减法
//  MOVD R27, r27+0(FP) // 压栈，

	MRS_TPIDR_R0
  MOVD R0, R27
#ifdef TLS_darwin
	// Darwin sometimes returns unaligned pointers
	AND	$0xfffffffffffffff8, R0
#endif
//	MOVD	runtime·tls_g(SB), R27
//	MOVD	(R0)(R27), g

// tlsdesc模式，通过调用函数的形式获得线程变量地址
// TLSDESC Global-Dynamic relocation are in the form:
//   adrp    x0, :tlsdesc:v             [R_AARCH64_TLSDESC_ADR_PAGE21]
//   ldr     x1, [x0, #:tlsdesc_lo12:v]  [R_AARCH64_TLSDESC_LD64_LO12]
//   add     x0, x0, :tlsdesc_los:v     [R_AARCH64_TLSDESC_ADD_LO12]
//   .tlsdesccall                       [R_AARCH64_TLSDESC_CALL]
//   blr     x1

//
// adrp    x0, :tlsdesc:tlsvar1
// ldr     x1, [x0, :tlsdesc_lo12:tlsvar1]
// add     x0, x0, :tlsdesc_lo12:tlsvar1
// .tlsdesccall tlsvar1

//  ADRP runtime·tls_g(SB), R0  // $runtime.tls_g 取符号地址模式
  MOVD runtime·tls_g(SB), R1  // MOVD与adrp有关
//  MOVD	runtime·tls_g(SB), R0  // :tlsdesc_lo12:tlsvar1 为地址，组合再取地址内容
  // ADD   runtime·tls_g(SB), R0, R0
//  ADD runtime·tls_g(SB), R0 // $runtime.tls_g 取符号地址模式
  // .tlsdesccall
  CALL   (R1) // (R1)
  MOVD	(R27)(R0), g

 // MOVD r1+8(FP),R27 // 出栈，恢复寄存器状态。应该是加
 // MOVD r27+0(FP),R1 // 出栈，恢复寄存器状态

nocgo:
	RET

TEXT runtime·save_g(SB),NOSPLIT,$0 // -16
#ifndef GOOS_darwin
#ifndef GOOS_openbsd
#ifndef GOOS_windows
	MOVB	runtime·iscgo(SB), R0
	CBZ	R0, nocgo
#endif
#endif
#endif

//  MOVD R1, r1+8(FP) // 压栈，
//  MOVD R27, r27+0(FP) // 压栈，

  // IE模式
  MRS_TPIDR_R0
#ifdef TLS_darwin
	// Darwin sometimes returns unaligned pointers
	AND	$0xfffffffffffffff8, R0
#endif
  MOVD R0, R27
  // MOVD	runtime·tls_g2(SB), R27
  //	MOVD	g, (R0)(R27)

  // GD模式、类似于c调用 __tls_get_addr@plt
//  ADRP runtime·tls_g(SB), R2   // 实际为$runtime·tls_g(SB)
  MOVD runtime·tls_g(SB), R1  // MOVD与adrp有关
//  MOVD runtime·tls_g(SB), R2  // LDR R1, [R0, #:tlsdesc_lo12:v]； 但runtime·tls_g(SB)是寄存器
  // ADD runtime·tls_g(SB), R0  // 作为参数
  // MOVD R0, R1
  // AND   $0xFFF, R1  // #:tlsdesc_lo12:
  // ADD   $runtime·tls_g(SB), R0, R0
//  ADD runtime·tls_g(SB), R2  // 实际为$runtime·tls_g(SB)
  // .tlsdesccall
  CALL  (R1) //   // 此时X0应当是相对于TPIDR_R0的偏移
  MOVD	g, (R27)(R0)
//  MOVD r1+8(FP),R27 // 出栈，恢复寄存器状态
//  MOVD r27+0(FP),R1 // 出栈，恢复寄存器状态
nocgo:
	RET

#ifdef TLSG_IS_VARIABLE
#ifdef GOOS_android
// Use the free TLS_SLOT_APP slot #2 on Android Q.
// Earlier androids are set up in gcc_android.c.
DATA runtime·tls_g+0(SB)/8, $16
#endif
GLOBL runtime·tls_g+0(SB), NOPTR, $8
#else
GLOBL runtime·tls_g+0(SB), TLSBSS, $8  // NOTE: runtime·tls_g变量已转为，dlload时重定向的新地址，会自动根据ie或gd模式自行确定地址
GLOBL runtime·tls_g2+0(SB), TLSBSS, $8
#endif


/// (SB) Static Base 静态基址
// NOSPLIT 是一个标志，表示在执行该段代码时，不会进行栈分裂（stack split）。栈分裂通常是在调用其他函数时发生，以确保有足够的栈空间
// ,$0-16  栈指针起始-栈大小