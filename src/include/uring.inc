%ifndef URING_S
%define URING_S

;
; ============================================================================
; File        : include/uring.s
; Project     : utasm
; Description : Linux io_uring architectural definitions and syscall maps.
;                Used for hyper-fast, asynchronous, zero-copy file I/O operations.
; ============================================================================
;

; ============================================================================
; SYSTEM CALLS (AMD64)
; ============================================================================
%define SYS_IO_URING_SETUP      425
%define SYS_IO_URING_ENTER      426
%define SYS_IO_URING_REGISTER   427

; ============================================================================
; OPCODES (io_uring_sqe->opcode)
; ============================================================================
%define IORING_OP_NOP           0
%define IORING_OP_READV         1
%define IORING_OP_WRITEV        2
%define IORING_OP_FSYNC         3
%define IORING_OP_READ_FIXED    4
%define IORING_OP_WRITE_FIXED   5
%define IORING_OP_POLL_ADD      6
%define IORING_OP_POLL_REMOVE   7
%define IORING_OP_SYNC_FILE_RANGE 8
%define IORING_OP_SENDMSG       9
%define IORING_OP_RECVMSG       10
%define IORING_OP_TIMEOUT       11
%define IORING_OP_TIMEOUT_REMOVE 12
%define IORING_OP_ACCEPT        13
%define IORING_OP_ASYNC_CANCEL  14
%define IORING_OP_LINK_TIMEOUT  15
%define IORING_OP_CONNECT       16
%define IORING_OP_FALLOCATE     17
%define IORING_OP_OPENAT        18
%define IORING_OP_CLOSE         19
%define IORING_OP_FILES_UPDATE  20
%define IORING_OP_STATX         21
%define IORING_OP_READ          22
%define IORING_OP_WRITE         23

; ============================================================================
; SUBMISSION QUEUE ENTRY (io_uring_sqe)
; ============================================================================
; Total Size: 64 bytes
%define URING_SQE_SIZE          64

%define SQE_OPCODE              0   ; u8: opcode
%define SQE_FLAGS               1   ; u8: IOSQE_ flags
%define SQE_IOPRIO              2   ; u16: ioprio
%define SQE_FD                  4   ; i32: file descriptor
%define SQE_OFF                 8   ; u64: offset into file
%define SQE_ADDR                16  ; u64: pointer to buffer or iovecs
%define SQE_LEN                 24  ; u32: buffer size or number of iovecs
%define SQE_RW_FLAGS            28  ; u32: rw flags (e.g., RWF_DSYNC)
%define SQE_USER_DATA           32  ; u64: opaque data for completion (cqe)
%define SQE_BUF_INDEX           40  ; u16: index into fixed buffers (if used)
%define SQE_PERSONALITY         42  ; u16: personality index
%define SQE_SPLICE_FD_IN        44  ; i32: fd_in for splice/tee
%define SQE_PAD_1               48  ; padding

; ============================================================================
; COMPLETION QUEUE ENTRY (io_uring_cqe)
; ============================================================================
; Total Size: 16 bytes
%define URING_CQE_SIZE          16

%define CQE_USER_DATA           0   ; u64: opaque data passed in sqe
%define CQE_RES                 8   ; i32: result code for this event
%define CQE_FLAGS               12  ; u32: IORING_CQE_F_* flags

; ============================================================================
; io_uring_params STRUCT
; ============================================================================
; Total Size: 120 bytes
%define URING_PARAMS_SIZE       120

%define UPAR_SQ_ENTRIES         0   ; u32: sq entries
%define UPAR_CQ_ENTRIES         4   ; u32: cq entries
%define UPAR_FLAGS              8   ; u32: setup flags
%define UPAR_SQ_THREAD_CPU      12  ; u32
%define UPAR_SQ_THREAD_IDLE     16  ; u32
%define UPAR_FEATURES           20  ; u32: features kernel supports
%define UPAR_WQ_FD              24  ; u32

; SQ Ring Offsets
%define UPAR_SQ_OFF_HEAD        40
%define UPAR_SQ_OFF_TAIL        44
%define UPAR_SQ_OFF_RING_MASK   48
%define UPAR_SQ_OFF_RING_ENTRIES 52
%define UPAR_SQ_OFF_FLAGS       56
%define UPAR_SQ_OFF_DROPPED     60
%define UPAR_SQ_OFF_ARRAY       64

; CQ Ring Offsets
%define UPAR_CQ_OFF_HEAD        80
%define UPAR_CQ_OFF_TAIL        84
%define UPAR_CQ_OFF_RING_MASK   88
%define UPAR_CQ_OFF_RING_ENTRIES 92
%define UPAR_CQ_OFF_FLAGS       96
%define UPAR_CQ_OFF_OVERFLOW    100
%define UPAR_CQ_OFF_CQES        104

; ============================================================================
; IORING MAGIC OFFSETS (mmap offsets)
; ============================================================================
%define IORING_OFF_SQ_RING      0
%define IORING_OFF_CQ_RING      0x8000000
%define IORING_OFF_SQES         0x10000000

%endif
