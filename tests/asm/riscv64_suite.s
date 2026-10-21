// ============================================================================
// UtkarshaLab Test Suite
// Architecture: RISC-V 64 (RV64GC)
// Description: Comprehensive coverage for the utasm RISC-V encoder.
// ============================================================================

[SECTION .text]

// ---- 1. RV64I Base Integer (R-Type, I-Type, U-Type, J-Type) ----
add a0, a1, a2
add w3, w4, w5           // Note: w registers map to x registers depending on assembler config
add x5, x6, x7
sub t0, t1, t2
sll s0, s1, s2
slt a3, a4, a5
sltu a6, a7, t3
xor t4, t5, t6
srl a0, a1, a2
sra a3, a4, a5
or t0, t1, t2
and s0, s1, s2

addi a0, a0, 0x123
slti a1, a1, -10
sltiu a2, a2, 10
xori a3, a3, 0xFF
ori a4, a4, 0x0F
andi a5, a5, 0xF0
slli t0, t0, 32
srli t1, t1, 16
srai t2, t2, 8

lui a0, 0x12345
auipc a1, 0x54321

// ---- 2. 64-bit specific (RV64I) ----
addw a0, a1, a2
subw a3, a4, a5
sllw a6, a7, t0
srlw t1, t2, t3
sraw t4, t5, t6
addiw a0, a0, 10
slliw a1, a1, 16
srliw a2, a2, 8
sraiw a3, a3, 4

// ---- 3. Memory Access (Loads & Stores) ----
lb a0, 0(sp)
lh a1, 2(sp)
lw a2, 4(sp)
ld a3, 8(sp)
lbu a4, 1(sp)
lhu a5, 3(sp)
lwu a6, 5(sp)

sb a0, 0(sp)
sh a1, 2(sp)
sw a2, 4(sp)
sd a3, 8(sp)

// ---- 4. RV64M Multiply/Divide ----
mul a0, a1, a2
mulh a3, a4, a5
mulhsu a6, a7, t0
mulhu t1, t2, t3
div t4, t5, t6
divu s0, s1, s2
rem s3, s4, s5
remu s6, s7, s8

mulw a0, a1, a2
divw a3, a4, a5
divuw a6, a7, t0
remw t1, t2, t3
remuw t4, t5, t6

// ---- 5. RV64A Atomics ----
lr.w a0, (a1)
sc.w a2, a3, (a1)
amoswap.w a4, a5, (a1)
amoadd.w a6, a7, (a1)
lr.d t0, (t1)
sc.d t2, t3, (t1)
amoadd.d t4, t5, (t1)

// ---- 6. Control Flow & Branches ----
beq a0, a1, _label_target
bne a2, a3, _label_target
blt a4, a5, _label_target
bge a6, a7, _label_target
bltu t0, t1, _label_target
bgeu t2, t3, _label_target

jal ra, _label_target
jalr ra, 0(t0)

// ---- 7. Pseudo-Instructions & Relaxation ----
nop
li a0, 0x12345678
la a1, _label_target
mv a2, a3
not a4, a5
neg a6, a7
sext.w t0, t1
seqz t2, t3
snez t4, t5
bnez t6, _label_target
beqz s0, _label_target
j _label_target
call _label_target
ret

_label_target:
ebreak
ecall

// ---- 8. RV64F/D Floating Point ----
flw f0, 0(sp)
fsw f1, 4(sp)
fld f2, 8(sp)
fsd f3, 16(sp)

fadd.s f4, f5, f6
fsub.s f7, f8, f9
fmul.s f10, f11, f12
fdiv.s f13, f14, f15

fadd.d f16, f17, f18
fsub.d f19, f20, f21
fmul.d f22, f23, f24
fdiv.d f25, f26, f27
fsqrt.d f28, f29
fmadd.d f30, f31, f0, f1
