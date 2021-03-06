/* memcmp/wmemcmp optimized with AVX2.
   Copyright (C) 2017-2019 Free Software Foundation, Inc.
   This file is part of the GNU C Library.

   The GNU C Library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   The GNU C Library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with the GNU C Library; if not, see
   <http://www.gnu.org/licenses/>.  */

//AT&T风格代码 op src, dest
//寻址 section:disp(base, index, scale) -> disp + base + index * scale

/*
cmp{bwl}	 	reg[8|16|32], r/m[8|16|32]
cmp{bwl} 		r/m[8|16|32], reg[8|16|32]
cmp{bwl}	 	imm[8|16|32], r/m[8|16|32]
*/
#if IS_IN (libc)

/* memcmp/wmemcmp is implemented as:
   1. For size from 2 to 7 bytes, load as big endian with movbe and bswap
      to avoid branches.
   2. Use overlapping compare to avoid branch.
   3. Use vector compare when size >= 4 bytes for memcmp or size >= 8
      bytes for wmemcmp.
   4. If size is 8 * VEC_SIZE or less, unroll the loop.
   5. Compare 4 * VEC_SIZE at a time with the aligned first memory
      area.
   6. Use 2 vector compares when size is 2 * VEC_SIZE or less.
   7. Use 4 vector compares when size is 4 * VEC_SIZE or less.
   8. Use 8 vector compares when size is 8 * VEC_SIZE or less.  */

# include <sysdep.h>

# ifndef MEMCMP
#  define MEMCMP	__memcmp_avx2_movbe
# endif

# ifdef USE_AS_WMEMCMP
#  define VPCMPEQ	vpcmpeqd	//double word
# else
#  define VPCMPEQ	vpcmpeqb	//word
# endif

# ifndef VZEROUPPER
#  define VZEROUPPER	vzeroupper
# endif

# define VEC_SIZE 32
# define VEC_MASK ((1 << VEC_SIZE) - 1)

/* Warning!
           wmemcmp has to use SIGNED comparison for elements.
           memcmp has to use UNSIGNED comparison for elemnts.
*/

	.section .text.avx,"ax",@progbits
ENTRY (MEMCMP)
# ifdef USE_AS_WMEMCMP
	shl	$2, %RDX_LP
# elif defined __ILP32__
	/* Clear the upper 32 bits.  */
	movl	%edx, %edx
# endif
	cmp	$VEC_SIZE, %RDX_LP	//根据 %RDX_LP-$VEC_SIZE设置flag
	jb	L(less_vec)	/*相当于jl，b是below的意思，RDX_LP(比较长度)内容小于VEC_SIZE的时候就跳转*/

	/* From VEC to 2 * VEC.  No branch when size == VEC_SIZE.  */
	vmovdqu	(%rsi), %ymm2		//ymm是32byte 
	VPCMPEQ (%rdi), %ymm2, %ymm2
	vpmovmskb %ymm2, %eax		//这里是32位的掩码
	subl    $VEC_MASK, %eax
	jnz	L(first_vec)

	cmpq	$(VEC_SIZE * 2), %rdx
	jbe	L(last_vec)		//比较完了前面的32byte，后面小于32  VEC-2*VEC

	VPCMPEQ	%ymm0, %ymm0, %ymm0	//把ymm都设置成1
	/* More than 2 * VEC.  */
	cmpq	$(VEC_SIZE * 8), %rdx
	ja	L(more_8x_vec)
	cmpq	$(VEC_SIZE * 4), %rdx
	jb	L(last_4x_vec)		//2*VEC-4*VEC

	/* From 4 * VEC to 8 * VEC, inclusively. */
	vmovdqu	(%rsi), %ymm1		//4路比较，结果分别放在ymm1-4中
	VPCMPEQ (%rdi), %ymm1, %ymm1	//相等就都设为1

	vmovdqu	VEC_SIZE(%rsi), %ymm2
	VPCMPEQ VEC_SIZE(%rdi), %ymm2, %ymm2

	vmovdqu	(VEC_SIZE * 2)(%rsi), %ymm3
	VPCMPEQ (VEC_SIZE * 2)(%rdi), %ymm3, %ymm3

	vmovdqu	(VEC_SIZE * 3)(%rsi), %ymm4
	VPCMPEQ (VEC_SIZE * 3)(%rdi), %ymm4, %ymm4

	vpand	%ymm1, %ymm2, %ymm5	//与
	vpand	%ymm3, %ymm4, %ymm6
	vpand	%ymm5, %ymm6, %ymm5	//4路结果的与放在ymm5中

	vptest	%ymm0, %ymm5		//如果ymm0&(~ymm5)全是0，设置CF（也就是ymm5全是1,也就是是全相等）
	jnc	L(4x_vec_end)		//前4×32里有至少一个不一样的情况

	leaq	-(4 * VEC_SIZE)(%rdi, %rdx), %rdi
	leaq	-(4 * VEC_SIZE)(%rsi, %rdx), %rsi
	vmovdqu	(%rsi), %ymm1
	VPCMPEQ (%rdi), %ymm1, %ymm1

	vmovdqu	VEC_SIZE(%rsi), %ymm2
	VPCMPEQ VEC_SIZE(%rdi), %ymm2, %ymm2
	vpand	%ymm2, %ymm1, %ymm5

	vmovdqu	(VEC_SIZE * 2)(%rsi), %ymm3
	VPCMPEQ (VEC_SIZE * 2)(%rdi), %ymm3, %ymm3
	vpand	%ymm3, %ymm5, %ymm5

	vmovdqu	(VEC_SIZE * 3)(%rsi), %ymm4
	VPCMPEQ (VEC_SIZE * 3)(%rdi), %ymm4, %ymm4
	vpand	%ymm4, %ymm5, %ymm5

	vptest	%ymm0, %ymm5
	jnc	L(4x_vec_end)
	xorl	%eax, %eax
	VZEROUPPER
	ret

	.p2align 4
L(last_2x_vec):
	/* From VEC to 2 * VEC.  No branch when size == VEC_SIZE.  */
	vmovdqu	(%rsi), %ymm2
	VPCMPEQ (%rdi), %ymm2, %ymm2
	vpmovmskb %ymm2, %eax
	subl    $VEC_MASK, %eax
	jnz	L(first_vec)

L(last_vec):
	/* Use overlapping loads to avoid branches.  */
	leaq	-VEC_SIZE(%rdi, %rdx), %rdi	//结尾减32
	leaq	-VEC_SIZE(%rsi, %rdx), %rsi
	vmovdqu	(%rsi), %ymm2
	VPCMPEQ (%rdi), %ymm2, %ymm2
	vpmovmskb %ymm2, %eax		//32位的掩码
	subl    $VEC_MASK, %eax
	jnz	L(first_vec)	//不相等就跳转,这里为什么不直接返回呢,因为不能确定返回大于还是小于0的数
	VZEROUPPER	//这里都要返回了，为什么还要清零ymm的高位呢？
	ret

	.p2align 4
L(first_vec):
	/* A byte or int32 is different within 16 or 32 bytes.  */
	tzcntl	%eax, %ecx	//把%eax结尾的（least sinificant bits）0的个数存在%ecx,也就是相同的长度
# ifdef USE_AS_WMEMCMP
	xorl	%eax, %eax
	movl	(%rdi, %rcx), %edx
	cmpl	(%rsi, %rcx), %edx
L(wmemcmp_return):	//跳转到这里执行完会不会执行#else里的内容？
	setl	%al		//小于的话设%al为1
	negl	%eax
	orl	$1, %eax	//为什么要orl一下？
# else
	movzbl	(%rdi, %rcx), %eax	//zero extend,byte到long,把不同的地方的字符分别移到eax和edx
	movzbl	(%rsi, %rcx), %edx
	sub	%edx, %eax
# endif
	VZEROUPPER	//清空128及以上的高位
	ret

# ifdef USE_AS_WMEMCMP
	.p2align 4
L(4):
	xorl	%eax, %eax	//等于的话直接返回0
	movl	(%rdi), %edx
	cmpl	(%rsi), %edx
	jne	L(wmemcmp_return)
	ret
# else
	.p2align 4
L(between_4_7):
	/* Load as big endian with overlapping movbe to avoid branches.  */
	movbe	(%rdi), %eax
	movbe	(%rsi), %ecx
	shlq	$32, %rax
	shlq	$32, %rcx
	movbe	-4(%rdi, %rdx), %edi
	movbe	-4(%rsi, %rdx), %esi
	orq	%rdi, %rax
	orq	%rsi, %rcx
	subq	%rcx, %rax
	je	L(exit)
	sbbl	%eax, %eax
	orl	$1, %eax
	ret

	.p2align 4
L(exit):
	ret

	.p2align 4
L(between_2_3):
	/* Load as big endian to avoid branches.  */
	movzwl	(%rdi), %eax	//把16位扩展成32位
	movzwl	(%rsi), %ecx
	shll	$8, %eax
	shll	$8, %ecx
	bswap	%eax			//交换大小端
	bswap	%ecx
	movb	-1(%rdi, %rdx), %al
	movb	-1(%rsi, %rdx), %cl
	/* Subtraction is okay because the upper 8 bits are zero.  */
	subl	%ecx, %eax	//这个应该是%eax-%ecx存到%eax里面
	ret

	.p2align 4
L(1):
	movzbl	(%rdi), %eax	//这里为什么用的movzbl？l是32位，高位会不会有影响
	movzbl	(%rsi), %ecx
	subl	%ecx, %eax
	ret
# endif

	.p2align 4
L(zero):
	xorl	%eax, %eax
	ret

	.p2align 4
L(less_vec):
# ifdef USE_AS_WMEMCMP
	/* It can only be 0, 4, 8, 12, 16, 20, 24, 28 bytes.  */
	cmpb	$4, %dl	//比较4和rdx的低8位
	je	L(4)
	jb	L(zero)	//小于4
# else		//node24上应该是没有USE_AN-WMEMCMP的
	cmpb	$1, %dl
	je	L(1)	//长度为1
	jb	L(zero)	//比较长度小于1就返回0
	cmpb	$4, %dl
	jb	L(between_2_3)
	cmpb	$8, %dl
	jb	L(between_4_7)
# endif
	cmpb	$16, %dl
	jae	L(between_16_31)	//大于等于就是16-31位
	/* It is between 8 and 15 bytes.  */
	vmovq	(%rdi), %xmm1	//xmm是128bits，16byte
	vmovq	(%rsi), %xmm2
	VPCMPEQ %xmm1, %xmm2, %xmm2		//相等就都设为1,否则就都是0	
	vpmovmskb %xmm2, %eax	//搜集每一byte的最高位组成掩码到%eax的低位
	subl    $0xffff, %eax	//0xffff(后面跳转之后用eax末尾0的个数表示相同的bytes),16位,正好和%eax的长度一样
	jnz	L(first_vec)
	/* Use overlapping loads to avoid branches.  */
	leaq	-8(%rdi, %rdx), %rdi	//结尾减8
	leaq	-8(%rsi, %rdx), %rsi
	vmovq	(%rdi), %xmm1
	vmovq	(%rsi), %xmm2
	VPCMPEQ %xmm1, %xmm2, %xmm2
	vpmovmskb %xmm2, %eax
	subl    $0xffff, %eax
	jnz	L(first_vec)	//这里如果是比较13位，第14位不相同的话跳转过去会怎么样？
	ret

	.p2align 4
L(between_16_31):
	/* From 16 to 31 bytes.  No branch when size == 16.  */
	vmovdqu	(%rsi), %xmm2	//xmm 是ymm的低128bits
	VPCMPEQ (%rdi), %xmm2, %xmm2
	vpmovmskb %xmm2, %eax
	subl    $0xffff, %eax
	jnz	L(first_vec)

	/* Use overlapping loads to avoid branches.  */
	leaq	-16(%rdi, %rdx), %rdi
	leaq	-16(%rsi, %rdx), %rsi
	vmovdqu	(%rsi), %xmm2
	VPCMPEQ (%rdi), %xmm2, %xmm2
	vpmovmskb %xmm2, %eax
	subl    $0xffff, %eax
	jnz	L(first_vec)
	ret

	.p2align 4
L(more_8x_vec):
	/* More than 8 * VEC.  Check the first VEC.  */
	vmovdqu	(%rsi), %ymm2
	VPCMPEQ (%rdi), %ymm2, %ymm2
	vpmovmskb %ymm2, %eax
	subl    $VEC_MASK, %eax
	jnz	L(first_vec)
	//没看懂
	/* Align the first memory area for aligned loads in the loop.
	   Compute how much the first memory area is misaligned.  */
	movq	%rdi, %rcx	//rdi,第一个参数，rsi，第二个参数,rdx,第三个参数
	andl	$(VEC_SIZE - 1), %ecx	//只保留末尾的5位,rcx前面的内容都清零了吗
	/* Get the negative of offset for alignment.  */
	subq	$VEC_SIZE, %rcx		//这里减是什么意思，会有溢出吗
	/* Adjust the second memory area.  */
	subq	%rcx, %rsi	//这里相当于是到了原本rsi的下一个32byte的开始吗？gdb试一下
	/* Adjust the first memory area which should be aligned now.  */
	subq	%rcx, %rdi
	/* Adjust length.  */
	addq	%rcx, %rdx

L(loop_4x_vec):
	/* Compare 4 * VEC at a time forward.  */
	vmovdqu	(%rsi), %ymm1
	VPCMPEQ (%rdi), %ymm1, %ymm1

	vmovdqu	VEC_SIZE(%rsi), %ymm2
	VPCMPEQ VEC_SIZE(%rdi), %ymm2, %ymm2
	vpand	%ymm2, %ymm1, %ymm5

	vmovdqu	(VEC_SIZE * 2)(%rsi), %ymm3
	VPCMPEQ (VEC_SIZE * 2)(%rdi), %ymm3, %ymm3
	vpand	%ymm3, %ymm5, %ymm5

	vmovdqu	(VEC_SIZE * 3)(%rsi), %ymm4
	VPCMPEQ (VEC_SIZE * 3)(%rdi), %ymm4, %ymm4
	vpand	%ymm4, %ymm5, %ymm5

	vptest	%ymm0, %ymm5
	jnc	L(4x_vec_end)

	addq	$(VEC_SIZE * 4), %rdi
	addq	$(VEC_SIZE * 4), %rsi

	subq	$(VEC_SIZE * 4), %rdx
	cmpq	$(VEC_SIZE * 4), %rdx
	jae	L(loop_4x_vec)

	/* Less than 4 * VEC.  */
	cmpq	$VEC_SIZE, %rdx
	jbe	L(last_vec)
	cmpq	$(VEC_SIZE * 2), %rdx
	jbe	L(last_2x_vec)

L(last_4x_vec):
	/* From 2 * VEC to 4 * VEC. */
	vmovdqu	(%rsi), %ymm2
	VPCMPEQ (%rdi), %ymm2, %ymm2
	vpmovmskb %ymm2, %eax
	subl    $VEC_MASK, %eax
	jnz	L(first_vec)

	addq	$VEC_SIZE, %rdi
	addq	$VEC_SIZE, %rsi
	vmovdqu	(%rsi), %ymm2
	VPCMPEQ (%rdi), %ymm2, %ymm2
	vpmovmskb %ymm2, %eax
	subl    $VEC_MASK, %eax
	jnz	L(first_vec)

	/* Use overlapping loads to avoid branches.  */
	leaq	-(3 * VEC_SIZE)(%rdi, %rdx), %rdi	//因为前面加了VEC，这里实际是比较的末尾-2×VEC
	leaq	-(3 * VEC_SIZE)(%rsi, %rdx), %rsi
	vmovdqu	(%rsi), %ymm2
	VPCMPEQ (%rdi), %ymm2, %ymm2
	vpmovmskb %ymm2, %eax
	subl    $VEC_MASK, %eax
	jnz	L(first_vec)

	addq	$VEC_SIZE, %rdi		//这里实际是结尾的最后一个VEC,我们可以在这情况直接用比较的长度（%rdx）减相同的长度
	addq	$VEC_SIZE, %rsi
	vmovdqu	(%rsi), %ymm2
	VPCMPEQ (%rdi), %ymm2, %ymm2
	vpmovmskb %ymm2, %eax
	subl    $VEC_MASK, %eax
	jnz	L(first_vec)
	VZEROUPPER
	ret

	.p2align 4
L(4x_vec_end):
	vpmovmskb %ymm1, %eax		//32位的掩码
	subl	$VEC_MASK, %eax
	jnz	L(first_vec)
	vpmovmskb %ymm2, %eax
	subl	$VEC_MASK, %eax
	jnz	L(first_vec_x1)
	vpmovmskb %ymm3, %eax
	subl	$VEC_MASK, %eax
	jnz	L(first_vec_x2)
	vpmovmskb %ymm4, %eax
	subl	$VEC_MASK, %eax
	tzcntl	%eax, %ecx	//结尾0的长度,也就是相等的长度
# ifdef USE_AS_WMEMCMP
	xorl	%eax, %eax
	movl	(VEC_SIZE * 3)(%rdi, %rcx), %edx
	cmpl	(VEC_SIZE * 3)(%rsi, %rcx), %edx
	jmp	L(wmemcmp_return)
# else
	movzbl	(VEC_SIZE * 3)(%rdi, %rcx), %eax	//见过这种语法，跳转到最后的不一样的地方，没太看懂
	movzbl	(VEC_SIZE * 3)(%rsi, %rcx), %edx
	sub	%edx, %eax
# endif
	VZEROUPPER
	ret
//比较同一个vec×4（128byte）里面第1/2个（从0开始）32byte
	.p2align 4
L(first_vec_x1):
	tzcntl	%eax, %ecx
# ifdef USE_AS_WMEMCMP
	xorl	%eax, %eax
	movl	VEC_SIZE(%rdi, %rcx), %edx
	cmpl	VEC_SIZE(%rsi, %rcx), %edx
	jmp	L(wmemcmp_return)
# else
	movzbl	VEC_SIZE(%rdi, %rcx), %eax
	movzbl	VEC_SIZE(%rsi, %rcx), %edx
	sub	%edx, %eax
# endif
	VZEROUPPER
	ret

	.p2align 4
L(first_vec_x2):
	tzcntl	%eax, %ecx
# ifdef USE_AS_WMEMCMP
	xorl	%eax, %eax
	movl	(VEC_SIZE * 2)(%rdi, %rcx), %edx
	cmpl	(VEC_SIZE * 2)(%rsi, %rcx), %edx
	jmp	L(wmemcmp_return)
# else
	movzbl	(VEC_SIZE * 2)(%rdi, %rcx), %eax
	movzbl	(VEC_SIZE * 2)(%rsi, %rcx), %edx
	sub	%edx, %eax
# endif
	VZEROUPPER
	ret
END (MEMCMP)
#endif
