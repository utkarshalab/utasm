%ifndef REGISTER_S
%define REGISTER_S

;
; ============================================================================
; File        : include/register.s
; Project     : utasm
; Description : AMD64 register semantic aliases for kernel and OS development.
;                Provides ABI calling convention aliases, system register
;                constants, and MSR identifiers usable in utasm source files.
; ============================================================================
;

; ============================================================================
; AMD64 SYSV ABI — CALLING CONVENTION ALIASES
; ============================================================================
; These aliases map the SysV AMD64 ABI roles onto concrete register names.
; Use these in kernel code for self-documenting system call sequences.

%define ARG1                   rdi     ; 1st function argument
%define ARG2                   rsi     ; 2nd function argument
%define ARG3                   rdx     ; 3rd function argument
%define ARG4                   rcx     ; 4th function argument
%define ARG5                   r8      ; 5th function argument
%define ARG6                   r9      ; 6th function argument
%define RETVAL                 rax     ; primary return value
%define RETVAL2                rdx     ; secondary return value (rdx:rax pair)
%define SYSCALL_NUM            rax     ; system call number register
%define SYSCALL_ARG1           rdi     ; syscall argument 1
%define SYSCALL_ARG2           rsi     ; syscall argument 2
%define SYSCALL_ARG3           rdx     ; syscall argument 3
%define SYSCALL_ARG4           r10     ; syscall argument 4 (note: NOT rcx)
%define SYSCALL_ARG5           r8      ; syscall argument 5
%define SYSCALL_ARG6           r9      ; syscall argument 6
%define SYSCALL_RET            rax     ; syscall return value / error (negative)

; ---- Callee-Saved (non-volatile) Registers ----
%define CALLEE0                rbx
%define CALLEE1                r12
%define CALLEE2                r13
%define CALLEE3                r14
%define CALLEE4                r15
%define FRAME_PTR              rbp
%define STACK_PTR              rsp

; ============================================================================
; SEGMENT REGISTER SELECTOR VALUES
; ============================================================================
; Standard GDT selector values used in a flat 64-bit kernel.
; The RPL (bits 1:0) = 0 means Ring 0 (kernel), = 3 means Ring 3 (user).

%define SEL_NULL               0x0000  ; null descriptor
%define SEL_KERNEL_CODE        0x0008  ; kernel code segment (Ring 0)
%define SEL_KERNEL_DATA        0x0010  ; kernel data segment (Ring 0)
%define SEL_USER_CODE          0x001B  ; user code  segment (Ring 3, RPL=3)
%define SEL_USER_DATA          0x0023  ; user data  segment (Ring 3, RPL=3)
%define SEL_TSS                0x0028  ; Task State Segment descriptor

; ---- Segment Override Prefix Bytes ----
%define SEG_ES                 0x26
%define SEG_CS                 0x2E
%define SEG_SS                 0x36
%define SEG_DS                 0x3E
%define SEG_FS                 0x64
%define SEG_GS                 0x65

; ============================================================================
; CONTROL REGISTER BIT MASKS
; ============================================================================

; ---- CR0 ----
%define CR0_PE                 0x00000001  ; Protected Mode Enable
%define CR0_MP                 0x00000002  ; Monitor Coprocessor
%define CR0_EM                 0x00000004  ; Emulation (disable x87)
%define CR0_TS                 0x00000008  ; Task Switched (lazy FPU)
%define CR0_ET                 0x00000010  ; Extension Type
%define CR0_NE                 0x00000020  ; Numeric Error (x87 internal)
%define CR0_WP                 0x00010000  ; Write Protect (Ring 0 obeys PTE WP)
%define CR0_AM                 0x00040000  ; Alignment Mask
%define CR0_NW                 0x20000000  ; Not Write-through (cache)
%define CR0_CD                 0x40000000  ; Cache Disable
%define CR0_PG                 0x80000000  ; Paging Enable

; ---- CR4 ----
%define CR4_VME                0x00000001  ; Virtual-8086 Mode Extensions
%define CR4_PVI                0x00000002  ; Protected-Mode Virtual Interrupts
%define CR4_TSD                0x00000004  ; Time Stamp Disable (RDTSC in Ring 0 only)
%define CR4_DE                 0x00000008  ; Debugging Extensions
%define CR4_PSE                0x00000010  ; Page Size Extension (4MB pages)
%define CR4_PAE                0x00000020  ; Physical Address Extension (>4GB)
%define CR4_MCE                0x00000040  ; Machine Check Enable
%define CR4_PGE                0x00000080  ; Page Global Enable (TLB global pages)
%define CR4_PCE                0x00000100  ; Performance Counter Enable
%define CR4_OSFXSR             0x00000200  ; OS support for FXSAVE/FXRSTOR
%define CR4_OSXMMEXCPT         0x00000400  ; OS Unmasked SIMD FP exceptions
%define CR4_UMIP               0x00000800  ; User-Mode Instruction Prevention
%define CR4_LA57               0x00001000  ; 5-Level Paging (57-bit VA)
%define CR4_VMXE               0x00002000  ; Virtual Machine Extensions Enable
%define CR4_SMXE               0x00004000  ; Safer Mode Extensions Enable
%define CR4_FSGSBASE           0x00010000  ; RDFSBASE/RDGSBASE/WRFSBASE/WRGSBASE
%define CR4_PCIDE              0x00020000  ; PCID Enable
%define CR4_OSXSAVE            0x00040000  ; XSAVE and Processor Extended States
%define CR4_SMEP               0x00100000  ; Supervisor Mode Execution Protection
%define CR4_SMAP               0x00200000  ; Supervisor Mode Access Protection
%define CR4_PKE                0x00400000  ; Protection Keys for User Pages
%define CR4_CET                0x00800000  ; Control-flow Enforcement Technology
%define CR4_PKS                0x01000000  ; Protection Keys for Supervisor Pages

; ---- EFLAGS / RFLAGS bit positions ----
%define RFLAGS_CF              0x00000001  ; Carry Flag
%define RFLAGS_PF              0x00000004  ; Parity Flag
%define RFLAGS_AF              0x00000010  ; Auxiliary Carry Flag
%define RFLAGS_ZF              0x00000040  ; Zero Flag
%define RFLAGS_SF              0x00000080  ; Sign Flag
%define RFLAGS_TF              0x00000100  ; Trap Flag (single-step)
%define RFLAGS_IF              0x00000200  ; Interrupt Enable Flag
%define RFLAGS_DF              0x00000400  ; Direction Flag
%define RFLAGS_OF              0x00000800  ; Overflow Flag
%define RFLAGS_IOPL_MASK       0x00003000  ; I/O Privilege Level (bits 12-13)
%define RFLAGS_NT              0x00004000  ; Nested Task Flag
%define RFLAGS_RF              0x00010000  ; Resume Flag
%define RFLAGS_VM              0x00020000  ; Virtual-8086 Mode
%define RFLAGS_AC              0x00040000  ; Alignment Check
%define RFLAGS_VIF             0x00080000  ; Virtual Interrupt Flag
%define RFLAGS_VIP             0x00100000  ; Virtual Interrupt Pending
%define RFLAGS_ID              0x00200000  ; CPUID support probe bit

; ============================================================================
; MODEL-SPECIFIC REGISTERS (MSRs)
; ============================================================================
; Used with RDMSR / WRMSR instructions. Load address into ECX first.

; ---- Extended Feature Enable Register ----
%define MSR_EFER               0xC0000080  ; Extended Feature Enables
%define EFER_SCE               0x00000001  ; SYSCALL/SYSRET enable
%define EFER_LME               0x00000100  ; Long Mode Enable
%define EFER_LMA               0x00000400  ; Long Mode Active (read-only)
%define EFER_NXE               0x00000800  ; No-Execute Enable (NX bit in PTE)
%define EFER_SVME              0x00001000  ; AMD-V (SVM) Enable
%define EFER_LMSLE             0x00002000  ; Long Mode Segment Limit Enable
%define EFER_FFXSR             0x00004000  ; Fast FXSAVE/FXRSTOR
%define EFER_TCE               0x00008000  ; Translation Cache Extension (AMD)

; ---- SYSCALL / SYSRET Target MSRs ----
%define MSR_STAR               0xC0000081  ; SYSCALL CS:SS selectors + compat ret
%define MSR_LSTAR              0xC0000082  ; SYSCALL target RIP (Long Mode)
%define MSR_CSTAR              0xC0000083  ; SYSCALL target RIP (Compat Mode)
%define MSR_SFMASK             0xC0000084  ; RFLAGS mask on SYSCALL entry

; ---- FS/GS Base MSRs ----
%define MSR_FS_BASE            0xC0000100  ; FS.Base virtual address
%define MSR_GS_BASE            0xC0000101  ; GS.Base virtual address
%define MSR_KERNEL_GS_BASE     0xC0000102  ; Shadow GS.Base (SWAPGS target)

; ---- Local APIC MSR ----
%define MSR_APIC_BASE          0x0000001B  ; APIC base address + enable bits
%define APIC_BASE_BSP          0x00000100  ; Is bootstrap processor?
%define APIC_BASE_ENABLE       0x00000800  ; Global APIC enable
%define APIC_BASE_X2APIC       0x00000C00  ; x2APIC mode

; ---- TSC & Performance MSRs ----
%define MSR_TSC                0x00000010  ; Time Stamp Counter
%define MSR_TSC_DEADLINE       0x000006E0  ; TSC Deadline for APIC timer
%define MSR_PERF_CTL0          0xC0010000  ; AMD: Performance Control 0
%define MSR_PERF_CTR0          0xC0010004  ; AMD: Performance Counter 0
%define MSR_FIXED_CTR0         0x00000309  ; Intel: Fixed Counter 0 (inst retired)
%define MSR_FIXED_CTR1         0x0000030A  ; Intel: Fixed Counter 1 (clk unhalted)
%define MSR_FIXED_CTR2         0x0000030B  ; Intel: Fixed Counter 2 (ref cycles)

; ---- Memory Type Range Registers ----
%define MSR_MTRR_DEF_TYPE      0x000002FF  ; MTRR default type
%define MSR_MTRR_PHYSBASE0     0x00000200  ; MTRR physical base 0
%define MSR_MTRR_PHYSMASK0     0x00000201  ; MTRR physical mask 0

; ---- Thermal & Power MSRs ----
%define MSR_THERM_STATUS       0x0000019C  ; Thermal Status register
%define MSR_POWER_CTL          0x000001FC  ; Power Control register

; ---- Spectre / Meltdown Mitigations ----
%define MSR_SPEC_CTRL          0x00000048  ; Speculation Control (IBRS, STIBP)
%define MSR_PRED_CMD           0x00000049  ; Prediction Command (IBPB)
%define SPEC_CTRL_IBRS         0x00000001  ; Indirect Branch Restricted Speculation
%define SPEC_CTRL_STIBP        0x00000002  ; Single Thread Indirect Branch Predictors
%define SPEC_CTRL_SSBD         0x00000004  ; Speculative Store Bypass Disable

; ============================================================================
; DEBUG REGISTER BIT MASKS
; ============================================================================

; ---- DR7 — Debug Control Register ----
%define DR7_L0                 0x00000001  ; Local enable breakpoint 0
%define DR7_G0                 0x00000002  ; Global enable breakpoint 0
%define DR7_L1                 0x00000004  ; Local enable breakpoint 1
%define DR7_G1                 0x00000008  ; Global enable breakpoint 1
%define DR7_L2                 0x00000010  ; Local enable breakpoint 2
%define DR7_G2                 0x00000020  ; Global enable breakpoint 2
%define DR7_L3                 0x00000040  ; Local enable breakpoint 3
%define DR7_G3                 0x00000080  ; Global enable breakpoint 3
%define DR7_LE                 0x00000100  ; Local exact breakpoint enable
%define DR7_GE                 0x00000200  ; Global exact breakpoint enable
%define DR7_RTM                0x00000800  ; Advanced debugging of RTM regions
%define DR7_GD                 0x00002000  ; General Detect Enable

; ---- DR6 — Debug Status Register ----
%define DR6_B0                 0x00000001  ; Breakpoint 0 triggered
%define DR6_B1                 0x00000002  ; Breakpoint 1 triggered
%define DR6_B2                 0x00000004  ; Breakpoint 2 triggered
%define DR6_B3                 0x00000008  ; Breakpoint 3 triggered
%define DR6_BD                 0x00002000  ; Debug register accessed
%define DR6_BS                 0x00004000  ; Single-step triggered
%define DR6_BT                 0x00008000  ; Task switch triggered

; ============================================================================
; x87 FPU CONTROL / STATUS WORD BITS
; ============================================================================

%define FCW_IM                 0x0001      ; Invalid Operation mask
%define FCW_DM                 0x0002      ; Denormalized Operand mask
%define FCW_ZM                 0x0004      ; Zero Divide mask
%define FCW_OM                 0x0008      ; Overflow mask
%define FCW_UM                 0x0010      ; Underflow mask
%define FCW_PM                 0x0020      ; Precision mask
%define FCW_PC_SINGLE          0x0000      ; Precision: 24-bit mantissa
%define FCW_PC_DOUBLE          0x0200      ; Precision: 53-bit mantissa
%define FCW_PC_EXTENDED        0x0300      ; Precision: 64-bit mantissa (default)
%define FCW_RC_NEAREST         0x0000      ; Round: to nearest (default)
%define FCW_RC_DOWN            0x0400      ; Round: toward -infinity
%define FCW_RC_UP              0x0800      ; Round: toward +infinity
%define FCW_RC_TRUNC           0x0C00      ; Round: toward zero (truncate)

; ============================================================================
; MXCSR — SSE Control/Status Register Bits
; ============================================================================

%define MXCSR_IE               0x0001      ; Invalid Operation flag
%define MXCSR_DE               0x0002      ; Denormal flag
%define MXCSR_ZE               0x0004      ; Divide-by-Zero flag
%define MXCSR_OE               0x0008      ; Overflow flag
%define MXCSR_UE               0x0010      ; Underflow flag
%define MXCSR_PE               0x0020      ; Precision flag
%define MXCSR_DAZ              0x0040      ; Denormals Are Zeros
%define MXCSR_IM               0x0080      ; Invalid Operation mask
%define MXCSR_DM               0x0100      ; Denormal mask
%define MXCSR_ZM               0x0200      ; Divide-by-Zero mask
%define MXCSR_OM               0x0400      ; Overflow mask
%define MXCSR_UM               0x0800      ; Underflow mask
%define MXCSR_PM               0x1000      ; Precision mask
%define MXCSR_RC_NEAREST        0x0000      ; Round to nearest
%define MXCSR_RC_DOWN           0x2000      ; Round toward -infinity
%define MXCSR_RC_UP             0x4000      ; Round toward +infinity
%define MXCSR_RC_TRUNC          0x6000      ; Round toward zero
%define MXCSR_FTZ              0x8000      ; Flush to Zero (denormals)
%define MXCSR_DEFAULT          0x1F80      ; Recommended kernel default

%endif
