;
; ============================================================================
; File        : profiler/strings.s
; Project     : utasm
; Author      : Utkarsha Lab
; License     : Apache-2.0
; Description : All string constants used by the profiler subsystem.
;
; Centralized .rodata for the profiler — phase names, report borders,
; column headers, formatting atoms, and footer text.
;
; Every profiler/*.s file that needs string data externs from here.
; ============================================================================
;

bits 64

%include "include/constant.inc"

[SECTION .rodata]

; ============================================================================
; PHASE NAME STRINGS
; ============================================================================
; Null-terminated phase names, referenced by the phase name pointer table.

global prof_name_lexer
global prof_name_prep
global prof_name_parser
global prof_name_semantic
global prof_name_encoder
global prof_name_linker
global prof_name_output
global prof_name_total

prof_name_lexer:        db "Lexer", 0
prof_name_prep:         db "Preprocessor", 0
prof_name_parser:       db "Parser", 0
prof_name_semantic:     db "Semantic", 0
prof_name_encoder:      db "Encoder", 0
prof_name_linker:       db "Linker", 0
prof_name_output:       db "Output", 0
prof_name_total:        db "Total", 0

; ============================================================================
; PHASE NAME POINTER TABLE
; ============================================================================
; Indexed by (PHASE_* - 1). Used by profiler_init to populate PROFENTRY.label.

    align 8
global prof_phase_names
prof_phase_names:
    dq prof_name_lexer
    dq prof_name_prep
    dq prof_name_parser
    dq prof_name_semantic
    dq prof_name_encoder
    dq prof_name_linker
    dq prof_name_output
    dq prof_name_total

; ============================================================================
; REPORT BORDERS & STRUCTURE
; ============================================================================

global prof_border_heavy
global prof_border_light
global prof_report_title
global prof_col_header
global prof_newline

prof_border_heavy:      db "========================================================", 10, 0
prof_border_light:      db "--------------------------------------------------------", 10, 0
prof_report_title:      db " utasm profiler report", 10, 0
prof_col_header:        db " Phase            Cycles          %     Calls      Avg", 10, 0
prof_newline:           db 10, 0

; ============================================================================
; ROW FORMATTING ATOMS
; ============================================================================

global prof_row_prefix
global prof_space
global prof_dot
global prof_pct_sign
global prof_comma

prof_row_prefix:        db " ", 0
prof_space:             db " ", 0
prof_dot:               db ".", 0
prof_pct_sign:          db "%", 0
prof_comma:             db ",", 0

; ============================================================================
; HOT PATH MARKERS
; ============================================================================

global prof_hot_marker
global prof_hot_marker_plain

prof_hot_marker:        db "  HOT", 0
prof_hot_marker_plain:  db "     ", 0

; ============================================================================
; TOTAL ROW
; ============================================================================

global prof_total_prefix
global prof_total_pct

prof_total_prefix:      db " Total       ", 0
prof_total_pct:         db "   100.0%", 10, 0

; ============================================================================
; FOOTER STRINGS
; ============================================================================

global prof_footer_legend
global prof_footer_calib_prefix
global prof_footer_calib_suffix
global prof_footer_wall_prefix
global prof_footer_wall_suffix
global prof_pct_zero

prof_footer_legend:     db " HOT = hot path (>10M cycles)", 10, 0
prof_footer_calib_prefix:
                        db " Calibration overhead: ", 0
prof_footer_calib_suffix:
                        db " cycles/measurement", 10, 0
prof_footer_wall_prefix:
                        db " Wall clock: ", 0
prof_footer_wall_suffix:
                        db " cycles", 10, 0
prof_pct_zero:          db "   0.0%", 0

; ============================================================================
; TRIGGER STRINGS
; ============================================================================

global prof_trigger_hot_prefix
global prof_trigger_hot_suffix
global prof_trigger_stub_msg

prof_trigger_hot_prefix:
    db "[profiler] hot path detected: ", 0
prof_trigger_hot_suffix:
    db " cycles)", 10, 0
prof_trigger_stub_msg:
    db "[profiler] selfpatch not yet implemented", 10, 0
prof_trigger_open_paren:
    db " (", 0
global prof_trigger_open_paren
