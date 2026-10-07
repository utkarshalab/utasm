;
; ============================================================================
; File        : include/listing.inc
; Project     : utasm
; Description : The per-line entries the listing (-l) and the DWARF line
;               table (-g) are made from: backend/output/listing/listing.s
;               gathers them, debug/dwarf.s reads them too.
; ============================================================================
;

; ---- an entry ----
%define LE_FILE     0               ; q file name (as the lexer has it)
%define LE_SEC      8               ; q SECTION* current at its start, or 0
%define LE_START    16              ; q offset in that section
%define LE_END      24              ; q offset after its bytes
%define LE_LINE     32              ; d line number
%define LE_DEPTH    36              ; b include / expansion depth (marker)
%define LE_BODY     37              ; b 1: a line of a macro or %rep body
%define LE_KIND     38              ; b LK_*: how its bytes are shown
%define LE_HIDE     39              ; b 1: inside [list -]
%define LK_CODE     0               ;   byte by byte
%define LK_BIN      1               ;   incbin: <bin Nh>
%define LK_FILL     2               ;   align padding: 90<rep Nh>
%define LK_FIELD    3               ;   a struc field: ???? at its offset
%define LE_FILLTO   40              ; d body line: the file's lines before
                                    ;   this one are listed first ...
%define LE_FILLFILE 48              ; q ... from this file (the lexer's)
%define LE_REPS     44              ; d times: how many repetitions
%define LE_PFILE    56              ; q nested body line: the enclosing
%define LE_PLINE    64              ; d body's lines up to here are listed
                                    ;   first (an inner %rep block)
%define LE_WARN     72              ; q its warnings: {q next, text}, or 0
%define LE_UNINIT   80              ; q its "?" bytes: {q from, q to (from
                                    ;   the entry's start), q next}, or 0
%define LE_SIZE     88
%define LST_DEPTHS  32              ; include depths remembered

