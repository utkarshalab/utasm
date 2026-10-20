; scripts/compat/disasm_gen.s - the disassembler suite: an instance of each
; form the disassembler reads by tools/disasm/x86_tables.inc generated
; entries (scripts/gen_x86_tables.py evex_generated / vex_generated, from
; the encoder forms), assembled by utasm and read back against objdump
bits 64
vmovddup xmm7, qword [rdi+rbx*4-128]
vmovddup xmm15, qword [r13+r8*8+128]
vmovddup ymm7, ymm5
vmovddup ymm9, ymm1
vmovhlps xmm9, xmm0, xmm0
vmovhlps xmm12, xmm1, xmm14
vmovhpd xmm2, xmm13, qword [rdi+8]
vmovhpd xmm3, xmm14, qword [rsi+rax*2+128]
vmovhpd qword [r11], xmm13
vmovhpd qword [rax], xmm3
vmovhps xmm14, xmm11, qword [r8+rbx*4+8]
vmovhps xmm2, xmm3, qword [r14+8]
vmovhps qword [rbx+r11*1+127], xmm11
vmovhps qword [r12+rax*4+8], xmm6
vmovlhps xmm15, xmm5, xmm11
vmovlhps xmm4, xmm1, xmm11
vmovlpd xmm4, xmm14, qword [r10-128]
vmovlpd xmm5, xmm13, qword [rbp+r13*4+127]
vmovlpd qword [rdi-128], xmm11
vmovlpd qword [r8+r15*1+8], xmm5
vmovlps xmm15, xmm10, qword [rsp+128]
vmovlps xmm9, xmm1, qword [r9+rbx*8+74565]
vmovlps qword [r15-128], xmm5
vmovlps qword [rsp+rdi*8-128], xmm8
vpsllw xmm2, xmm1, xmm4
vpsllw xmm10, xmm3, oword [rbp+r8*1+74565]
vpsllw xmm2, xmm10, 0
vpsllw xmm3, xmm3, 0
vpslld xmm13, xmm10, oword [r15+74565]
vpslld xmm12, xmm12, oword [rbp*8]
vpslld xmm0, xmm3, -1
vpslld xmm14, xmm10, 1
vpsllq xmm3, xmm4, oword [8]
vpsllq xmm13, xmm6, oword [r15+rbp*1]
vpsllq xmm4, xmm1, 1
vpsllq xmm7, xmm5, 1
vpsraw xmm6, xmm6, xmm10
vpsraw xmm7, xmm15, xmm4
vpsraw xmm6, xmm7, -128
vpsraw xmm5, xmm12, 1
vpsrad xmm2, xmm4, xmm2
vpsrad xmm5, xmm2, oword [r11+8]
vpsrad xmm10, xmm12, -128
vpsrad xmm7, xmm6, 1
vpsrlw xmm9, xmm6, oword [r11+74565]
vpsrlw xmm7, xmm7, xmm14
vpsrlw xmm13, xmm13, -1
vpsrlw xmm5, xmm6, -128
vpsrld xmm0, xmm6, xmm2
vpsrld xmm14, xmm9, oword [r8+r15*4-128]
vpsrld xmm11, xmm2, 5
vpsrld xmm1, xmm7, 0
vpsrlq xmm11, xmm7, xmm9
vpsrlq xmm6, xmm10, xmm4
vpsrlq xmm7, xmm9, 1
vpsrlq xmm13, xmm3, 0
vcvtps2ph oword [rsp+8], ymm14, -128
vcvtps2ph oword [rcx-128], ymm6, 5
vcvtps2ph xmm2, xmm14, -1
vcvtps2ph xmm7, xmm5, 127
slwpcb eax
slwpcb r10d
slwpcb rax
slwpcb r12
lwpval esp, dword [r11], 128
lwpval eax, r8d, -1
lwpval rbp, ecx, 305419896
lwpval r8, dword [r13-8], 128
lwpins r8d, esi, 1
lwpins eax, ebp, -1
lwpins r12, dword [r15-128], -1
lwpins r8, dword [r9*1], -1
vfmaddpd xmm10, xmm12, oword [rbp+127], xmm12
vfmaddpd xmm4, xmm7, xmm8, xmm15
vfmaddpd ymm1, ymm11, ymm6, ymm12
vfmaddpd ymm15, ymm2, yword [r15+r15*1], ymm15
vfmaddpd xmm12, xmm8, xmm15, xmm4
vfmaddpd xmm12, xmm14, xmm9, xmm4
vfmaddpd ymm11, ymm15, ymm13, yword [8]
vfmaddpd ymm0, ymm13, ymm5, ymm13
vfmaddps xmm11, xmm1, oword [rax-128], xmm2
vfmaddps xmm5, xmm3, xmm6, xmm4
vfmaddps ymm3, ymm4, ymm13, ymm10
vfmaddps ymm11, ymm14, ymm3, ymm7
vfmaddps xmm2, xmm1, xmm0, oword [74565]
vfmaddps xmm11, xmm8, xmm7, oword [rsp+rbx*8-128]
vfmaddps ymm4, ymm1, ymm15, ymm13
vfmaddps ymm7, ymm13, ymm14, yword [rax+128]
vfmaddsd xmm1, xmm9, xmm0, xmm1
vfmaddsd xmm3, xmm6, xmm5, xmm9
vfmaddsd xmm14, xmm5, xmm9, xmm14
vfmaddsd xmm0, xmm5, xmm3, xmm6
vfmaddss xmm14, xmm1, dword [rsp+8], xmm3
vfmaddss xmm2, xmm11, dword [rax], xmm6
vfmaddss xmm4, xmm12, xmm3, dword [r8-8]
vfmaddss xmm11, xmm15, xmm11, dword [rdx]
vfmaddsubpd xmm0, xmm10, xmm7, xmm15
vfmaddsubpd xmm15, xmm4, xmm9, xmm0
vfmaddsubpd ymm4, ymm6, ymm0, ymm6
vfmaddsubpd ymm14, ymm11, ymm2, ymm2
vfmaddsubpd xmm4, xmm3, xmm15, xmm10
vfmaddsubpd xmm10, xmm15, xmm11, xmm12
vfmaddsubpd ymm3, ymm14, ymm5, ymm2
vfmaddsubpd ymm2, ymm11, ymm9, ymm0
vfmaddsubps xmm1, xmm3, oword [rdx+127], xmm4
vfmaddsubps xmm0, xmm10, xmm10, xmm8
vfmaddsubps ymm12, ymm5, ymm4, ymm15
vfmaddsubps ymm5, ymm13, ymm13, ymm13
vfmaddsubps xmm13, xmm4, xmm5, xmm6
vfmaddsubps xmm1, xmm15, xmm5, xmm12
vfmaddsubps ymm0, ymm12, ymm5, yword [r14+rax*2-8]
vfmaddsubps ymm2, ymm7, ymm13, ymm6
vfmsubaddpd xmm2, xmm6, oword [r9+rbx*8], xmm4
vfmsubaddpd xmm12, xmm3, xmm13, xmm8
vfmsubaddpd ymm0, ymm0, yword [r11-8], ymm14
vfmsubaddpd ymm6, ymm4, ymm8, ymm4
vfmsubaddpd xmm8, xmm10, xmm4, xmm8
vfmsubaddpd xmm0, xmm5, xmm9, xmm3
vfmsubaddpd ymm4, ymm14, ymm6, ymm2
vfmsubaddpd ymm7, ymm6, ymm15, ymm5
vfmsubaddps xmm1, xmm3, oword [r12+r11*1+127], xmm10
vfmsubaddps xmm12, xmm2, xmm9, xmm14
vfmsubaddps ymm15, ymm3, yword [r13+r12*1], ymm4
vfmsubaddps ymm11, ymm13, ymm15, ymm15
vfmsubaddps xmm8, xmm3, xmm6, xmm0
vfmsubaddps xmm11, xmm12, xmm0, oword [r10+r11*4]
vfmsubaddps ymm9, ymm12, ymm12, ymm10
vfmsubaddps ymm4, ymm15, ymm0, ymm9
vfmsubpd xmm8, xmm14, oword [rsi+8], xmm11
vfmsubpd xmm11, xmm4, xmm0, xmm6
vfmsubpd ymm13, ymm14, yword [rdx*4-128], ymm0
vfmsubpd ymm8, ymm7, ymm9, ymm2
vfmsubpd xmm2, xmm0, xmm12, oword [4096]
vfmsubpd xmm5, xmm9, xmm12, xmm3
vfmsubpd ymm10, ymm1, ymm5, yword [r9+8]
vfmsubpd ymm5, ymm14, ymm8, ymm0
vfmsubps xmm4, xmm15, oword [rsi+8], xmm11
vfmsubps xmm15, xmm3, xmm11, xmm3
vfmsubps ymm8, ymm5, ymm13, ymm5
vfmsubps ymm10, ymm4, yword [r15], ymm15
vfmsubps xmm15, xmm11, xmm7, xmm12
vfmsubps xmm13, xmm4, xmm9, xmm7
vfmsubps ymm2, ymm1, ymm2, ymm13
vfmsubps ymm6, ymm1, ymm5, yword [r14+r11*1]
vfmsubsd xmm7, xmm14, xmm0, xmm11
vfmsubsd xmm0, xmm0, xmm11, xmm2
vfmsubsd xmm6, xmm9, xmm15, xmm11
vfmsubsd xmm13, xmm15, xmm12, qword [r14+rcx*2+74565]
vfmsubss xmm7, xmm4, xmm3, xmm0
vfmsubss xmm7, xmm1, xmm14, xmm4
vfmsubss xmm15, xmm14, xmm14, dword [r15+8]
vfmsubss xmm14, xmm1, xmm0, dword [r13-128]
vfnmaddpd xmm13, xmm11, oword [rbx+8], xmm0
vfnmaddpd xmm8, xmm1, oword [rcx+r15*8+128], xmm0
vfnmaddpd ymm12, ymm7, ymm0, ymm3
vfnmaddpd ymm15, ymm6, yword [rax+74565], ymm14
vfnmaddpd xmm3, xmm14, xmm6, oword [r10+128]
vfnmaddpd xmm3, xmm8, xmm11, oword [rcx-128]
vfnmaddpd ymm4, ymm10, ymm7, yword [rsi*2+74565]
vfnmaddpd ymm5, ymm6, ymm1, ymm5
vfnmaddps xmm5, xmm13, oword [rbp+r9*8], xmm12
vfnmaddps xmm9, xmm9, oword [rbx+r15*4-128], xmm6
vfnmaddps ymm9, ymm9, ymm9, ymm3
vfnmaddps ymm7, ymm9, ymm12, ymm0
vfnmaddps xmm9, xmm10, xmm12, oword [rsi+r9*2]
vfnmaddps xmm6, xmm13, xmm14, oword [r15-8]
vfnmaddps ymm10, ymm4, ymm10, yword [rbp*2]
vfnmaddps ymm11, ymm4, ymm5, yword [r15+127]
vfnmaddsd xmm1, xmm15, xmm5, xmm14
vfnmaddsd xmm14, xmm8, xmm6, xmm9
vfnmaddsd xmm8, xmm12, xmm13, xmm9
vfnmaddsd xmm0, xmm7, xmm3, xmm7
vfnmaddss xmm14, xmm11, dword [r15+r10*2+128], xmm13
vfnmaddss xmm7, xmm4, dword [rsi+rbp*1+127], xmm0
vfnmaddss xmm12, xmm12, xmm12, dword [rbp-8]
vfnmaddss xmm7, xmm0, xmm0, xmm2
vfnmsubpd xmm10, xmm10, oword [rsi+rdx*8], xmm10
vfnmsubpd xmm13, xmm13, oword [rax], xmm10
vfnmsubpd ymm3, ymm15, ymm9, ymm14
vfnmsubpd ymm1, ymm11, ymm13, ymm1
vfnmsubpd xmm11, xmm10, xmm9, xmm8
vfnmsubpd xmm4, xmm2, xmm14, xmm1
vfnmsubpd ymm6, ymm11, ymm5, yword [r13+8]
vfnmsubpd ymm2, ymm2, ymm12, ymm10
vfnmsubps xmm9, xmm7, xmm11, xmm4
vfnmsubps xmm6, xmm3, oword [r11+rcx*8+127], xmm8
vfnmsubps ymm1, ymm5, ymm7, ymm10
vfnmsubps ymm11, ymm13, yword [127], ymm6
vfnmsubps xmm7, xmm1, xmm1, oword [rsi+128]
vfnmsubps xmm13, xmm12, xmm10, xmm9
vfnmsubps ymm12, ymm11, ymm10, ymm10
vfnmsubps ymm14, ymm9, ymm6, yword [r15-8]
vfnmsubsd xmm10, xmm2, qword [rsi], xmm11
vfnmsubsd xmm10, xmm0, xmm13, xmm9
vfnmsubsd xmm5, xmm3, xmm13, xmm9
vfnmsubsd xmm14, xmm8, xmm10, xmm11
vfnmsubss xmm13, xmm6, dword [rbx-128], xmm13
vfnmsubss xmm0, xmm13, dword [r12-8], xmm4
vfnmsubss xmm3, xmm0, xmm14, dword [r8-8]
vfnmsubss xmm6, xmm2, xmm14, xmm13
vfrczpd xmm10, xmm13
vfrczpd xmm12, oword [rdx]
vfrczpd ymm4, ymm2
vfrczpd ymm0, yword [rcx+r15*2]
vfrczps xmm5, xmm11
vfrczps xmm0, oword [r15-128]
vfrczps ymm13, yword [rax]
vfrczps ymm1, ymm7
vfrczsd xmm12, xmm5
vfrczsd xmm8, qword [rdx+74565]
vfrczss xmm14, xmm11
vfrczss xmm4, dword [rdx+r15*4-128]
vpcmov xmm12, xmm1, xmm10, xmm9
vpcmov xmm1, xmm9, oword [r11], xmm14
vpcmov ymm8, ymm2, ymm14, ymm9
vpcmov ymm9, ymm3, ymm6, ymm4
vpcmov xmm1, xmm5, xmm1, oword [rdx+127]
vpcmov xmm4, xmm0, xmm1, xmm11
vpcmov ymm12, ymm1, ymm8, yword [r9+r11*8+8]
vpcmov ymm9, ymm8, ymm13, yword [r12+74565]
vpcomb xmm6, xmm9, xmm5, 127
vpcomb xmm2, xmm12, xmm14, -128
vpcomd xmm2, xmm11, oword [r11+r14*4-8], 5
vpcomd xmm2, xmm4, oword [4096], -128
vpcomq xmm9, xmm7, xmm1, 0
vpcomq xmm13, xmm7, oword [rax+rdx*2], 127
vpcomub xmm1, xmm11, oword [4096], -128
vpcomub xmm8, xmm15, oword [rbx+74565], 1
vpcomud xmm14, xmm4, xmm7, 5
vpcomud xmm7, xmm1, xmm15, 127
vpcomuq xmm2, xmm14, xmm0, 5
vpcomuq xmm6, xmm7, xmm9, -1
vpcomuw xmm6, xmm3, oword [r11+rcx*8], 127
vpcomuw xmm2, xmm10, xmm4, 1
vpcomw xmm15, xmm5, oword [rdx+8], -128
vpcomw xmm2, xmm0, oword [r12+74565], 127
vphaddbd xmm14, xmm7
vphaddbd xmm8, xmm15
vphaddbq xmm5, oword [rcx+r11*4+128]
vphaddbq xmm9, oword [rdx*8-128]
vphaddbw xmm3, oword [rdx+128]
vphaddbw xmm0, xmm7
vphadddq xmm8, xmm0
vphadddq xmm11, xmm9
vphaddubd xmm3, xmm9
vphaddubd xmm14, oword [rsp+rdi*8+127]
vphaddubq xmm13, xmm12
vphaddubq xmm11, oword [rbp+r15*1+128]
vphaddubw xmm8, oword [rsp+127]
vphaddubw xmm3, xmm8
vphaddudq xmm1, xmm6
vphaddudq xmm8, xmm3
vphadduwd xmm6, oword [r9-8]
vphadduwd xmm15, oword [r14+r9*8+127]
vphadduwq xmm8, oword [rdx+rbp*4+127]
vphadduwq xmm9, oword [r15+r13*8+74565]
vphaddwd xmm15, xmm11
vphaddwd xmm13, xmm4
vphaddwq xmm1, xmm7
vphaddwq xmm4, xmm9
vphsubbw xmm6, oword [r9*4+74565]
vphsubbw xmm5, oword [r11+r13*2+74565]
vphsubdq xmm5, xmm0
vphsubdq xmm13, oword [r15+8]
vphsubwd xmm2, xmm0
vphsubwd xmm10, oword [r13]
vpmacsdd xmm12, xmm14, xmm6, xmm2
vpmacsdd xmm7, xmm12, xmm14, xmm10
vpmacsdqh xmm8, xmm9, xmm12, xmm8
vpmacsdqh xmm14, xmm0, oword [r9+8], xmm7
vpmacsdql xmm8, xmm6, xmm13, xmm2
vpmacsdql xmm10, xmm3, xmm10, xmm8
vpmacssdd xmm2, xmm7, xmm10, xmm15
vpmacssdd xmm6, xmm6, xmm10, xmm7
vpmacssdqh xmm15, xmm11, xmm15, xmm5
vpmacssdqh xmm12, xmm15, xmm0, xmm14
vpmacssdql xmm3, xmm7, oword [r9+r9*1+127], xmm4
vpmacssdql xmm9, xmm6, xmm14, xmm6
vpmacsswd xmm9, xmm10, xmm4, xmm13
vpmacsswd xmm0, xmm4, oword [rcx], xmm1
vpmacssww xmm2, xmm8, oword [r13+rbx*4+8], xmm15
vpmacssww xmm2, xmm14, xmm15, xmm2
vpmacswd xmm4, xmm8, xmm3, xmm15
vpmacswd xmm13, xmm8, xmm7, xmm13
vpmacsww xmm6, xmm11, oword [r10+8], xmm1
vpmacsww xmm14, xmm2, xmm11, xmm2
vpmadcsswd xmm12, xmm0, oword [r8], xmm15
vpmadcsswd xmm6, xmm8, xmm3, xmm0
vpmadcswd xmm7, xmm12, xmm4, xmm6
vpmadcswd xmm7, xmm15, xmm1, xmm13
vpperm xmm13, xmm14, xmm13, xmm12
vpperm xmm1, xmm12, xmm13, xmm9
vpperm xmm7, xmm10, xmm2, xmm3
vpperm xmm13, xmm15, xmm11, xmm10
vprotb xmm2, xmm11, xmm10
vprotb xmm14, oword [rdi+rsi*1-128], xmm6
vprotb xmm15, xmm0, xmm1
vprotb xmm8, xmm3, oword [rax]
vprotb xmm8, xmm13, 5
vprotb xmm0, xmm13, 127
vprotd xmm2, oword [rbx+128], xmm7
vprotd xmm0, xmm11, xmm15
vprotd xmm0, xmm11, oword [rsi+127]
vprotd xmm8, xmm5, oword [rdi-8]
vprotd xmm9, xmm2, 5
vprotd xmm3, oword [rax*4-8], -1
vprotq xmm4, oword [r9*8+74565], xmm14
vprotq xmm13, xmm14, xmm13
vprotq xmm0, xmm11, oword [-128]
vprotq xmm8, xmm11, xmm4
vprotq xmm7, xmm7, -128
vprotq xmm8, oword [r13+74565], 5
vprotw xmm5, xmm15, xmm10
vprotw xmm2, oword [r14+128], xmm5
vprotw xmm9, xmm11, xmm13
vprotw xmm4, xmm6, oword [r14-8]
vprotw xmm12, oword [rcx+rdi*2], -1
vprotw xmm9, xmm4, 0
vpshab xmm3, xmm2, xmm12
vpshab xmm6, xmm8, xmm12
vpshab xmm0, xmm5, oword [rsi+8]
vpshab xmm9, xmm14, xmm12
vpshad xmm2, xmm12, xmm15
vpshad xmm9, xmm14, xmm4
vpshad xmm10, xmm1, oword [r14-8]
vpshad xmm4, xmm2, xmm4
vpshaq xmm2, oword [r14-128], xmm5
vpshaq xmm2, oword [rdi+rdi*2+74565], xmm3
vpshaq xmm5, xmm10, oword [r12+127]
vpshaq xmm5, xmm12, xmm15
vpshaw xmm14, xmm7, xmm15
vpshaw xmm5, xmm7, xmm4
vpshaw xmm3, xmm8, xmm8
vpshaw xmm11, xmm13, xmm11
vpshlb xmm6, xmm10, xmm4
vpshlb xmm0, oword [rbp-8], xmm0
vpshlb xmm7, xmm2, xmm12
vpshlb xmm10, xmm3, oword [r9+rax*8+8]
vpshld xmm14, oword [r12+r11*4], xmm14
vpshld xmm4, xmm8, xmm4
vpshld xmm4, xmm10, oword [rdx]
vpshld xmm1, xmm9, xmm5
vpshlq xmm7, oword [rsi+rdx*1-8], xmm0
vpshlq xmm9, xmm6, xmm14
vpshlq xmm7, xmm1, oword [rsi+rbx*8-8]
vpshlq xmm7, xmm9, oword [r9+r11*1+8]
vpshlw xmm13, xmm10, xmm5
vpshlw xmm15, xmm11, xmm5
vpshlw xmm6, xmm12, oword [rdx+r13*1-8]
vpshlw xmm1, xmm0, oword [rdx+8]
vpsllw ymm11, ymm6, oword [rax+127]
vpsllw ymm5, ymm15, xmm8
vpsllw ymm7, ymm9, 1
vpsllw ymm10, ymm6, -128
vpslld ymm9, ymm0, xmm5
vpslld ymm7, ymm7, xmm11
vpslld ymm11, ymm8, 1
vpslld ymm2, ymm2, -128
vpsllq ymm3, ymm13, xmm10
vpsllq ymm0, ymm15, oword [rsp+r10*8-8]
vpsllq ymm1, ymm7, -1
vpsllq ymm5, ymm4, 0
vpsraw ymm7, ymm5, oword [r14*2+127]
vpsraw ymm0, ymm10, xmm9
vpsraw ymm2, ymm14, 0
vpsraw ymm14, ymm7, -128
vpsrad ymm2, ymm7, oword [4096]
vpsrad ymm3, ymm1, xmm10
vpsrad ymm7, ymm9, 1
vpsrad ymm4, ymm8, 127
vpsrlw ymm1, ymm9, oword [-8]
vpsrlw ymm3, ymm9, xmm11
vpsrlw ymm0, ymm10, 127
vpsrlw ymm8, ymm4, 127
vpsrld ymm1, ymm5, oword [rbp]
vpsrld ymm15, ymm14, oword [r13+127]
vpsrld ymm12, ymm5, -128
vpsrld ymm13, ymm11, -1
vpsrlq ymm10, ymm12, oword [r11+rax*4-8]
vpsrlq ymm7, ymm4, oword [rsi+r9*2-128]
vpsrlq ymm15, ymm1, 0
vpsrlq ymm2, ymm7, 0
bextr esi, dword [r11+8], r11d
bextr r9d, ebp, r12d
bextr r10, r8, rdi
bextr rdx, r8, r10
bextr eax, edx, 305419896
bextr r14d, esp, 128
bextr r13, r12, 305419896
bextr r10, rbx, 128
blci r15d, r8d
blci edx, dword [r10+rsi*1]
blci rcx, r13
blci rcx, r11
blcic r14d, esp
blcic r13d, dword [r12+74565]
blcic r14, qword [r11+r12*1]
blcic rsp, rdx
blsic eax, dword [rcx-8]
blsic r9d, dword [rsi+rcx*2]
blsic r12, r15
blsic rdx, r12
blcfill ecx, dword [r10+r13*1]
blcfill eax, dword [rbx+rax*1]
blcfill rsi, qword [rdi+rdi*1-8]
blcfill rsp, rsi
blsfill ecx, dword [rax+8]
blsfill edi, edi
blsfill r11, r11
blsfill rsp, rsp
blcmsk esp, r9d
blcmsk edi, dword [r15+r10*8]
blcmsk r14, rbp
blcmsk rsp, rdx
blcs r12d, esi
blcs r15d, dword [rsi+127]
blcs rdi, rdx
blcs r8, qword [8]
tzmsk ecx, eax
tzmsk r15d, dword [8]
tzmsk r14, qword [r15+r13*8]
tzmsk r14, qword [rbx]
t1mskc r14d, r13d
t1mskc ebp, r8d
t1mskc r9, r14
t1mskc rsp, qword [r15]
vsha512msg1 ymm4, xmm8
vsha512msg1 ymm10, xmm0
vsha512msg2 ymm0, ymm5
vsha512msg2 ymm6, ymm15
vsha512rnds2 ymm2, ymm4, xmm8
vsha512rnds2 ymm6, ymm13, xmm2
vsm3msg1 xmm9, xmm11, xmm9
vsm3msg1 xmm9, xmm12, xmm2
vsm3msg2 xmm2, xmm12, xmm14
vsm3msg2 xmm6, xmm14, xmm11
vsm3rnds2 xmm3, xmm3, xmm9, -128
vsm3rnds2 xmm15, xmm9, xmm11, 5
vsm4key4 xmm10, xmm10, oword [rdi]
vsm4key4 xmm15, xmm8, xmm3
vsm4key4 ymm0, ymm5, ymm5
vsm4rnds4 xmm8, xmm3, oword [rax-8]
vsm4rnds4 xmm15, xmm15, xmm12
vsm4rnds4 ymm6, ymm0, ymm3
vsm4rnds4 ymm2, ymm0, ymm3
vcvtneps2bf16 xmm7, xmm9
vcvtneps2bf16 xmm6, xmm0
vpmadd52huq xmm6, xmm4, xmm6
vpmadd52huq xmm5, xmm10, oword [rbx+127]
vpmadd52huq ymm5, ymm15, yword [r15-8]
vpmadd52huq ymm8, ymm13, yword [r10-8]
vpmadd52luq xmm7, xmm15, oword [r15-8]
vpmadd52luq xmm4, xmm2, xmm15
vpmadd52luq ymm8, ymm6, yword [r9+128]
vpmadd52luq ymm14, ymm6, ymm14
vcvtpd2qq xmm28{k7}{z}, xmm2
vcvtpd2qq xmm11{k4}, xmm15
vcvtpd2qq ymm7{k1}{z}, ymm28
vcvtpd2qq ymm14{k4}{z}, ymm30
vcvtpd2qq zmm14{k7}{z}, zword [-128]
vcvtpd2qq zmm20, zword [r12*2-8]
vcvtpd2udq xmm11{k4}{z}, oword [rbp+r15*8+128]
vcvtpd2udq xmm28{k6}, oword [rsp+8]
vcvtpd2udq xmm3, yword [r10*8+127]
vcvtpd2udq xmm16, yword [rax+rbx*4-8]
vcvtpd2udq ymm15, zword [rdx+r11*8]
vcvtpd2udq ymm17, zword [rdi+74565]
vcvtpd2uqq xmm14{k4}{z}, xmm18
vcvtpd2uqq xmm15, oword [r15+127]
vcvtpd2uqq ymm2{k2}, yword [rsi-128]
vcvtpd2uqq ymm0, yword [r15-8]
vcvtpd2uqq zmm15{k3}, zword [r15+128]
vcvtpd2uqq zmm7, zmm29
vcvtps2ph xmm22, xmm5, 0
vcvtps2ph xmm10, xmm26, 5
vcvtps2ph xmm12{k2}, ymm0, 5
vcvtps2ph xmm19, ymm29, -1
vcvtps2ph ymm13, zmm8, -1
vcvtps2ph ymm5, zmm24, -1
vcvtps2ph qword [r9+rcx*1+8], xmm18, 1
vcvtps2ph qword [rdi+74565], xmm7, 1
vcvtps2ph oword [74565], ymm15, -128
vcvtps2ph oword [r9+rdi*8-8], ymm6, 0
vcvtps2ph yword [rsi+r15*4+128], zmm9, 1
vcvtps2ph yword [rsi+128], zmm16, 1
vcvtps2qq xmm7{k2}, xmm13
vcvtps2qq xmm27{k4}, xmm25
vcvtps2qq ymm6{k3}{z}, xmm16
vcvtps2qq ymm14, xmm10
vcvtps2qq zmm30{k2}{z}, yword [rcx-128]
vcvtps2qq zmm20{k7}{z}, yword [rbx-8]
vcvtps2udq xmm14{k7}{z}, xmm20
vcvtps2udq xmm8{k3}, xmm19
vcvtps2udq ymm3, yword [rsi+rdx*1-128]
vcvtps2udq ymm12, ymm16
vcvtps2udq zmm21, zword [4096]
vcvtps2udq zmm23{k5}{z}, zmm1
vcvtps2uqq xmm11, qword [rdx-8]
vcvtps2uqq xmm18{k3}, xmm28
vcvtps2uqq ymm30, xmm25
vcvtps2uqq ymm16, xmm18
vcvtps2uqq zmm24, yword [r13+8]
vcvtps2uqq zmm27, yword [r10+r11*1+127]
vcvtsd2usi edi, qword [rsp+r14*1+8]
vcvtsd2usi ebp, xmm18
vcvtsd2usi r12, xmm14
vcvtsd2usi rsp, xmm13
vcvtss2usi esp, dword [r12+rsi*4+128]
vcvtss2usi eax, dword [8]
vcvtss2usi r11, dword [rdi*1-8]
vcvtss2usi rdi, xmm26
vcvttpd2qq xmm1, xmm15
vcvttpd2qq xmm9{k2}{z}, oword [r15+127]
vcvttpd2qq ymm2{k2}, ymm19
vcvttpd2qq ymm5, yword [rbx]
vcvttpd2qq zmm11{k3}, zmm27
vcvttpd2qq zmm12, zword [rdi+rcx*4]
vcvttpd2udq xmm26, oword [r14-128]
vcvttpd2udq xmm24, oword [r13+rdx*2]
vcvttpd2udq xmm24{k3}{z}, ymm2
vcvttpd2udq xmm23, yword [rsi+r9*2-8]
vcvttpd2udq ymm10{k5}, zword [r14+74565]
vcvttpd2udq ymm26{k2}, zword [r12+r14*2+127]
vcvttpd2uqq xmm31, xmm9
vcvttpd2uqq xmm9, xmm22
vcvttpd2uqq ymm13, ymm24
vcvttpd2uqq ymm19, ymm11
vcvttpd2uqq zmm29, zmm4
vcvttpd2uqq zmm15, zmm16
vcvttps2qq xmm21, xmm12
vcvttps2qq xmm25{k7}, qword [r8+r15*1+74565]
vcvttps2qq ymm29{k2}, xmm31
vcvttps2qq ymm31{k1}{z}, oword [rcx+74565]
vcvttps2qq zmm16, ymm15
vcvttps2qq zmm12, yword [rsi-128]
vcvttps2udq xmm29{k6}{z}, xmm24
vcvttps2udq xmm2, oword [4096]
vcvttps2udq ymm19{k7}, yword [r9+rbp*1+74565]
vcvttps2udq ymm14{k2}, yword [r13+74565]
vcvttps2udq zmm24, zmm11
vcvttps2udq zmm17, zword [r11-8]
vcvttps2uqq xmm25, qword [rdx]
vcvttps2uqq xmm5{k6}, qword [r11+rbx*1-128]
vcvttps2uqq ymm8{k4}{z}, xmm18
vcvttps2uqq ymm1, xmm24
vcvttps2uqq zmm31, yword [r12+rdx*2+128]
vcvttps2uqq zmm28, yword [rbp+rbp*8+127]
vcvttsd2usi r10d, qword [r11*8+128]
vcvttsd2usi r12d, xmm15
vcvttsd2usi r13, xmm7
vcvttsd2usi rdi, qword [r11+74565]
vcvttss2usi r9d, xmm19
vcvttss2usi edi, dword [rsp+r10*8+128]
vcvttss2usi r12, dword [r13+127]
vcvttss2usi r14, dword [-8]
vcvtudq2pd xmm12{k7}, qword [r13]
vcvtudq2pd xmm1, qword [r13*2-8]
vcvtudq2pd ymm6{k2}, oword [rax+r8*2+8]
vcvtudq2pd ymm10, xmm22
vcvtudq2pd zmm19{k1}{z}, ymm10
vcvtudq2pd zmm11{k2}{z}, yword [rsp+r14*1+128]
vcvtudq2ps xmm5, oword [rdi+r10*8-8]
vcvtudq2ps xmm14, oword [rsp]
vcvtudq2ps ymm8{k4}{z}, ymm6
vcvtudq2ps ymm2{k4}{z}, yword [rbx+r13*2+128]
vcvtudq2ps zmm12{k1}, zword [4096]
vcvtudq2ps zmm1{k3}{z}, zmm31
vcvtuqq2pd xmm8{k7}{z}, xmm28
vcvtuqq2pd xmm7{k3}, oword [rdx*1+8]
vcvtuqq2pd ymm7, ymm6
vcvtuqq2pd ymm9, ymm8
vcvtuqq2pd zmm15{k4}{z}, zmm9
vcvtuqq2pd zmm31{k7}{z}, zword [rcx-8]
vcvtuqq2ps xmm3{k1}, oword [r14+rax*1-8]
vcvtuqq2ps xmm29, oword [rcx+128]
vcvtuqq2ps xmm23, yword [r15+127]
vcvtuqq2ps xmm1, yword [rbp*8+8]
vcvtuqq2ps ymm29{k4}{z}, zword [r9+74565]
vcvtuqq2ps ymm11{k5}, zmm7
vcvtusi2sd xmm10, xmm21, r10d
vcvtusi2sd xmm16, xmm21, dword [r12*8]
vcvtusi2sd xmm29, xmm18, qword [r8+rax*2]
vcvtusi2sd xmm15, xmm19, qword [rbp]
vcvtusi2ss xmm20, xmm4, esp
vcvtusi2ss xmm22, xmm12, dword [rdi+r13*2-8]
vcvtusi2ss xmm1, xmm9, rsp
vcvtusi2ss xmm18, xmm16, qword [r14+r11*8+127]
vexp2pd zmm31{k2}{z}, zmm8
vexp2pd zmm23, zword [rcx]
vexp2ps zmm31{k7}, zmm28
vexp2ps zmm15{k4}{z}, zmm2
vfixupimmpd xmm3{k7}{z}, xmm18, oword [127], 5
vfixupimmpd xmm28{k6}{z}, xmm29, xmm2, 0
vfixupimmpd ymm5, ymm25, ymm16, -128
vfixupimmpd ymm7, ymm4, yword [rsi+r13*8+127], 0
vfixupimmpd zmm30{k7}, zmm15, zmm23, -128
vfixupimmpd zmm29, zmm12, zmm11, 127
vfixupimmps xmm28, xmm22, oword [r11+8], 127
vfixupimmps xmm22{k1}{z}, xmm17, xmm25, 127
vfixupimmps ymm2{k2}, ymm22, yword [rcx+r12*4+127], 127
vfixupimmps ymm14{k1}, ymm12, ymm26, 5
vfixupimmps zmm6, zmm8, zword [r10+127], -1
vfixupimmps zmm13, zmm31, zword [rdi+rdx*4+128], 1
vfixupimmsd xmm19, xmm14, xmm16, 0
vfixupimmsd xmm17, xmm30, xmm8, 0
vfixupimmss xmm19, xmm1, dword [r8+74565], 5
vfixupimmss xmm20, xmm9, dword [r8+r8*4+128], 0
vfpclasspd k2, oword [r9+rsi*8], -1
vfpclasspd k5, xmm17, 0
vfpclasspd k5, yword [r9], 0
vfpclasspd k4, ymm30, 0
vfpclasspd k6, zmm29, 127
vfpclasspd k6{k6}, zmm31, 0
vfpclassps k2{k3}, xmm20, 5
vfpclassps k0{k5}, xmm0, 127
vfpclassps k2{k2}, yword [r9-8], -128
vfpclassps k4, ymm8, 1
vfpclassps k6, zmm0, 0
vfpclassps k7{k4}, zword [rsp], 127
vfpclasssd k3{k5}, xmm16, -1
vfpclasssd k0{k3}, xmm8, 1
vfpclassss k2{k5}, dword [rcx+rdi*1], -1
vfpclassss k6{k1}, xmm17, 1
vgatherpf0dpd qword [r11+ymm16*2-8]{k4}
vgatherpf0dpd qword [rbx+ymm9*8]{k3}
vgatherpf0dps dword [r11+zmm3*8]{k1}
vgatherpf0dps dword [zmm20*1+128]{k3}
vgatherpf0qpd qword [rsp+zmm17*8+8]{k3}
vgatherpf0qpd qword [r12+zmm16*1+127]{k3}
vgatherpf0qps dword [r15+zmm2*2]{k2}
vgatherpf0qps dword [rbx+zmm12*1]{k7}
vgatherpf1dpd qword [r8+ymm24*2]{k1}
vgatherpf1dpd qword [ymm22*8+128]{k7}
vgatherpf1dps dword [r14+zmm17*8]{k6}
vgatherpf1dps dword [rsp+zmm1*2+74565]{k3}
vgatherpf1qpd qword [rdi+zmm19*4+74565]{k6}
vgatherpf1qpd qword [rdx+zmm4*4+8]{k2}
vgatherpf1qps dword [r12+zmm17*1-8]{k1}
vgatherpf1qps dword [zmm22*1]{k6}
vgetexpsd xmm7{k7}, xmm12, qword [r9-8]
vgetexpsd xmm12{k4}{z}, xmm3, xmm0
vgetexpss xmm30{k5}{z}, xmm25, dword [r14+rax*1+74565]
vgetexpss xmm22, xmm28, xmm13
vgetmantpd xmm30, oword [r9+r11*1], 5
vgetmantpd xmm15{k6}, oword [r9+8], -128
vgetmantpd ymm26, ymm26, 127
vgetmantpd ymm22{k7}, ymm10, -1
vgetmantpd zmm22, zmm17, 1
vgetmantpd zmm29, zword [r15+8], 0
vgetmantps xmm31, oword [rcx+127], -128
vgetmantps xmm26{k3}, xmm18, 127
vgetmantps ymm11{k1}{z}, yword [rcx+r14*8], 127
vgetmantps ymm25, ymm13, 1
vgetmantps zmm4, zword [rsi], 127
vgetmantps zmm9, zmm19, 0
vgetmantsd xmm5, xmm4, xmm4, -1
vgetmantsd xmm15, xmm17, xmm10, -128
vgetmantss xmm21, xmm22, xmm15, 0
vgetmantss xmm23{k2}, xmm9, xmm26, 1
vmovddup xmm21{k2}, qword [r15+rdx*4+8]
vmovddup xmm22{k2}{z}, qword [rax+r13*1-128]
vmovddup ymm22{k3}, ymm15
vmovddup ymm9, ymm31
vmovddup zmm28{k6}, zmm22
vmovddup zmm30, zmm8
vmovhlps xmm19, xmm18, xmm20
vmovhlps xmm3, xmm20, xmm0
vmovhpd xmm18, xmm16, qword [r10+r13*4-8]
vmovhpd xmm14, xmm24, qword [127]
vmovhpd qword [-8], xmm7
vmovhpd qword [rsp+r13*2], xmm13
vmovhps xmm19, xmm17, qword [127]
vmovhps xmm6, xmm9, qword [r13+rbx*1+127]
vmovhps qword [r14+r15*4-128], xmm13
vmovhps qword [r15+r13*8+8], xmm7
vmovlhps xmm15, xmm19, xmm28
vmovlhps xmm8, xmm4, xmm1
vmovlpd xmm23, xmm6, qword [rcx+r11*2+127]
vmovlpd xmm19, xmm13, qword [rdx-8]
vmovlpd qword [rsp], xmm12
vmovlpd qword [8], xmm27
vmovlps xmm22, xmm2, qword [r14+rcx*1+128]
vmovlps xmm22, xmm1, qword [rsi+rbp*1]
vmovlps qword [r13], xmm7
vmovlps qword [rbx+74565], xmm12
vpbroadcastmb2q xmm12, k4
vpbroadcastmb2q xmm14, k6
vpbroadcastmb2q ymm19, k3
vpbroadcastmb2q ymm16, k7
vpbroadcastmb2q zmm21, k0
vpbroadcastmb2q zmm14, k3
vpbroadcastmw2d xmm27, k1
vpbroadcastmw2d xmm9, k0
vpbroadcastmw2d ymm4, k6
vpbroadcastmw2d ymm8, k4
vpbroadcastmw2d zmm5, k1
vpbroadcastmw2d zmm10, k2
vpmadd52huq xmm4{k6}{z}, xmm6, xmm11
vpmadd52huq xmm20, xmm5, oword [rax+74565]
vpmadd52huq ymm23{k6}, ymm19, yword [rdx+127]
vpmadd52huq ymm26, ymm31, ymm15
vpmadd52huq zmm4, zmm16, zmm14
vpmadd52huq zmm28{k4}{z}, zmm0, zword [127]
vpmadd52luq xmm5{k2}{z}, xmm21, xmm17
vpmadd52luq xmm14{k5}{z}, xmm15, xmm6
vpmadd52luq ymm30, ymm26, yword [r12+r12*1-128]
vpmadd52luq ymm2{k5}, ymm3, ymm15
vpmadd52luq zmm10, zmm9, zmm30
vpmadd52luq zmm12, zmm19, zword [rdx]
vpmultishiftqb xmm23, xmm2, oword [rsi+127]
vpmultishiftqb xmm2{k7}{z}, xmm1, xmm16
vpmultishiftqb ymm2, ymm21, yword [r8+127]
vpmultishiftqb ymm22{k1}{z}, ymm7, ymm7
vpmultishiftqb zmm16{k5}{z}, zmm17, zmm12
vpmultishiftqb zmm27{k5}, zmm22, zword [rbx+127]
vprolvd xmm2, xmm15, oword [rbp+r13*4-8]
vprolvd xmm16{k4}{z}, xmm13, xmm23
vprolvd ymm17, ymm23, ymm5
vprolvd ymm6, ymm7, yword [r8+r10*2+74565]
vprolvd zmm19, zmm6, zword [rdx+8]
vprolvd zmm13, zmm26, zword [rbp+r10*2-128]
vprolvq xmm29{k1}, xmm18, xmm1
vprolvq xmm12, xmm4, xmm11
vprolvq ymm5, ymm27, yword [rbx*2]
vprolvq ymm9, ymm29, yword [r8+r11*4]
vprolvq zmm13, zmm25, zword [rsi+r11*8]
vprolvq zmm23, zmm0, zmm11
vprorvd xmm19, xmm24, xmm14
vprorvd xmm24{k6}{z}, xmm7, oword [r15+r13*1+74565]
vprorvd ymm8{k2}{z}, ymm10, ymm6
vprorvd ymm20{k6}{z}, ymm24, ymm12
vprorvd zmm7, zmm16, zmm1
vprorvd zmm20{k5}{z}, zmm23, zmm14
vprorvq xmm29{k2}, xmm1, xmm1
vprorvq xmm16, xmm9, oword [rdx]
vprorvq ymm21, ymm27, yword [r12+r12*8+127]
vprorvq ymm30{k4}, ymm4, ymm22
vprorvq zmm27, zmm14, zword [r10*4-8]
vprorvq zmm29, zmm23, zmm26
vpscatterdd dword [r8+xmm12*4]{k5}, xmm15
vpscatterdd dword [rbp+xmm31*4-8]{k1}, xmm28
vpscatterdd dword [rsi+ymm9*2]{k2}, ymm26
vpscatterdd dword [rdi+ymm16*1+74565]{k5}, ymm9
vpscatterdd dword [rsp+zmm30*2+8]{k6}, zmm7
vpscatterdd dword [r9+zmm24*1]{k1}, zmm1
vpscatterdq qword [rdx+xmm24*8-128]{k5}, xmm19
vpscatterdq qword [r8+xmm11*4-8]{k5}, xmm21
vpscatterdq qword [xmm21*1+128]{k3}, ymm30
vpscatterdq qword [r9+xmm2*1+128]{k7}, ymm22
vpscatterdq qword [rcx+ymm28*4+8]{k1}, zmm9
vpscatterdq qword [r9+ymm17*8+8]{k4}, zmm21
vpscatterqd dword [rsp+xmm15*1+74565]{k7}, xmm2
vpscatterqd dword [r8+xmm11*1+128]{k1}, xmm7
vpscatterqd dword [rdx+ymm24*2]{k7}, xmm10
vpscatterqd dword [r11+ymm13*2]{k4}, xmm25
vpscatterqd dword [rbp+zmm19*4+74565]{k5}, ymm25
vpscatterqd dword [rsi+zmm8*8+128]{k5}, ymm18
vpscatterqq qword [r13+xmm1*8]{k5}, xmm12
vpscatterqq qword [r11+xmm27*8+128]{k2}, xmm17
vpscatterqq qword [rdi+ymm0*8]{k7}, ymm10
vpscatterqq qword [rsp+ymm14*8+128]{k1}, ymm29
vpscatterqq qword [r15+zmm28*8+128]{k6}, zmm28
vpscatterqq qword [r13+zmm11*1]{k5}, zmm9
vpslld xmm8, xmm6, oword [rbp+rbx*4-8]
vpslld xmm19, xmm25, oword [rdi]
vpslld ymm20{k2}, ymm9, oword [r14]
vpslld ymm3{k1}{z}, ymm22, xmm11
vpslld zmm10{k7}, zmm12, oword [rsp+r11*1]
vpslld zmm1{k1}{z}, zmm16, oword [r11]
vpslld xmm26{k5}{z}, oword [r14*2], 1
vpslld xmm22, xmm15, 127
vpslld ymm25{k5}{z}, ymm30, -1
vpslld ymm20, ymm10, 1
vpslld zmm3, zword [r15-8], -128
vpslld zmm31{k1}, zmm11, 127
vpsllq xmm0, xmm5, oword [r14+127]
vpsllq xmm23{k4}, xmm16, oword [rax+rsi*4+74565]
vpsllq ymm14{k1}{z}, ymm29, xmm18
vpsllq ymm10{k4}{z}, ymm8, xmm18
vpsllq zmm27, zmm13, xmm22
vpsllq zmm20{k7}, zmm0, oword [rbx+rbp*1+8]
vpsllq xmm10{k7}{z}, xmm5, 5
vpsllq xmm27{k1}{z}, oword [r8+r8*2+8], 5
vpsllq ymm14{k7}, ymm2, -1
vpsllq ymm3{k7}, ymm14, 0
vpsllq zmm28, zword [r12+rcx*4-128], 5
vpsllq zmm30, zmm21, 127
vpsllw xmm21{k3}{z}, xmm0, xmm26
vpsllw xmm31{k5}{z}, xmm21, oword [rdi-8]
vpsllw ymm15, ymm26, oword [r14+8]
vpsllw ymm3, ymm26, oword [r12+r8*2-8]
vpsllw zmm23, zmm0, oword [rsi+8]
vpsllw zmm7{k7}{z}, zmm31, xmm25
vpsllw xmm15{k7}, xmm2, 0
vpsllw xmm2, xmm10, 5
vpsllw ymm10, ymm5, 127
vpsllw ymm6{k1}{z}, ymm10, 127
vpsllw zmm24, zmm10, 0
vpsllw zmm23, zmm22, -128
vpsrad xmm13{k6}{z}, xmm6, xmm12
vpsrad xmm16{k5}, xmm6, xmm6
vpsrad ymm7, ymm13, xmm29
vpsrad ymm25{k3}, ymm19, xmm4
vpsrad zmm24{k7}{z}, zmm1, xmm21
vpsrad zmm25, zmm17, oword [r15-8]
vpsrad xmm5{k7}, oword [r8+74565], 127
vpsrad xmm12, oword [rbx+127], 5
vpsrad ymm2, yword [rax*1], 127
vpsrad ymm1, yword [r8+74565], -128
vpsrad zmm8, zword [rsi], 1
vpsrad zmm23{k4}, zmm18, 1
vpsraw xmm9{k7}{z}, xmm28, xmm4
vpsraw xmm13{k6}, xmm0, xmm2
vpsraw ymm18{k6}{z}, ymm30, xmm17
vpsraw ymm25, ymm30, oword [r13+74565]
vpsraw zmm8{k1}{z}, zmm15, xmm9
vpsraw zmm16, zmm25, oword [r14+8]
vpsraw xmm20{k1}, xmm3, 5
vpsraw xmm6{k1}{z}, xmm18, -1
vpsraw ymm22, ymm31, -128
vpsraw ymm10{k3}{z}, yword [rbp+r12*1-8], 1
vpsraw zmm3{k1}{z}, zmm23, 0
vpsraw zmm21{k6}{z}, zmm26, -128
vpsrld xmm5{k4}, xmm20, xmm12
vpsrld xmm4{k1}, xmm13, xmm9
vpsrld ymm4{k3}, ymm4, oword [r11]
vpsrld ymm30{k7}, ymm30, oword [rsp+rbx*4+8]
vpsrld zmm16{k1}, zmm13, xmm18
vpsrld zmm6{k5}{z}, zmm2, oword [r8+74565]
vpsrld xmm13, xmm20, 127
vpsrld xmm20{k1}{z}, oword [r10+rax*1], 127
vpsrld ymm28{k5}, yword [4096], 0
vpsrld ymm28, ymm10, 127
vpsrld zmm6, zword [r13+8], 127
vpsrld zmm23{k1}, zmm27, -128
vpsrlq xmm21, xmm4, oword [r11]
vpsrlq xmm28{k4}, xmm21, oword [rdx+rdx*8-8]
vpsrlq ymm15, ymm2, oword [127]
vpsrlq ymm11{k5}, ymm11, xmm20
vpsrlq zmm0, zmm4, xmm13
vpsrlq zmm7{k2}{z}, zmm16, xmm2
vpsrlq xmm12{k2}{z}, xmm28, -128
vpsrlq xmm25{k6}{z}, oword [r12+r14*1+128], 127
vpsrlq ymm17{k6}{z}, ymm21, 127
vpsrlq ymm21, ymm10, 0
vpsrlq zmm3, zword [rdi+r15*8-8], 0
vpsrlq zmm18, zmm16, 127
vpsrlw xmm2{k4}, xmm28, oword [rsi]
vpsrlw xmm12{k1}, xmm27, xmm27
vpsrlw ymm16, ymm0, xmm30
vpsrlw ymm12{k6}{z}, ymm1, oword [r11+rax*8+127]
vpsrlw zmm19, zmm18, xmm28
vpsrlw zmm31{k1}{z}, zmm12, xmm13
vpsrlw xmm11{k4}, xmm30, -1
vpsrlw xmm19, oword [r14+r11*8], 5
vpsrlw ymm6, ymm0, 0
vpsrlw ymm23, yword [rdx], -128
vpsrlw zmm4{k5}, zword [r14+128], -128
vpsrlw zmm15, zmm5, 127
vrangepd xmm26, xmm19, oword [r10+rsi*1], -1
vrangepd xmm12{k7}, xmm2, xmm23, -128
vrangepd ymm14{k7}, ymm29, yword [rax+r11*8+74565], -128
vrangepd ymm22, ymm31, ymm12, -1
vrangepd zmm26{k5}, zmm29, zword [r8-8], 127
vrangepd zmm3{k2}{z}, zmm8, zmm28, -128
vrangeps xmm0{k2}{z}, xmm3, oword [rsi+r9*4+8], 127
vrangeps xmm9, xmm4, xmm30, -128
vrangeps ymm26, ymm3, yword [rsi+r12*2+128], 0
vrangeps ymm1{k6}, ymm9, yword [rsp-8], -128
vrangeps zmm16{k6}{z}, zmm9, zmm27, 5
vrangeps zmm5{k2}{z}, zmm19, zmm5, 1
vrangesd xmm14, xmm20, qword [rdx], 1
vrangesd xmm6{k3}{z}, xmm22, xmm29, -1
vrangess xmm12, xmm2, dword [rsi+rdi*2+8], -128
vrangess xmm24, xmm19, dword [rsi+rcx*2+127], 5
vrcp28pd zmm11, zword [rdi+r12*2]
vrcp28pd zmm29{k3}{z}, zmm3
vrcp28ps zmm5{k5}{z}, zmm23
vrcp28ps zmm0, zmm10
vrcp28sd xmm15, xmm5, xmm21
vrcp28sd xmm7{k6}{z}, xmm19, xmm1
vrcp28ss xmm11, xmm14, xmm5
vrcp28ss xmm29{k7}, xmm14, xmm7
vreducepd xmm6, xmm0, 1
vreducepd xmm26{k6}, xmm30, -128
vreducepd ymm14{k2}{z}, ymm8, -1
vreducepd ymm12, ymm3, -128
vreducepd zmm24{k3}{z}, zword [r10*1+74565], -128
vreducepd zmm5, zmm2, -128
vreduceps xmm1{k4}{z}, oword [-128], 0
vreduceps xmm10, xmm17, -1
vreduceps ymm10{k7}, ymm17, 0
vreduceps ymm29, ymm11, 0
vreduceps zmm23{k6}{z}, zword [r13*2+74565], 1
vreduceps zmm22{k3}{z}, zmm17, -1
vreducesd xmm16{k1}, xmm9, xmm7, 127
vreducesd xmm17, xmm4, xmm28, 0
vreducess xmm29, xmm21, xmm9, -1
vreducess xmm4, xmm15, dword [r12+128], -128
vrsqrt28pd zmm2, zword [rdi+r11*4+74565]
vrsqrt28pd zmm27{k3}{z}, zword [rax*4-128]
vrsqrt28ps zmm11, zmm5
vrsqrt28ps zmm31, zmm22
vrsqrt28sd xmm18, xmm22, xmm14
vrsqrt28sd xmm19, xmm3, qword [r11+r13*2+8]
vrsqrt28ss xmm11{k1}{z}, xmm31, dword [rbx+rdi*4-128]
vrsqrt28ss xmm30{k4}{z}, xmm3, xmm29
vscalefsd xmm19, xmm22, qword [rsi+8]
vscalefsd xmm8, xmm2, qword [r13+rbx*1+128]
vscalefss xmm2, xmm4, dword [rdx-128]
vscalefss xmm17, xmm30, xmm18
vscatterdpd qword [r10+xmm25*2+128]{k3}, xmm5
vscatterdpd qword [r9+xmm7*2+74565]{k6}, xmm22
vscatterdpd qword [rax+xmm10*2+74565]{k2}, ymm27
vscatterdpd qword [rdx+xmm15*2+128]{k7}, ymm14
vscatterdpd qword [r14+ymm29*8+128]{k2}, zmm2
vscatterdpd qword [rsp+ymm5*2-128]{k4}, zmm8
vscatterdps dword [r9+xmm15*4]{k7}, xmm11
vscatterdps dword [r12+xmm4*4]{k2}, xmm21
vscatterdps dword [r11+ymm1*8+128]{k5}, ymm20
vscatterdps dword [ymm5*1]{k3}, ymm19
vscatterdps dword [rbp+zmm15*1+127]{k7}, zmm27
vscatterdps dword [r9+zmm4*4-128]{k2}, zmm27
vscatterpf0dpd qword [rdx+ymm12*4+74565]{k4}
vscatterpf0dpd qword [rbp+ymm0*4+8]{k1}
vscatterpf0dps dword [r8+zmm27*8]{k1}
vscatterpf0dps dword [rcx+zmm15*2]{k5}
vscatterpf0qpd qword [rbx+zmm5*2-128]{k3}
vscatterpf0qpd qword [rdi+zmm14*4-128]{k7}
vscatterpf0qps dword [rbp+zmm15*4-128]{k7}
vscatterpf0qps dword [r11+zmm6*2+8]{k4}
vscatterpf1dpd qword [rbp+ymm12*4+128]{k3}
vscatterpf1dpd qword [r8+ymm17*2-128]{k4}
vscatterpf1dps dword [r8+zmm15*2-128]{k4}
vscatterpf1dps dword [r8+zmm19*1-128]{k6}
vscatterpf1qpd qword [rdx+zmm31*1+74565]{k5}
vscatterpf1qpd qword [rdx+zmm0*4]{k6}
vscatterpf1qps dword [r11+zmm7*8+128]{k6}
vscatterpf1qps dword [r9+zmm2*8]{k7}
vscatterqpd qword [r8+xmm16*4+8]{k6}, xmm14
vscatterqpd qword [r11+xmm15*8+74565]{k1}, xmm10
vscatterqpd qword [r13+ymm23*2+74565]{k1}, ymm28
vscatterqpd qword [ymm4*1]{k4}, ymm31
vscatterqpd qword [r14+zmm8*1]{k1}, zmm29
vscatterqpd qword [rdi+zmm10*4+74565]{k4}, zmm19
vscatterqps dword [rbx+xmm29*1+127]{k6}, xmm28
vscatterqps dword [r15+xmm25*1+127]{k3}, xmm31
vscatterqps dword [ymm9*8+8]{k5}, xmm23
vscatterqps dword [rax+ymm7*8+74565]{k4}, xmm6
vscatterqps dword [rcx+zmm14*2+8]{k5}, ymm2
vscatterqps dword [r9+zmm26*1+128]{k1}, ymm0
vpcompressb oword [rbp+128], xmm15
vpcompressb oword [rcx-128], xmm30
vpcompressb yword [rbx+rdx*1+74565], ymm23
vpcompressb yword [r9+128], ymm18
vpcompressb zword [r11+rsi*2-8], zmm0
vpcompressb zword [rdx*2-128], zmm28
vpcompressb xmm7, xmm8
vpcompressb xmm8, xmm27
vpcompressb ymm30, ymm9
vpcompressb ymm25, ymm15
vpcompressb zmm13, zmm28
vpcompressb zmm16, zmm15
vpcompressw oword [r13+rcx*2], xmm9
vpcompressw oword [rcx+127], xmm8
vpcompressw yword [rsp+rbx*8], ymm2
vpcompressw yword [r14], ymm2
vpcompressw zword [r11+74565], zmm13
vpcompressw zword [rdx+8], zmm26
vpcompressw xmm15, xmm14
vpcompressw xmm12{k5}, xmm0
vpcompressw ymm31, ymm7
vpcompressw ymm4, ymm27
vpcompressw zmm1, zmm14
vpcompressw zmm29, zmm29
vpexpandb xmm17, oword [rsp+rax*8]
vpexpandb xmm8, xmm6
vpexpandb ymm25{k4}, ymm5
vpexpandb ymm21, ymm2
vpexpandb zmm6{k6}, zmm2
vpexpandb zmm4, zword [r12+74565]
vpexpandw xmm16{k2}, xmm14
vpexpandw xmm29, xmm31
vpexpandw ymm10, ymm13
vpexpandw ymm6, ymm22
vpexpandw zmm27{k3}{z}, zmm8
vpexpandw zmm2{k7}, zword [r13+rax*8]
vpshldw xmm29, xmm17, oword [rax+rbp*4-8], 127
vpshldw xmm23, xmm23, oword [rax+r15*4+127], -1
vpshldw ymm27{k1}, ymm11, yword [74565], 5
vpshldw ymm30{k7}, ymm7, yword [rcx], 1
vpshldw zmm25{k7}, zmm30, zmm27, 1
vpshldw zmm20, zmm30, zword [r11+r11*1+128], 127
vpshldd xmm28, xmm21, oword [r12+8], 1
vpshldd xmm29, xmm5, oword [r10*4-128], -1
vpshldd ymm27, ymm3, yword [rcx], -128
vpshldd ymm23, ymm3, ymm19, 0
vpshldd zmm4{k2}{z}, zmm23, zmm1, 1
vpshldd zmm22{k4}, zmm27, zmm25, -1
vpshldq xmm28, xmm30, xmm10, 1
vpshldq xmm29{k7}, xmm11, xmm19, 0
vpshldq ymm13{k7}{z}, ymm15, yword [rdx+r11*8+128], 1
vpshldq ymm2{k3}{z}, ymm24, ymm8, -128
vpshldq zmm11{k7}, zmm26, zmm14, 127
vpshldq zmm17{k4}{z}, zmm5, zmm6, 1
vpshldvw xmm17, xmm5, oword [rsi+127]
vpshldvw xmm4{k2}{z}, xmm9, xmm26
vpshldvw ymm4, ymm2, ymm21
vpshldvw ymm2, ymm9, yword [rsi+r8*4]
vpshldvw zmm9{k6}, zmm25, zmm17
vpshldvw zmm24, zmm16, zword [r12+r10*4+8]
vpshldvd xmm7, xmm21, xmm14
vpshldvd xmm16, xmm6, xmm18
vpshldvd ymm6{k2}{z}, ymm3, yword [rcx+8]
vpshldvd ymm22{k5}, ymm21, ymm13
vpshldvd zmm11, zmm10, zword [rdx+r12*8+8]
vpshldvd zmm6{k5}{z}, zmm5, zmm9
vpshldvq xmm6, xmm27, xmm23
vpshldvq xmm0{k6}{z}, xmm24, xmm24
vpshldvq ymm26, ymm3, yword [rsp+128]
vpshldvq ymm1, ymm14, ymm18
vpshldvq zmm24{k2}, zmm8, zword [rdi+8]
vpshldvq zmm0{k5}{z}, zmm17, zword [r8+127]
vpshrdw xmm8, xmm2, oword [r13], 127
vpshrdw xmm18{k6}{z}, xmm4, oword [rbp+8], -1
vpshrdw ymm2{k4}, ymm19, ymm9, 5
vpshrdw ymm8, ymm26, yword [r13+rbp*4+8], 0
vpshrdw zmm23{k7}, zmm26, zword [rax-128], -1
vpshrdw zmm7{k2}{z}, zmm4, zmm26, 1
vpshrdd xmm15{k6}, xmm20, oword [rcx+rcx*2+8], 1
vpshrdd xmm3, xmm22, oword [r12+r10*4], 5
vpshrdd ymm2{k1}{z}, ymm1, yword [rax+r13*8+74565], -1
vpshrdd ymm31{k5}{z}, ymm21, yword [rsp+rdx*2], 0
vpshrdd zmm28{k1}, zmm8, zmm16, 0
vpshrdd zmm22{k2}, zmm9, zword [rbp+128], -128
vpshrdq xmm23, xmm8, oword [r14+r9*8+127], 5
vpshrdq xmm30{k1}{z}, xmm10, xmm2, -1
vpshrdq ymm11{k7}{z}, ymm31, yword [r15+r12*1-128], 0
vpshrdq ymm19, ymm26, yword [rdi+128], -128
vpshrdq zmm9{k4}, zmm14, zmm1, -128
vpshrdq zmm5{k6}, zmm29, zmm23, 5
vpshrdvw xmm9, xmm24, oword [rax]
vpshrdvw xmm30, xmm8, xmm24
vpshrdvw ymm18{k6}{z}, ymm21, ymm3
vpshrdvw ymm25{k4}{z}, ymm13, ymm16
vpshrdvw zmm24, zmm28, zword [rbp*1]
vpshrdvw zmm8{k2}, zmm18, zword [r13]
vpshrdvd xmm16, xmm2, oword [rax+r14*4]
vpshrdvd xmm10, xmm13, xmm21
vpshrdvd ymm31{k4}, ymm19, yword [r8-8]
vpshrdvd ymm14, ymm25, yword [r8+8]
vpshrdvd zmm19{k7}, zmm8, zword [4096]
vpshrdvd zmm19, zmm20, zmm2
vpshrdvq xmm0{k6}{z}, xmm24, xmm18
vpshrdvq xmm18{k3}, xmm29, oword [r13+128]
vpshrdvq ymm14, ymm24, ymm16
vpshrdvq ymm9{k7}{z}, ymm8, ymm22
vpshrdvq zmm3, zmm20, zmm21
vpshrdvq zmm18, zmm0, zword [rsi+128]
vpopcntb xmm15{k4}{z}, xmm28
vpopcntb xmm1, xmm0
vpopcntb ymm0{k1}, yword [r8+74565]
vpopcntb ymm15{k2}{z}, yword [r11+74565]
vpopcntb zmm0{k2}{z}, zword [r9+127]
vpopcntb zmm15, zmm13
vpopcntw xmm5, oword [r9+128]
vpopcntw xmm28, xmm8
vpopcntw ymm4{k5}{z}, ymm23
vpopcntw ymm1, ymm2
vpopcntw zmm29, zword [rcx-128]
vpopcntw zmm10{k1}, zword [rsp+rcx*4+8]
vpopcntd xmm30{k1}, xmm2
vpopcntd xmm4{k4}, oword [rbx+127]
vpopcntd ymm20, yword [r8+74565]
vpopcntd ymm20, yword [r9*8-128]
vpopcntd zmm1, zmm27
vpopcntd zmm8{k3}, zword [r8-8]
vpopcntq xmm22, oword [rdi+rdi*4+74565]
vpopcntq xmm19{k2}{z}, oword [rsp]
vpopcntq ymm5{k7}{z}, yword [8]
vpopcntq ymm9, ymm24
vpopcntq zmm9, zmm6
vpopcntq zmm18{k5}{z}, zword [rcx]
vpshufbitqmb k6{k6}, xmm14, xmm22
vpshufbitqmb k6, xmm8, xmm31
vpshufbitqmb k4, ymm2, yword [r11+128]
vpshufbitqmb k3, ymm0, yword [r11+rcx*2+128]
vpshufbitqmb k5, zmm14, zword [rbp+8]
vpshufbitqmb k4, zmm31, zmm23
vcvtne2ps2bf16 xmm7{k4}, xmm25, xmm6
vcvtne2ps2bf16 xmm3, xmm4, oword [r15]
vcvtne2ps2bf16 ymm22{k3}{z}, ymm0, ymm24
vcvtne2ps2bf16 ymm18, ymm24, ymm27
vcvtne2ps2bf16 zmm6, zmm16, zmm25
vcvtne2ps2bf16 zmm0{k4}{z}, zmm10, zmm2
vdpbf16ps xmm21{k6}{z}, xmm14, oword [r14+128]
vdpbf16ps xmm28, xmm26, oword [rbp-128]
vdpbf16ps ymm25, ymm19, ymm4
vp2intersectd k6, xmm11, oword [127]
vp2intersectd k3, xmm21, xmm7
vp2intersectd k2, ymm17, ymm3
vp2intersectd k4, ymm17, ymm0
vp2intersectd k6, zmm24, zmm15
ldtilecfg zword [4096]
ldtilecfg zword [r11]
sttilecfg zword [r14+rbx*2+127]
sttilecfg zword [r15+r9*8+127]
tdpbf16ps tmm7, tmm2, tmm5
tdpbssd tmm4, tmm7, tmm0
tdpbsud tmm3, tmm1, tmm6
tdpbsud tmm6, tmm1, tmm7
tdpbusd tmm2, tmm0, tmm6
tdpbuud tmm6, tmm0, tmm3
tileloadd tmm7, [rsi+r9*4+8]
tileloadd tmm7, [rdx-8]
tileloaddt1 tmm5, [r15-8]
tileloaddt1 tmm5, [rax-8]
tilerelease
tilerelease
tilestored [rdi+74565], tmm3
tilestored [r11+8], tmm5
tilezero tmm6
tilezero tmm7
vaddph xmm13{k5}{z}, xmm29, xmm25
vaddph xmm20, xmm17, xmm27
vaddph ymm1{k5}, ymm25, ymm1
vaddph ymm17, ymm24, ymm3
vaddph zmm20{k7}, zmm28, zmm0
vaddph zmm30{k1}{z}, zmm30, zmm0
vaddsh xmm29, xmm27, xmm25
vaddsh xmm25, xmm6, word [rdx]
vcmpph k0{k6}, xmm12, [rbx+rbx*2+127], 127
vcmpph k5, xmm1, [r9+rdx*1], -128
vcmpph k2, ymm7, ymm21, -1
vcmpph k3{k1}, ymm24, ymm4, -1
vcmpph k2{k6}, zmm14, [rax+r11*1+8], -128
vcmpph k1, zmm15, [r15+rsi*4+8], 127
vcmpsh k1, xmm12, word [r10], 0
vcmpsh k4, xmm29, xmm19, -128
vcomish xmm15, word [rbx+rsi*8-128]
vcomish xmm11, word [4096]
vcvtdq2ph xmm21{k6}{z}, oword [rdi+r14*4+127]
vcvtdq2ph xmm10, oword [r15+8]
vcvtpd2ph xmm10{k7}{z}, oword [r12+r9*2+8]
vcvtpd2ph xmm11{k3}, xmm21
vcvtph2dq xmm7, qword [r14]
vcvtph2dq xmm4, qword [rdi-128]
vcvtph2dq ymm28, oword [rax+rdi*8+128]
vcvtph2dq ymm5{k5}{z}, oword [r12*1+127]
vcvtph2dq zmm26, yword [-128]
vcvtph2dq zmm18{k5}, yword [rsp+rdx*4]
vcvtph2pd xmm16{k4}{z}, dword [r12+r13*2+8]
vcvtph2pd xmm10{k5}{z}, xmm30
vcvtph2pd ymm4{k2}{z}, qword [r11]
vcvtph2pd ymm16{k7}, xmm16
vcvtph2pd zmm19, oword [-8]
vcvtph2pd zmm21, xmm0
vcvtph2psx xmm7{k5}{z}, qword [r11-128]
vcvtph2psx xmm31{k7}{z}, xmm23
vcvtph2psx ymm21, xmm13
vcvtph2psx ymm20, oword [r14+rcx*8+127]
vcvtph2psx zmm26, ymm10
vcvtph2psx zmm10{k7}{z}, ymm4
vcvtph2qq xmm22{k7}, xmm9
vcvtph2qq xmm18, xmm9
vcvtph2qq ymm13{k3}{z}, qword [rsi+r9*1+74565]
vcvtph2qq ymm5{k2}{z}, xmm17
vcvtph2qq zmm30{k2}{z}, oword [r14+127]
vcvtph2qq zmm26{k1}, xmm7
vcvtph2udq xmm5, xmm2
vcvtph2uqq xmm8, xmm26
vcvtph2uqq xmm13{k6}{z}, xmm16
vcvtph2uqq ymm0, qword [r15]
vcvtph2uqq ymm23{k3}, xmm21
vcvtph2uqq zmm23{k6}{z}, oword [r13+127]
vcvtph2uqq zmm6{k4}{z}, oword [r10]
vcvtph2uw xmm19{k2}, oword [rax+8]
vcvtph2uw xmm2, oword [rbx-8]
vcvtph2uw ymm23, ymm16
vcvtph2uw ymm5{k4}, ymm17
vcvtph2uw zmm7{k6}, zmm11
vcvtph2uw zmm4{k4}, zmm26
vcvtph2w xmm23{k3}, xmm0
vcvtph2w xmm11, xmm18
vcvtph2w ymm18, yword [4096]
vcvtph2w ymm11, yword [r10+r15*8]
vcvtph2w zmm24, zmm6
vcvtph2w zmm22{k4}{z}, zword [rsi+r14*2-128]
vcvtps2ph xmm3, xmm9, 0
vcvtps2ph xmm13, xmm5, 0
vcvtps2ph oword [r11+128], ymm11, -1
vcvtps2ph oword [rdi], ymm7, 127
vcvtps2ph xmm26{k4}, xmm23, 0
vcvtps2ph xmm12{k2}{z}, xmm12, -1
vcvtps2ph qword [rsi+128], xmm1, 1
vcvtps2ph qword [r9-128], xmm20, 127
vcvtps2ph xmm27{k2}, ymm31, 127
vcvtps2ph xmm31{k2}{z}, ymm29, -1
vcvtps2ph oword [r13+74565], ymm17, 5
vcvtps2ph oword [r12+8], ymm5, 5
vcvtps2ph ymm5, zmm9, 1
vcvtps2ph ymm17{k6}, zmm5, 0
vcvtps2ph yword [rdi+128], zmm4, 0
vcvtps2ph yword [r12-128], zmm28, 0
vcvtqq2ph xmm13{k3}{z}, oword [rax]
vcvtqq2ph xmm30{k5}, oword [rsi+rsi*8+127]
vcvtsd2sh xmm2, xmm28, xmm29
vcvtsd2sh xmm14{k2}, xmm23, qword [r13+rbx*4+128]
vcvtsh2sd xmm30, xmm20, xmm17
vcvtsh2sd xmm17, xmm18, xmm11
vcvtsh2si r10d, word [r15+128]
vcvtsh2si r8d, word [rbp+r10*4-128]
vcvtsh2si r15, word [rsp+127]
vcvtsh2si r9, word [rsi+r15*8-8]
vcvtsh2ss xmm20, xmm3, word [4096]
vcvtsh2ss xmm31{k3}{z}, xmm9, xmm13
vcvtsh2usi ecx, word [r15+r13*2-128]
vcvtsh2usi esi, word [rdi+74565]
vcvtsh2usi r15, word [r8+127]
vcvtsh2usi rdx, word [r8*8+128]
vcvtsi2sh xmm25, xmm25, dword [rbx+r12*2+128]
vcvtsi2sh xmm9, xmm28, r14d
vcvtsi2sh xmm10, xmm15, r12
vcvtsi2sh xmm7, xmm7, qword [rbx+rax*4]
vcvtss2sh xmm29, xmm4, xmm24
vcvtss2sh xmm2, xmm20, dword [r11+r13*2+74565]
vcvttph2dq xmm16, qword [rax+rdx*8+128]
vcvttph2dq xmm23, xmm30
vcvttph2dq ymm4, oword [r11+r12*2+8]
vcvttph2dq ymm1, oword [r13+rbx*8+8]
vcvttph2dq zmm18, ymm27
vcvttph2dq zmm19{k5}, ymm14
vcvttph2qq xmm29{k1}{z}, dword [r11+rbp*4+74565]
vcvttph2qq xmm9{k1}{z}, dword [rdi+127]
vcvttph2qq ymm31, xmm8
vcvttph2qq ymm8, qword [74565]
vcvttph2qq zmm30{k2}, oword [rdi+r11*2]
vcvttph2qq zmm6, oword [rbp+r13*1+74565]
vcvttph2udq xmm10, qword [rdx+rdx*2+74565]
vcvttph2udq xmm6{k4}, xmm20
vcvttph2udq ymm22, xmm19
vcvttph2udq ymm17{k4}{z}, xmm23
vcvttph2udq zmm17, ymm10
vcvttph2udq zmm11, ymm25
vcvttph2uqq xmm27, dword [r10+74565]
vcvttph2uqq xmm6{k2}{z}, dword [rax*1+128]
vcvttph2uqq ymm7{k3}{z}, xmm31
vcvttph2uqq ymm26{k4}, qword [r13-8]
vcvttph2uqq zmm31, xmm6
vcvttph2uqq zmm25, oword [rsi*2-128]
vcvttph2uw xmm31, oword [r8]
vcvttph2uw xmm17{k1}{z}, xmm5
vcvttph2uw ymm14{k6}, yword [rsp-128]
vcvttph2uw ymm17{k7}, ymm30
vcvttph2uw zmm6, zword [rsp+r13*1+127]
vcvttph2uw zmm9{k1}{z}, zword [r9+rbx*4+74565]
vcvttph2w xmm24, xmm25
vcvttph2w xmm16, xmm5
vcvttph2w ymm12{k6}, ymm1
vcvttph2w ymm4{k1}, yword [r15+r9*4+127]
vcvttph2w zmm12, zword [127]
vcvttph2w zmm27, zword [r15-8]
vcvttsh2si r9d, word [rbp+74565]
vcvttsh2si r12d, xmm25
vcvttsh2si r15, xmm10
vcvttsh2si r13, word [r13+8]
vcvttsh2usi ecx, word [127]
vcvttsh2usi r10d, xmm11
vcvttsh2usi rsi, word [rcx]
vcvttsh2usi rbp, xmm24
vcvtudq2ph xmm4, oword [rax+r12*2+128]
vcvtudq2ph xmm21{k7}, oword [4096]
vcvtuqq2ph xmm0, oword [rbx+8]
vcvtuqq2ph xmm16, xmm31
vcvtusi2sh xmm18, xmm4, eax
vcvtusi2sh xmm7, xmm14, dword [rdi*1]
vcvtusi2ss xmm2, xmm31, r15
vcvtusi2ss xmm24, xmm3, qword [r10+r12*4-8]
vcvtuw2ph xmm0, xmm7
vcvtuw2ph xmm31, oword [rsi+rax*8+74565]
vcvtuw2ph ymm12, yword [r15*8]
vcvtuw2ph ymm31{k3}, yword [r13*8+8]
vcvtuw2ph zmm14, zmm0
vcvtuw2ph zmm6, zword [rcx+r11*1-8]
vcvtw2ph xmm15, xmm12
vcvtw2ph xmm12{k5}, oword [rbx+128]
vcvtw2ph ymm16, yword [r11]
vcvtw2ph ymm25, ymm10
vcvtw2ph zmm18, zword [rbx+rdx*2+127]
vcvtw2ph zmm5, zword [rdi+127]
vdivph xmm4{k7}{z}, xmm11, xmm19
vdivph xmm30, xmm13, oword [rbp+74565]
vdivph ymm23, ymm29, yword [r15+r9*2-8]
vdivph ymm7{k4}, ymm22, yword [rdx+r12*8]
vdivph zmm20, zmm10, zword [r15+8]
vdivph zmm24, zmm6, zmm28
vdivsh xmm18{k2}{z}, xmm1, word [r12]
vdivsh xmm23{k4}{z}, xmm5, word [r9]
vfcmaddcph xmm31, xmm1, oword [rbp-128]
vfcmaddcph xmm2, xmm8, xmm30
vfcmaddcph ymm6, ymm0, ymm0
vfcmaddcph zmm6, zmm15, zmm17
vfcmaddcph zmm0{k6}, zmm8, zword [r8+r8*8+8]
vfmaddcph xmm12{k7}{z}, xmm14, oword [rdx]
vfmaddcph xmm0, xmm26, xmm16
vfmaddcph ymm18, ymm6, yword [rax+8]
vfmaddcph zmm20{k5}{z}, zmm29, zmm9
vfmaddcph zmm6, zmm7, zword [r12+r15*8]
vfcmaddcsh xmm27{k1}{z}, xmm8, xmm25
vfcmaddcsh xmm0, xmm20, xmm6
vfmaddcsh xmm11, xmm30, xmm12
vfmaddcsh xmm17, xmm4, dword [r9-128]
vfcmulcsh xmm29, xmm21, xmm17
vfcmulcsh xmm26, xmm31, xmm31
vfmulcsh xmm16{k7}, xmm5, xmm0
vfmulcsh xmm8{k7}{z}, xmm14, dword [r9-8]
vfmaddsub132ph xmm23, xmm25, oword [rcx]
vfmaddsub132ph xmm27, xmm26, oword [r10+r15*8-128]
vfmaddsub132ph ymm5{k2}, ymm2, ymm5
vfmaddsub132ph ymm26{k2}, ymm26, yword [r10]
vfmaddsub132ph zmm25, zmm0, zmm31
vfmaddsub132ph zmm18, zmm31, zword [127]
vfmaddsub213ph xmm15, xmm31, oword [rsp+rax*8]
vfmaddsub213ph xmm0, xmm24, xmm17
vfmaddsub213ph ymm23{k3}{z}, ymm4, yword [rsp+128]
vfmaddsub213ph ymm6, ymm5, ymm22
vfmaddsub213ph zmm12{k6}, zmm13, zword [r13+128]
vfmaddsub213ph zmm13{k7}{z}, zmm15, zmm22
vfmaddsub231ph xmm3, xmm14, xmm30
vfmaddsub231ph xmm14{k2}{z}, xmm20, xmm14
vfmaddsub231ph ymm27, ymm26, ymm3
vfmaddsub231ph ymm28, ymm15, ymm28
vfmaddsub231ph zmm8{k4}{z}, zmm21, zword [rdi+74565]
vfmaddsub231ph zmm5{k3}{z}, zmm29, zmm25
vfmsubadd132ph xmm22{k6}{z}, xmm5, xmm26
vfmsubadd132ph xmm21{k7}{z}, xmm0, oword [r14+128]
vfmsubadd132ph ymm16{k5}{z}, ymm11, ymm22
vfmsubadd132ph ymm18{k4}{z}, ymm15, ymm2
vfmsubadd132ph zmm17{k2}{z}, zmm9, zword [r9+rbx*4+8]
vfmsubadd132ph zmm6{k6}{z}, zmm17, zmm24
vfmsubadd213ph xmm23{k3}, xmm3, oword [rbp]
vfmsubadd213ph xmm12{k6}, xmm12, xmm19
vfmsubadd213ph ymm18{k6}{z}, ymm9, ymm24
vfmsubadd213ph ymm9{k5}, ymm3, ymm11
vfmsubadd213ph zmm30, zmm23, zmm25
vfmsubadd213ph zmm29, zmm16, zword [r13+r11*4-128]
vfmsubadd231ph xmm8{k1}, xmm17, oword [r14-128]
vfmsubadd231ph xmm16, xmm7, xmm7
vfmsubadd231ph ymm31{k6}, ymm1, yword [r9]
vfmsubadd231ph ymm23{k7}{z}, ymm12, yword [r14+r13*8]
vfmsubadd231ph zmm18{k1}, zmm3, zword [r11+rdi*1]
vfmsubadd231ph zmm6, zmm12, zmm1
vfmadd132ph xmm27{k4}{z}, xmm0, xmm6
vfmadd132ph xmm7{k5}, xmm2, oword [r11+rbx*4+8]
vfmadd132ph ymm29{k3}, ymm17, ymm3
vfmadd132ph ymm31{k4}{z}, ymm26, ymm31
vfmadd132ph zmm16{k1}{z}, zmm26, zword [rsp+r8*1-128]
vfmadd132ph zmm21, zmm20, zmm16
vfmadd213ph xmm0, xmm2, oword [-128]
vfmadd213ph xmm1, xmm16, oword [rsi]
vfmadd213ph ymm9{k7}{z}, ymm13, yword [r10]
vfmadd213ph ymm13, ymm1, yword [rsi*1+8]
vfmadd213ph zmm8{k7}{z}, zmm21, zmm22
vfmadd213ph zmm25, zmm11, zmm22
vfmadd231ph xmm30, xmm16, xmm17
vfmadd231ph xmm2{k5}{z}, xmm14, oword [rbp]
vfmadd231ph ymm22, ymm5, ymm3
vfmadd231ph ymm23, ymm23, ymm14
vfmadd231ph zmm8, zmm15, zword [4096]
vfmadd231ph zmm26, zmm4, zword [rbp+rbx*2+128]
vfmsub132ph xmm20, xmm28, oword [r14+r14*4+127]
vfmsub132ph xmm20, xmm5, xmm11
vfmsub132ph ymm14{k1}{z}, ymm0, yword [rsp+rdx*8+127]
vfmsub132ph ymm14, ymm5, ymm23
vfmsub132ph zmm10, zmm14, zmm3
vfmsub132ph zmm23, zmm23, zmm5
vfmsub213ph xmm16, xmm20, oword [rdx*8]
vfmsub213ph xmm4, xmm4, oword [r15+128]
vfmsub213ph ymm10, ymm9, yword [rax+r11*2+128]
vfmsub213ph ymm29{k7}, ymm5, yword [r11*2]
vfmsub213ph zmm4, zmm14, zmm12
vfmsub213ph zmm8{k5}, zmm31, zword [rsp+128]
vfmsub231ph xmm20, xmm26, oword [rdi+rcx*1]
vfmsub231ph xmm26, xmm25, xmm28
vfmsub231ph ymm25, ymm21, yword [rdx-8]
vfmsub231ph ymm7{k1}{z}, ymm30, ymm15
vfmsub231ph zmm11{k3}, zmm28, zword [r12+r9*2-128]
vfmsub231ph zmm26{k5}{z}, zmm18, zword [rsp+r10*4+128]
vfpclassph k4, xmm24, -128
vfpclassph k6{k3}, xmm27, 1
vfpclassph k3{k4}, yword [rsi+r15*4-128], 127
vfpclassph k7{k3}, ymm0, 0
vfpclassph k1, zword [rcx+74565], 1
vfpclassph k5, zmm22, 0
vfpclasssh k0{k5}, xmm12, 127
vfpclasssh k2{k7}, word [r10+8], 127
vgetexpph xmm14, oword [r14+74565]
vgetexpph xmm18{k3}{z}, xmm6
vgetexpph ymm0, yword [8]
vgetexpph ymm31{k5}{z}, ymm28
vgetexpph zmm25, zword [74565]
vgetexpph zmm9{k2}, zword [rbp-128]
vgetexpsh xmm2{k1}{z}, xmm19
vgetexpsh xmm6{k2}, xmm24
vgetmantph xmm2, xmm17, 0
vgetmantph xmm7, oword [r9+74565], -1
vgetmantph ymm0, yword [r8+rdi*4], 127
vgetmantph ymm10{k4}{z}, yword [rsp+rcx*1+127], -1
vgetmantph zmm24{k6}{z}, zword [r12], -128
vgetmantph zmm28, zmm2, 1
vgetmantsh xmm3{k6}, word [rbx*1+8], 1
vgetmantsh xmm0{k6}, xmm13, 127
vmovsh xmm12{k5}, word [r12+127]
vmovsh xmm28, word [r13-128]
vmovsh word [-8], xmm2
vmovsh word [rax+rax*8], xmm15
vmovsh xmm3, xmm8, xmm5
vmovsh xmm21, xmm7, xmm1
vmovsh xmm21{k6}, xmm11, xmm7
vmovsh xmm19{k1}, xmm3, xmm7
vmulph xmm12, xmm25, xmm3
vmulph xmm5{k1}, xmm6, oword [r9+rdx*1]
vmulph ymm8, ymm13, ymm27
vmulph ymm12{k7}{z}, ymm18, yword [rdx-128]
vmulph zmm13{k5}{z}, zmm11, zword [-8]
vmulph zmm20{k6}, zmm3, zword [rsi+r15*4-8]
vmulsh xmm25{k5}{z}, xmm11, word [r12+r8*1]
vmulsh xmm3, xmm2, word [rax+8]
vrcpsh xmm12{k5}{z}, xmm5, xmm17
vrcpsh xmm26{k5}, xmm5, xmm31
vreduceph xmm22, xmm11, -1
vreduceph xmm26, oword [rbx+rcx*4], 127
vreduceph ymm10, ymm6, 5
vreduceph ymm14, ymm3, -1
vreduceph zmm2, zword [8], 0
vreduceph zmm25{k2}, zword [rsp+r11*1], 5
vreducesh xmm8, xmm30, word [r11+r13*8+8], 127
vreducesh xmm29, xmm4, word [rax+rdi*2+8], -128
vscalefph xmm12, xmm11, xmm17
vscalefph xmm3{k4}{z}, xmm11, xmm19
vscalefph ymm20, ymm12, yword [r8+128]
vscalefph ymm16{k2}{z}, ymm16, yword [r11+8]
vscalefph zmm13, zmm31, zmm6
vscalefph zmm13{k5}, zmm31, zword [rdi]
vscalefsh xmm13, xmm13, word [r12]
vscalefsh xmm6, xmm31, xmm22
vsqrtph xmm18{k5}, oword [r9-128]
vsqrtph xmm14, xmm22
vsqrtph ymm27{k3}{z}, ymm10
vsqrtph ymm3{k4}, ymm4
vsqrtph zmm30{k2}, zmm25
vsqrtph zmm28, zword [r14+r14*1-8]
vsqrtsh xmm9, xmm10, word [rbx+128]
vsqrtsh xmm21{k2}{z}, xmm13, word [r13+rsi*4+8]
vsubph xmm0{k2}, xmm20, xmm31
vsubph xmm10{k5}, xmm7, oword [rsi+74565]
vsubph ymm8, ymm2, ymm11
vsubph ymm2{k1}, ymm23, ymm18
vsubph zmm30, zmm28, zmm28
vsubph zmm0{k5}{z}, zmm8, zword [r10+r10*2-8]
vsubsh xmm25{k7}, xmm11, word [rbx+8]
vsubsh xmm23, xmm15, xmm2
vucomish xmm22, word [r12+r12*8+128]
vucomish xmm11, xmm13
cmpaexadd dword [rdi+8], r15d, ebx
cmpgexadd dword [rdx+127], esi, r11d
cmplexadd qword [rcx+8], r11, r13
cmpgexadd qword [rcx+8], rbx, r13
