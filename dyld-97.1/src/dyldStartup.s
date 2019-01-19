/*
 * Copyright (c) 1999-2005 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/* C 运行时启动i386和ppc接口的动态链接器。这与 crt0.o 中的入口点相同，并添加了 mach 头的地址作为额外第一个参数传递。
 *
 * 内核设置堆栈帧如下:
 *
 *	| STRING AREA |
 *	+-------------+
 *	|      0      |	
*	+-------------+
 *	|  apple[n]   |
 *	+-------------+
 *	       :
 *	+-------------+
 *	|  apple[0]   | 
 *	+-------------+ 
 *	|      0      |
 *	+-------------+
 *	|    env[n]   |
 *	+-------------+
 *	       :
 *	       :
 *	+-------------+
 *	|    env[0]   |
 *	+-------------+
 *	|      0      |
 *	+-------------+
 *	| arg[argc-1] |
 *	+-------------+
 *	       :
 *	       :
 *	+-------------+
 *	|    arg[0]   |
 *	+-------------+
 *	|     argc    |
 *	+-------------+
 * sp->	|      mh     | a.out 文件偏移量 0 在内存中的地址
 *	+-------------+
 *
 *	Where arg[i] and env[i] point into the STRING AREA
 *
 *  从下述汇编代码看出 __dyld_start() 内部调用函数 dyldbootstrap::start(app_mh, argc, argv, slide, dyld_mh, &startGlue)
 */

	.globl __dyld_start


#ifdef __i386__
	.data
__dyld_start_static_picbase: 
	.long   L__dyld_start_picbase


	.text
	.align 2
# stable entry points into dyld
	.globl	_stub_binding_helper
_stub_binding_helper:
	jmp	_stub_binding_helper_interface
	nop
	nop
	nop
	.globl	_dyld_func_lookup
_dyld_func_lookup:
	jmp	__Z18lookupDyldFunctionPKcPm

	.text
	.align	4, 0x90
	.globl __dyld_start
__dyld_start:
	pushl	$0		# 在帧标记的调试器端 push 0
	movl	%esp,%ebp	# 指向基于内核帧的指针  （ %rsp 栈指针寄存器，指向栈顶）
	andl    $-16,%esp       # 强制SSE对齐
	
	# 调用函数 dyldbootstrap::start(app_mh, argc, argv, slide)
	call    L__dyld_start_picbase
L__dyld_start_picbase:	
	popl	%ebx		# set %ebx to runtime value of picbase
    	movl	__dyld_start_static_picbase-L__dyld_start_picbase(%ebx), %eax
	subl    %eax, %ebx      # slide = L__dyld_start_picbase - [__dyld_start_static_picbase]
	pushl   %ebx		# param4 = slide
	lea     12(%ebp),%ebx	
	pushl   %ebx		# param3 = argv
	movl	8(%ebp),%ebx	
	pushl   %ebx		# param2 = argc
	movl	4(%ebp),%ebx	
	pushl   %ebx		# param1 = mh
	call	__ZN13dyldbootstrap5startEPK11mach_headeriPPKcl	

    	# 清理堆栈并跳转到结果
	movl	%ebp,%esp	# 还原未对齐的堆栈指针
	addl	$8,%esp		# 移除 mh 参数，调试器结束帧标记
	movl	$0,%ebp		# 将 ebp 恢复为零
	jmp	*%eax		# 跳到入口点


	.globl dyld_stub_binding_helper
dyld_stub_binding_helper:
	hlt
L_end:
#endif /* __i386__ */


#if __x86_64__
	.data
	.align 3
__dyld_start_static: 
	.quad   __dyld_start

# stable entry points into dyld
	.text
	.align 2
	.globl	_stub_binding_helper
_stub_binding_helper:
	jmp	_stub_binding_helper_interface
	nop
	nop
	nop
	.globl	_dyld_func_lookup
_dyld_func_lookup:
	jmp	__Z18lookupDyldFunctionPKcPm

	.text
	.align 2,0x90
	.globl __dyld_start
__dyld_start:
	pushq	$0		# 在帧标记的调试器端 push 0
	movq	%rsp,%rbp	# 指向基于内核帧的指针  （ %rsp 栈指针寄存器，指向栈顶）
	andq    $-16,%rsp       # 强制SSE对齐
	
	# 调用函数 dyldbootstrap::start(app_mh, argc, argv, slide)
	movq	8(%rbp),%rdi	# param1 = mh into %rdi （ %rdi 对应第1个函数参数）
	movl	16(%rbp),%esi	# param2 = argc into %esi （ %esi 对应第2个函数参数）
	leaq	24(%rbp),%rdx	# param3 = &argv[0] into %rdx （ %rdx 对应第3个函数参数）
	movq	__dyld_start_static(%rip), %r8
	leaq	__dyld_start(%rip), %rcx
	subq	 %r8, %rcx	# param4 = slide into %rcx （ %rdx 对应第4个函数参数）
	call	__ZN13dyldbootstrap5startEPK11mach_headeriPPKcl	

    	# 清理堆栈并跳转到结果
	movq	%rbp,%rsp	# 还原未对齐的堆栈指针
	addq	$16,%rsp	# 移除 mh 参数，调试器结束帧标记
	movq	$0,%rbp		# 将 ebp 恢复为零
	jmp	*%rax		# 跳到入口点 （ %rax 作为函数返回值使用）
	
#endif /* __x86_64__ */


#if __ppc__ || __ppc64__
#include <architecture/ppc/mode_independent_asm.h>

	.data
	.align 2
__dyld_start_static_picbase: 
	.g_long   L__dyld_start_picbase

#if __ppc__	
	.set L_mh_offset,0
	.set L_argc_offset,4
	.set L_argv_offset,8
#else
	.set L_mh_offset,0
	.set L_argc_offset,8	; stack is 8-byte aligned and there is a 4-byte hole between argc and argv
	.set L_argv_offset,16
#endif

	.text
	.align 2
; stable entry points into dyld
	.globl	_stub_binding_helper
_stub_binding_helper:
	b	_stub_binding_helper_interface
	nop 
	.globl	_dyld_func_lookup
_dyld_func_lookup:
	b	__Z18lookupDyldFunctionPKcPm
	
	
	
	.text
	.align 2
__dyld_start:
	mr	r26,r1		; save original stack pointer into r26
	subi	r1,r1,GPR_BYTES	; make space for linkage
	clrrgi	r1,r1,5		; align to 32 bytes
	addi	r0,0,0		; load 0 into r0
	stg	r0,0(r1)	; terminate initial stack frame
	stgu	r1,-SF_MINSIZE(r1); allocate minimal stack frame
		
	; call dyldbootstrap::start(app_mh, argc, argv, slide)
	lg	r3,L_mh_offset(r26)	; r3 = mach_header
	lwz	r4,L_argc_offset(r26)	; r4 = argc (int == 4 bytes)
	addi	r5,r26,L_argv_offset	; r5 = argv
	bcl	20,31,L__dyld_start_picbase	
L__dyld_start_picbase:	
	mflr	r31		; put address of L__dyld_start_picbase in r31
	addis   r6,r31,ha16(__dyld_start_static_picbase-L__dyld_start_picbase)
	lg      r6,lo16(__dyld_start_static_picbase-L__dyld_start_picbase)(r6)
	subf    r6,r6,r31       ; r6 = slide
	bl	__ZN13dyldbootstrap5startEPK11mach_headeriPPKcl	
	
	; clean up stack and jump to result
	mtctr	r3		; Put entry point in count register
	mr	r12,r3		;  also put in r12 for ABI convention.
	addi	r1,r26,GPR_BYTES; Restore the stack pointer and remove the
				;  mach_header argument.
	bctr			; jump to the program's entry point

	.globl dyld_stub_binding_helper
dyld_stub_binding_helper:
	trap
L_end:
#endif /* __ppc__ */


/* dyld 调用此函数来终止进程。
 * 它有一个标签，用于 CrashReporter 区分 此种终止 与 随机崩溃。 rdar://problem/4764143
 */
	.text
	.align 2
	.globl	_dyld_fatal_error
_dyld_fatal_error:
#if __ppc__ || __ppc64__
    trap
#elif __x86_64__ || __i386__
    int3
#else
    #error unknown architecture
#endif

    
    


