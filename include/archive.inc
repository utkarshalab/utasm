; ============================================================================
; File        : include/archive.inc
; Project     : utasm
; Description : Unix Archive (.a) Format Definitions & Structures
; ============================================================================

%ifndef ARCHIVE_INC
%define ARCHIVE_INC

; Archive Header Constants
%define AR_MAG_LEN      8
%define AR_HDR_SIZE     60

; Unix Archive Member Header (60 bytes total)
struc ARHDR
    field name,     16      ; File name / identifier (ASCII)
    field date,     12      ; Modification timestamp (ASCII decimal)
    field uid,      6       ; User ID (ASCII decimal)
    field gid,      6       ; Group ID (ASCII decimal)
    field mode,     8       ; File mode (ASCII octal)
    field size,     10      ; File size in bytes (ASCII decimal)
    field fmag,     2       ; Header trailer string (0x60, 0x0A)
endstruc

%endif ; ARCHIVE_INC
