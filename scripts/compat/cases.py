"""Source snippets the compatibility suites assemble with NASM and utasm.

Generated once from the ad-hoc checks used while bringing utasm up to NASM;
edit freely -- every entry is a small, self-contained program.
"""

# flat binary (-f bin): "bits 64" is put first unless the snippet sets it
BIN_PROBES = {'basic_no_section': 'nop\nret\n',
 'basic_text_define': 'section .text\n%define REG rax\n%define VAL 5\nmov REG, VAL\n',
 'basic_define_params': 'section .text\n%define ADD2(a,b) ((a)+(b))\nmov eax, ADD2(3,4)\n',
 'basic_xdefine': 'section .text\n%define A 1\n%xdefine B A\n%define A 2\nmov eax, B\n',
 'basic_assign_loop': 'section .text\n%assign i 0\n%rep 4\ndb i\n%assign i i+1\n%endrep\n',
 'basic_times': 'section .text\ntimes 5 db 0x90\ntimes 3 dw 0x1234\n',
 'basic_times_expr': 'section .text\nstart:\ndb 1,2,3\ntimes 8-($-start) db 0\n',
 'basic_db_string': 'section .text\ndb \'abc\', 0, "de"\ndw \'ab\'\ndd \'abcd\'\n',
 'basic_backquote': 'section .text\ndb `a\\tb\\n\\x41\\0`\n',
 'basic_float_data': 'section .text\ndd 1.5\ndq 3.25\ndq -0.5\ndd 1.0e3\n',
 'basic_dt_float': 'section .text\ndt 1.5\n',
 'basic_resb_bss': 'section .text\nnop\nsection .bss\nbuf: resb 16\nresw 2\nresd 1\nresq 1\n',
 'basic_align': 'section .text\ndb 1\nalign 8\ndb 2\nalign 4, db 0xCC\ndb 3\n',
 'basic_struc': 'section .text\n'
                'struc pt\n'
                '.x: resd 1\n'
                '.y: resd 1\n'
                'endstruc\n'
                'mov eax, pt.y\n'
                'mov eax, pt_size\n',
 'basic_istruc': 'section .text\n'
                 'struc pt\n'
                 '.x: resd 1\n'
                 '.y: resw 1\n'
                 'endstruc\n'
                 'istruc pt\n'
                 'at pt.x, dd 7\n'
                 'at pt.y, dw 9\n'
                 'iend\n',
 'basic_equ_expr': 'section .text\nA equ 10\nB equ A*3+2\nmov eax, B\nmov ebx, (B >> 1) | 1\n',
 'basic_dollar_dollar': 'section .text\nnop\nnop\nmov eax, $-$$\n',
 'basic_local_labels': 'section .text\nf:\n.a: jmp .a\ng:\n.a: jmp .a\n',
 'basic_macro_defaults': 'section .text\n'
                         '%macro m 1-2 7\n'
                         'mov eax, %1\n'
                         'mov ebx, %2\n'
                         '%endmacro\n'
                         'm 1\n'
                         'm 1, 2\n',
 'basic_macro_greedy': 'section .text\n%macro emit 1+\ndb %1\n%endmacro\nemit 1, 2, 3\n',
 'basic_macro_local': 'section .text\n'
                      '%macro spin 0\n'
                      '%%l: dec ecx\n'
                      'jnz %%l\n'
                      '%endmacro\n'
                      'spin\n'
                      'spin\n',
 'basic_ifidn': 'section .text\n'
                '%macro z 1\n'
                '%ifidn %1, rax\n'
                'xor eax, eax\n'
                '%else\n'
                'xor %1, %1\n'
                '%endif\n'
                '%endmacro\n'
                'z rax\n'
                'z rbx\n',
 'basic_if_expr': 'section .text\n'
                  '%if 3 > 2 && 1\n'
                  'db 1\n'
                  '%elif 1\n'
                  'db 2\n'
                  '%endif\n'
                  '%if (4 & 1)\n'
                  'db 3\n'
                  '%else\n'
                  'db 4\n'
                  '%endif\n',
 'basic_ifdef': 'section .text\n%define X\n%ifdef X\ndb 1\n%endif\n%ifndef Y\ndb 2\n%endif\n',
 'basic_strlen_substr': "section .text\n%strlen L 'hello'\ndb L\n%substr S 'hello' 2\ndb S\n",
 'basic_strcat': "section .text\n%strcat S 'ab', 'cd'\ndb S\n",
 'basic_incbin': 'section .text\nincbin "/etc/hostname", 0, 2\n',
 'basic_char_const': "section .text\nmov al, 'A'\nmov eax, 'AB'\ncmp byte [rax], 'x'\n",
 'basic_neg_expr': 'section .text\nmov eax, -(3+4)\nmov ebx, ~0\nmov ecx, 7 % 3\nmov edx, 1 << 4\n',
 'basic_seg_rel': 'section .text\ndefault rel\nlea rax, [x]\nx: dq 0\n',
 'basic_org': 'bits 64\norg 0x7c00\nsection .text\njmp short $\nmov ax, [here]\nhere: dw 0\n',
 'basic_bits16': 'bits 16\nsection .text\nmov ax, 1\nint 0x10\n',
 'basic_bits32': 'bits 32\nsection .text\nmov eax, 1\npush ebx\n',
 'basic_multi_section': 'section .text\nnop\nsection .data\ndb 7\nsection .text\nnop\n',
 'basic_use_sym_diff': 'section .text\na: nop\nnop\nb:\nmov eax, b - a\n',
 'basic_sizeof_dq_list': 'section .text\ntbl: dq 1, 2, 3\nmov eax, ($ - tbl) / 8\n',
 'basic_cpu_directive': 'cpu x64\nsection .text\nnop\n',
 'basic_warning_dir': 'section .text\n%warning hello\nnop\n',
 'basic_label_colonless': 'section .text\nfoo nop\njmp foo\n',
 'basic_db_dup_q': 'section .text\ndq 0x1122334455667788, -1\ndw -2\n',
 'basic_string_escape_nul': 'section .text\ndb "a\\"b"\n',
 'basic_push_imm_sym': 'section .text\nx equ 0x1234\npush x\n',
 'basic_rep_nested': 'section .text\n%rep 2\n%rep 3\nnop\n%endrep\nint3\n%endrep\n',
 'basic_exitrep': 'section .text\n'
                  '%assign i 0\n'
                  '%rep 10\n'
                  '%if i == 3\n'
                  '%exitrep\n'
                  '%endif\n'
                  'db i\n'
                  '%assign i i+1\n'
                  '%endrep\n',
 'basic_macro_nolist_plus': 'section .text\n'
                            '%macro pr 0-*\n'
                            '%rep %0\n'
                            'db %1\n'
                            '%rotate 1\n'
                            '%endrep\n'
                            '%endmacro\n'
                            'pr 1,2,3\n',
 'basic_idefine': 'section .text\n%idefine Foo 3\nmov eax, FOO\n',
 'basic_deftok': "section .text\n%deftok T 'nop'\nT\n",
 'basic_ternary_like': 'section .text\nmov eax, (1 ? 5 : 6)\n',
 'basic_cmp_ops': 'section .text\ndb (3 == 3), (3 != 3), (2 < 3), (3 <= 2), (5 >= 5)\n',
 'basic_seg_directive': 'segment .text\nnop\n',
 'basic_section_attr': 'section .text progbits alloc exec align=16\nnop\n',
 'basic_global_extern_bin': 'section .text\nglobal a\na: ret\n',
 'num_h_suffix': 'mov eax, 0ffh\nmov ebx, 10h\n',
 'num_q_suffix': 'mov eax, 777q\nmov ebx, 17o\n',
 'num_b_suffix': 'mov eax, 1010b\nmov ebx, 0b1010\n',
 'num_y_suffix': 'mov eax, 1010y\nmov ebx, 0y1010\n',
 'num_dollar_hex': 'mov eax, $0ff\n',
 'num_d_prefix': 'mov eax, 0d100\nmov ebx, 100d\n',
 'num_t_prefix': 'mov eax, 0t100\n',
 'num_underscore': 'mov eax, 1_000_000\nmov ebx, 0xdead_beef\n',
 'num_0h_prefix': 'mov eax, 0h1f\n',
 'num_large': 'mov rax, 0x123456789abcdef0\n',
 'op_signed_div': 'mov eax, -7 // 2\nmov ebx, -7 %% 2\n',
 'op_logical': 'db (1 && 0), (1 || 0), (1 ^^ 1), !0, !5\n',
 'op_shifts': 'mov eax, -16 >>> 2\nmov ebx, 1 <<< 3\nmov ecx, -16 >> 2\n',
 'op_cmp3': 'db (1 <=> 2), (2 <=> 2), (3 <=> 2)\n',
 'op_ne_alt': 'db (1 <> 2), (2 <> 2)\n',
 'op_unary_plus': 'mov eax, +5\nmov ebx, -(-3)\n',
 'op_bitnot_xor': 'mov eax, ~0 ^ 0xff\nmov ebx, 6 & 3 | 8\n',
 'op_precedence': 'db 1 + 2 * 3, (1 + 2) * 3, 10 - 2 - 3, 2 * 3 % 4\n',
 'pre_bits': 'db __BITS__\n',
 'pre_line': '\ndb __LINE__\n',
 'pre_sect': '%ifidn __SECT__, [section .text]\ndb 1\n%else\ndb 2\n%endif\n',
 'pre_pass': 'db __PASS__\n',
 'pre_nasm_ver': '%ifdef __NASM_MAJOR__\ndb 1\n%endif\n',
 'pre_output_format': '%ifidn __OUTPUT_FORMAT__, bin\ndb 1\n%else\ndb 2\n%endif\n',
 'pre_file': 'db __FILE__\n',
 'pp_ifnum': '%ifnum 5\ndb 1\n%endif\n%ifnum x\ndb 2\n%endif\n',
 'pp_ifstr': "%ifstr 'a'\ndb 1\n%endif\n%ifstr 5\ndb 2\n%endif\n",
 'pp_ifid': '%ifid foo\ndb 1\n%endif\n%ifid 5\ndb 2\n%endif\n',
 'pp_ifempty': '%macro m 0-1\n%ifempty %1\ndb 1\n%else\ndb 2\n%endif\n%endmacro\nm\nm x\n',
 'pp_ifmacro': '%macro mm 1\n%endmacro\n%ifmacro mm\ndb 1\n%endif\n%ifmacro nn\ndb 2\n%endif\n',
 'pp_ifdef_macro': '%define A\n%ifdef A\ndb 1\n%endif\n%ifndef B\ndb 2\n%endif\n',
 'pp_elifdef': '%ifdef X\ndb 1\n%elifdef Y\ndb 2\n%else\ndb 3\n%endif\n',
 'pp_elif_chain': '%assign v 3\n'
                  '%if v == 1\n'
                  'db 1\n'
                  '%elif v == 2\n'
                  'db 2\n'
                  '%elif v == 3\n'
                  'db 3\n'
                  '%else\n'
                  'db 4\n'
                  '%endif\n',
 'pp_defstr': '%defstr S hello world\ndb S\n',
 'pp_strlen_var': "%define T 'abcd'\n%strlen L T\ndb L\n",
 'pp_substr_len': "%substr S 'hello', 2, 3\ndb S\n",
 'pp_substr_neg': "%substr S 'hello', -3, 2\ndb S\n",
 'pp_indirect': '%define N 2\n%define X2 7\ndb X%[N]\n',
 'pp_paste': '%define P ab\n%define abcd 9\ndb P %+ cd\n',
 'pp_macro_label_param': '%macro lbl 0\n%00: nop\n%endmacro\nhere: lbl\njmp here\n',
 'pp_macro_last_param': '%macro m 1-*\ndb %-1\n%endmacro\nm 1, 2, 3\n',
 'pp_macro_range': '%macro m 1-*\ndb %{2:3}\n%endmacro\nm 1, 2, 3, 4\n',
 'pp_macro_name': '%macro myname 0\ndb %?\n%endmacro\nmyname\n',
 'pp_macro_overload': '%macro m 1\ndb 1\n%endmacro\n%macro m 2\ndb 2\n%endmacro\nm a\nm a, b\n',
 'pp_imacro': '%imacro Foo 0\ndb 7\n%endmacro\nFOO\nfoo\n',
 'pp_exitmacro': '%macro m 1\ndb 1\n%if %1\n%exitmacro\n%endif\ndb 2\n%endmacro\nm 1\nm 0\n',
 'pp_rotate_neg': '%macro m 3\n%rotate -1\ndb %1, %2, %3\n%endmacro\nm 1, 2, 3\n',
 'pp_context_local': '%push ctx\n%define %$v 5\ndb %$v\n%pop\n',
 'pp_repl': '%push a\n%repl b\n%ifctx b\ndb 1\n%endif\n%pop\n',
 'pp_local_labels_ctx': '%macro if1 0\n'
                        '%push if\n'
                        'jmp %$skip\n'
                        '%endmacro\n'
                        '%macro end1 0\n'
                        '%$skip:\n'
                        '%pop\n'
                        '%endmacro\n'
                        'if1\n'
                        'nop\n'
                        'end1\n',
 'pp_assign_expr': '%assign x 3\n%assign x x*x+1\ndb x\n',
 'pp_xdefine_chain': '%define a 1\n%xdefine b a\n%define a 2\ndb b\n',
 'pp_undef_macro': '%define Q 1\n%undef Q\n%ifdef Q\ndb 1\n%else\ndb 2\n%endif\n',
 'pp_rep_counter': '%assign i 0\n%rep 4\ndb i*i\n%assign i i+1\n%endrep\n',
 'pp_line': '%line 100 foo.s\ndb __LINE__\n',
 'pp_use': '%use altreg\nmov r0, r1\n',
 'pp_pragma': '%pragma foo bar\nnop\n',
 'pp_clear': '%define A 1\n%clear\n%ifdef A\ndb 1\n%else\ndb 2\n%endif\n',
 'pp_stringify_param': "%macro s 1\ndb %1\n%endmacro\ns 'xy'\n",
 'pp_comment_after_dir': '%define V 3 ; comment\ndb V\n',
 'pp_multi_line_macro_args': '%macro m 2\ndb %1\ndb %2\n%endmacro\nm {1, 2}, 3\n',
 'pp_nested_macro_def': '%macro outer 0\n'
                        '%macro inner 0\n'
                        'db 9\n'
                        '%endmacro\n'
                        '%endmacro\n'
                        'outer\n'
                        'inner\n',
 'pp_iassign': '%iassign Qq 5\ndb QQ\n',
 'pp_ifidni_str': "%ifidni 'ABC', 'abc'\ndb 1\n%endif\n",
 'pp_if_string_cmp': "%if 'ab' == 'ab'\ndb 1\n%endif\n",
 'pp_defalias': '%defalias foo bar\nnop\n',
 'dir_absolute': 'absolute 0x100\nvar: resb 4\nvar2: resw 1\nsection .text\nmov eax, var2\n',
 'dir_times_expr': 'times 2+1 db 7\ntimes 0 db 1\n',
 'dir_times_instr': 'times 3 nop\n',
 'dir_times_dollar': 'db 1, 2\ntimes 8-($-$$) db 0\n',
 'dir_align_code': 'nop\nalign 8\nnop\n',
 'dir_alignb_bss': 'section .bss\nresb 1\nalignb 8\nx: resb 1\nsection .text\nmov eax, x\n',
 'dir_equ_dollar': 'a: db 1,2,3\nalen equ $ - a\ndb alen\n',
 'dir_db_question': 'db 1\ndb ?\ndb 2\n',
 'dir_dw_question': 'dw ?, 5\n',
 'dir_times_question': 'times 3 db ?\ndb 1\n',
 'dir_org_label': 'org 0x7c00\nstart: jmp start\ndw start\n',
 'dir_default_abs': 'default abs\nmov eax, [0x1000]\n',
 'dir_bits32_mix': 'bits 32\nmov eax, [ebx+4]\nbits 64\nmov rax, [rbx+4]\n',
 'dir_use32': 'use32\nmov eax, 1\nuse64\nmov rax, 1\n',
 'dir_section_vstart': 'section .text\n'
                       'nop\n'
                       'section .data vstart=0x1000\n'
                       'd: db 1\n'
                       'section .text\n'
                       'mov eax, d\n',
 'dir_section_follows': 'section .a\ndb 1\nsection .b follows=.a\ndb 2\n',
 'dir_warning_pragma': '[warning -all]\nnop\n',
 'dir_map': '[map all x.map]\nnop\n',
 'dir_list': '[list -]\nnop\n[list +]\n',
 'dir_cpu_named': 'cpu 386\nnop\n',
 'dir_float_ctrl': 'float daz\nfloat nodaz\ndd 1.5\n',
 'dir_extern_bin': 'extern foo\nnop\n',
 'ins_strict': 'push strict dword 5\nmov eax, strict dword 1\n',
 'ins_prefix_o16': 'o16 movsb\no32 lodsd\n',
 'ins_a32': 'a32 mov eax, [ebx]\n',
 'ins_rep_prefix': 'rep movsb\nrepne scasb\nrepe cmpsb\n',
 'ins_lock_prefix': 'lock inc dword [rax]\n',
 'ins_seg_prefix_line': 'fs mov eax, [rbx]\n',
 'ins_far_jmp': 'jmp far [rax]\ncall far [rbx]\n',
 'ins_short_near': 'jmp short l\nl: jmp near l\n',
 'ins_type_ptr': 'mov byte [rax], 1\nmov word [rax], 1\nmov dword [rax], 1\nmov qword [rax], 1\n',
 'ins_nosplit': 'mov eax, [nosplit eax*2]\n',
 'ins_rel_abs': 'mov eax, [rel x]\nmov eax, [abs x]\nx: dd 0\n',
 'ins_seg_override': 'mov eax, [fs:rbx]\nmov eax, [gs:0x10]\n',
 'ins_label_arith': 'a: nop\nb: nop\nmov eax, b-a\nmov ebx, (b-a)*4\n',
 'ins_bracket_directive': '[bits 64]\n[section .text]\nnop\n',
 'ins_mov_imm_sizes': 'mov al, -1\nmov ax, -1\nmov eax, -1\nmov rax, -1\n',
 'ins_mem_scale_forms': 'lea eax, [rbx*2+rcx]\nlea eax, [rbx+rcx*8+0x10]\nlea eax, [2*rbx]\n',
 'ins_mem_expr': 'lea rax, [rbx + 4*2 - 1]\n',
 'ins_jcc_forms': 'l: jz l\njnz l\njc l\njnae l\njpe l\njpo l\n',
 'ins_setcc_aliases': 'setz al\nsetnae bl\nsetpe cl\n',
 'ins_cmov_aliases': 'cmovz eax, ebx\ncmovnae eax, ebx\n',
 'ins_fpu': 'fld dword [rax]\nfstp qword [rbx]\nfadd st0, st1\nfxch\nfldpi\n',
 'ins_sse_forms': 'movaps xmm0, xmm1\naddss xmm2, [rax]\n',
 'ins_int3': 'int3\nint 3\n',
 'ins_ret_imm': 'ret 8\nretf\n',
 'ins_enter_leave': 'enter 16, 0\nleave\n',
 'ins_xlat': 'xlatb\ncqo\ncdq\ncwde\ncbw\n',
 'ins_movzx_forms': 'movzx eax, byte [rax]\nmovsx rax, word [rbx]\nmovsxd rax, dword [rcx]\n',
 'ins_label_colon_space': 'lbl : nop\njmp lbl\n',
 'ins_dup_label_local': 'g1:\n.x: nop\ng2:\n.x: nop\njmp g1.x\n',
 'ins_special_local': '..@x: nop\njmp ..@x\n',
 'ins_dotdot_start': '..start: nop\n',
 'ins_str_imm': "mov eax, 'abcd'\npush 'ab'\n",
 'ins_empty_lines_comments': '; only comment\n\n   nop ; trailing\n',
 'ins_multiple_prefix': 'lock xchg [rax], ebx\n',
 'ins_times_label': 'tbl: times 4 dd tbl\n',
 # %ifdef with %else: a true %ifdef used to let the %else branch through
 'pp_ifdef_else': '%define F\n%ifdef F\ndb 1\n%else\ndb 2\n%endif\ndb 3\n',
 'pp_ifndef_else': '%define F\n%ifndef F\ndb 1\n%else\ndb 2\n%endif\n',
 'pp_elifdef_taken': '%define G\n%ifdef F\ndb 1\n%elifdef G\ndb 2\n%else\ndb 3\n%endif\n',
 'pp_elifndef': '%ifdef F\ndb 1\n%elifndef G\ndb 2\n%else\ndb 3\n%endif\n',
 'pp_ifdef_in_skip': '%if 0\n%ifdef F\ndb 1\n%else\ndb 2\n%endif\ndb 4\n%endif\ndb 5\n',
 'pp_ifdef_label': 'lbl: db 0\n%ifdef lbl\ndb 1\n%else\ndb 2\n%endif\n',
 'pp_ifdef_file': '%ifdef __FILE__\ndb 1\n%else\ndb 2\n%endif\n',
 'pp_ifdef_assign': '%assign A 3\n%ifdef A\ndb A\n%endif\n',
 'pp_ifdef_mline': '%macro mm 0\nnop\n%endmacro\n%ifdef mm\ndb 1\n%else\ndb 2\n%endif\n'}

# ELF objects: section contents, relocations and symbols are compared
ELF_PROBES = {
 # same-section PC-relative references are written in place, as NASM does
 'elf_rel_same_fwd': 'mov eax, [rel x]\nx: dd 1\n',
 'elf_rel_same_back': 'x: dd 1\nmov eax, [rel x]\n',
 'elf_rel_same_offset': 'lea rax, [rel x+4]\nx: dq 0\n',
 'elf_jmp_short_fwd': 'jmp short l\nl: ret\n',
 'elf_call_global_same': 'global f\nf: ret\ncall f\njmp f\njz f\n',
 'elf_call_global_fwd': 'call f\njmp f\nglobal f\nf: ret\n',
 'elf_rel_other_section': 'section .data\ny: dd 0\nsection .text\nlea rax, [rel y]\n',
 # equ: constants, label differences, aliases, used before or after
 'elf_equ_diff_back': 'section .rodata\nx: db 1,2,3\nlen equ $ - x\nsection .text\nmov ecx, len\n',
 'elf_equ_diff_fwd': 'section .text\nmov ecx, len\nsection .rodata\nx: db 1,2,3\nlen equ $ - x\n',
 'elf_equ_const_fwd': 'mov ecx, len\nlen equ 7\n',
 'elf_equ_in_data': 'mov ecx, len\ndd len\nx: db 1,2,3\nlen equ $ - x\n',
 'elf_equ_alias_fwd': 'section .text\nmov eax, alias\nx: db 1\nsection .data\ny: dd 0\nalias equ y+4\n',
 'elf_equ_alias_back': 'section .data\ny: dd 0\nalias equ y+4\nsection .text\nmov eax, alias\nlea rax, [rel alias]\n',
 'elf_equ_small_fwd': 'mov ax, w\nmov al, b\nw equ 0xFFFF\nb equ -1\n',
 'elf_equ_forward_ref': 'mov ecx, len\nx: db 1,2,3\nlen equ y - x\ny:\n',
 # mov to a 16/8-bit register from a symbol: relocated
 'elf_mov_small_extern': 'extern w, b\nmov ax, w\nmov al, b\nadd ax, w\nmov word [rax], w\n',
 'elf_global_function': 'global f:function\n'
                        'global d:data\n'
                        'section .text\n'
                        'f: ret\n'
                        'section .data\n'
                        'd: dd 1\n',
 'elf_global_hidden': 'global f:function hidden\nsection .text\nf: ret\n',
 'elf_global_size': 'global f:function (f.end - f)\nsection .text\nf: nop\nnop\n.end:\n',
 'elf_common': 'common buf 64:8\nsection .text\nmov rax, buf\n',
 'elf_static': 'static s\nsection .text\ns: ret\n',
 'elf_wrt_plt': 'extern puts\nsection .text\ncall puts wrt ..plt\n',
 'elf_wrt_gotpcrel': 'extern v\nsection .text\nmov rax, [rel v wrt ..gotpcrel]\n',
 'elf_wrt_got': 'extern v\nsection .text\nmov rax, v wrt ..got\n',
 'elf_wrt_sym': 'extern v\nsection .data\ndq v wrt ..sym\n',
 'elf_extern_rel': 'extern v\nsection .text\nmov eax, [rel v]\ncall v\n',
 'elf_dq_label_diff': 'section .data\na: dd 1\nb: dq b - a\n',
 'elf_weak': 'weak w\nsection .text\nw: ret\n',
 'elf_default_rel': 'default rel\nsection .text\nmov eax, [x]\nsection .data\nx: dd 1\n',
 'elf_section_flags_str': 'section .foo progbits alloc write\ndd 1\n',
 'elf_local_sym_types': 'section .text\nf: ret\nsection .data\nd: dd 1\n',
 'elf_extern_in_data': 'extern e\nsection .data\ndd e\ndq e + 8\n',
 'elf_times_reloc': 'extern e\nsection .data\ntimes 2 dq e\n',
 'elf_note_gnu_stack': 'section .note.GNU-stack noalloc noexec nowrite progbits\n',
 'elf_abs_symbol': 'A equ 5\nglobal A\nsection .text\nnop\n',
 'elf_jmp_extern': 'extern e\nsection .text\njmp e\njz e\n'}

# data directives, strings, floats and incbin, one program each (-f bin)
DATA_CASES = ['db "a\\n"',
 'db `a\\n\\101\\x4\\u00e9`',
 'db `\\x41\\x`',
 'db `tab\\there\\0end`',
 'db `q\\`\\x27\\"`',
 'db `\\U0001F600`',
 'db `\\e\\a\\b\\f\\v\\r`',
 'db \'x\', "it\'s", `y`',
 "dw 'abc'",
 'dd "abcde"',
 "dq 'a'",
 "dd 'ab', 'cdefg'",
 'dq "abcdefghijk"',
 'dw `a\\0`',
 "db 'a'+1, 'bc'",
 'dd 1.5',
 'dq 3.25',
 'dq -0.5',
 'dd 1.0e3',
 'dd 1e3',
 'dq 2E-1',
 'dw 1.5',
 'dt 1.5',
 'dt -2.75',
 'dt 0.1',
 'dq 0.1',
 'dd 0.1',
 'dw 0.1',
 'dq 1e300',
 'dq 1e-300',
 'dq 4.9e-324',
 'dq 2.2250738585072014e-308',
 'dq 1.7976931348623157e308',
 'dq 1e309',
 'dd 3.4028235e38',
 'dd 1e39',
 'dd 1.4e-45',
 'dd 1e-46',
 'dw 65504.0',
 'dw 6.0e-8',
 'dt 1e4932',
 'dt 3.6e-4951',
 'dq 123456789012345678901234567890.0',
 'dq 0.30000000000000004',
 'dq 9007199254740993.0',
 'dq 2.5, -1.25, 100.0',
 'dd -0.0',
 'dq 0.0',
 'dd 0x1.8p1',
 'dq 0x1p-1074',
 'dd 1.',
 'dd __float32__(1.5)',
 'dq __float64__(-2.5)',
 'dw __float16__(0.1)',
 'mov eax, __float32__(2.0)',
 'mov eax, 1.5',
 'dt 5',
 'do -1',
 'rest 1',
 'resz 1',
 'reso 2\ndb 1',
 'resy 1\ndb 2',
 "do 'abc'",
 'incbin "inc.bin"',
 'incbin "inc.bin", 6',
 'incbin "inc.bin", 6, 5',
 "incbin 'inc.bin', 1, 2",
 'db 1\nincbin "inc.bin", 0, 3\ndb 2',
 'incbin "missing.bin"']

# section headers of an ELF object: name, type, size, flags
SECTION_CASES = ['section .x\n nop\n',
 'section .data\n dd 1\n',
 'nop\nsection .data\n dd 1\n',
 'section .text\n nop\nsection .data\n dd 1\nsection .bss\n resb 4\nsection .rodata\n db 1\n',
 'section .text\nsection .data\n dd 1\n',
 'section .data\n align 16\n dd 1\n',
 'section .text align=64\n nop\n',
 'section .x progbits alloc exec nowrite align=16\n nop\nsection .x\n nop\n',
 'global f\nsection .data\nf: dd 1\nsection .text\n',
 'extern g\nsection .data\n dq g\n',
 'nop\nsection .data\n dd 1\nsection .bss\n resb 1\n',
 'nop\nsection .x\n db 1\nsection .data\n dd 1\n',
 'section .x\n db 1\nsection .text\n nop\nsection .data\n dd 1\n',
 'nop\nsection .data\n dd 1\nsection .text\n nop\nsection .x\n db 1\n',
 'section .x\n db 1\nsection .rodata\n db 2\nsection .bss\n resb 1\nsection .data\n db 3\n',
 'start:\nsection .data\n dq start\n']

# operand shapes: the general-purpose instructions with every pairing of
# register and memory sizes; NASM's verdict (bytes, or an error) is the
# reference, so the cases NASM rejects count too
SHAPE_OPS = ["mov", "add", "adc", "sub", "cmp", "test", "xchg", "xadd", "cmpxchg",
             "bsf", "popcnt", "lzcnt", "imul", "cmovz", "movbe", "bt", "bts",
             "shld", "andn", "movsx", "movzx", "movsxd", "crc32", "lar", "lsl",
             "adcx", "in", "out"]
SHAPE_REGS = {8: "bl", 16: "bx", 32: "ebx", 64: "rbx"}
SHAPE_SRC = {8: "r9b", 16: "r9w", 32: "r9d", 64: "r9"}
SHAPE_MEM = {0: "[rbx]", 8: "byte [rbx]", 16: "word [rbx]", 32: "dword [rbx]", 64: "qword [rbx]"}


def shape_lines():
    out = []
    for op in SHAPE_OPS:
        for a in SHAPE_REGS:
            for b in SHAPE_SRC:
                out.append("%s %s, %s" % (op, SHAPE_REGS[a], SHAPE_SRC[b]))
            for m in SHAPE_MEM.values():
                out.append("%s %s, %s" % (op, SHAPE_REGS[a], m))
                out.append("%s %s, %s" % (op, m, SHAPE_REGS[a]))
            out.append("%s %s, %s, %s" % (op, SHAPE_REGS[a], SHAPE_SRC[a], "[rbx]"))
            out.append("%s %s, %s, cl" % (op, SHAPE_REGS[a], SHAPE_SRC[a]))
            out.append("%s %s, %s, 3" % (op, SHAPE_REGS[a], SHAPE_SRC[a]))
        out += ["%s al, cl" % op, "%s rax, cl" % op, "%s al, dx" % op, "%s ax, dx" % op,
                "%s eax, dx" % op, "%s dx, al" % op, "%s dx, eax" % op, "%s al, 5" % op,
                "%s 5, al" % op, "%s rbx, 5" % op, "%s bx, 5" % op]
    return out


# diagnostics: sources NASM rejects; utasm must reject them too and report
# the first error at the same file and line. A case is the main source, or
# a dict of file name -> text with the main source under "main.s".
DIAG_CASES = [
    ("unknown instruction", "mov eax, 1\nfoo eax\nnop\n"),
    ("unclosed bracket", "mov eax, 1\nmov eax, [\nnop\n"),
    ("dangling operator", "nop\nmov eax, 1 +\n"),
    ("macro arity", "%macro m 2\nnop\n%endmacro\nm 1\n"),
    ("operand sizes", "nop\nmov al, rax\n"),
    ("operand kinds", "nop\nnop\nbsf [rbx], bx\n"),
    ("include missing", "nop\n%include \"nofile.inc\"\n"),
    ("include name", "%include nofile\n"),
    ("label redefined", "nop\ndb 1\nx: nop\nx: nop\n"),
    ("%error", "nop\n%error custom message\nnop\n"),
    ("%fatal", "nop\n%fatal stop here\nnop\n"),
    ("%error then more", "%error first\nnop\nfoo\n"),
    ("undefined symbol", "nop\njmp nowhere\n"),
    ("global undefined", "global foo\nnop\ncall foo\n"),
    ("undefined in data", "extern foo\ncall foo\nbar: dq baz\n"),
    ("undefined in macro", "%macro m 0\n call missing\n%endmacro\nnop\nm\n"),
    ("error in macro", "%macro m 0\nnop\nfoo\n%endmacro\nnop\nm\n"),
    ("error in %rep", "%rep 2\nnop\nmov al, bx\n%endrep\n"),
    ("error in include", {"main.s": "nop\n%include \"part.inc\"\nnop\n",
                          "part.inc": "nop\nnop\nmov al, rax\n"}),
    ("after include", {"main.s": "%include \"part.inc\"\nnop\nfoo\n",
                       "part.inc": "nop\n"}),
]


# the command line: NASM's options, each run with NASM and with utasm on
# the same files. (name, arguments, what is compared: "bin" the flat
# binary, "deps" the -M output, "pp" -E output assembled again)
CLI_FILES = {
    "main.s": 'bits 64\n%include "defs.inc"\n%ifdef FAST\nmov eax, VAL\n%else\nnop\n%endif\n'
              'incbin "data.bin"\nmsg: db "hi", 0\n',
    "inc/defs.inc": "times 2 nop\n",
    "inc/data.bin": "XY",
    "pre.inc": "%define VAL 9\n%define FAST\n",
    "long.s": '%include "x.inc"\n%include "defs.inc"\nnop\n',
    "inc/a_rather_long_directory_name_for_wrapping/x.inc": "nop\n",
    "pp.s": 'bits 64\n%macro two 1\n mov eax, %1\n add eax, [rbx+%1]\n%endmacro\n'
            'lbl:  two 3\n%define N 4\ndd N*2, (N+1)\n%rep 2\n nop\n%endrep\n'
            'msg: db "hi", 0, `a\\tb`, "q\'s"\n',
}
CLI_CASES = [
    ("-I", ["-f", "bin", "main.s", "-Iinc"], "bin"),
    ("-I with a slash", ["-f", "bin", "main.s", "-I", "inc/"], "bin"),
    ("-D", ["-f", "bin", "main.s", "-Iinc", "-DFAST", "-DVAL=7"], "bin"),
    ("-d -U", ["-f", "bin", "main.s", "-Iinc", "-dFAST", "-dVAL=0x10", "-UFAST"], "bin"),
    ("--before", ["-f", "bin", "-Iinc", "--before", "%define FAST", "-DVAL=3", "main.s"], "bin"),
    ("-p", ["-f", "bin", "main.s", "-Iinc", "-p", "pre.inc"], "bin"),
    ("--include", ["-f", "bin", "main.s", "-Iinc", "--include", "pre.inc"], "bin"),
    ("-M", ["-M", "-f", "elf64", "-Iinc", "main.s"], "deps"),
    ("-M -MT -MP", ["-M", "-MT", "x", "-MP", "-Iinc", "main.s"], "deps"),
    ("-M -MQ", ["-M", "-f", "elf64", "-MQ", "y", "-Iinc", "main.s"], "deps"),
    ("-M long lines", ["-M", "-f", "elf64", "-Iinc", "-Iinc/a_rather_long_directory_name_for_wrapping", "long.s"], "deps"),
    ("-E", ["-f", "bin", "pp.s"], "pp"),
]


# DWARF line tables (-g): programs whose decoded line rows (file, line,
# address) must be NASM's
DWARF_FILES = {
    "inc.s": "    nop\n    add eax, 1\n",
}
DWARF_CASES = {
    "macro, include, loop":
        "global _start\nsection .text\n%macro exit 1\n    mov eax, 60\n    mov edi, %1\n"
        "    syscall\n%endmacro\n_start:\n    mov ecx, 3\n.loop:\n    call work\n"
        "    dec ecx\n    jnz .loop\n    exit 0\nwork:\n    %include \"inc.s\"\n    ret\n",
    "rep and times":
        "section .text\nf:\n%rep 2\n    nop\n    inc eax\n%endrep\n    times 3 nop\n    ret\n",
    "two code sections":
        "section .text\na: mov eax, 1\n    ret\nsection .init exec\nb: xor eax, eax\n    ret\n"
        "section .data\nd: dd 5\nsection .text\n    nop\n",
    "short jumps":
        "section .text\nl1: jmp l2\n    nop\nl2: jz l1\n    times 200 nop\n    jmp l1\n",
}


# -f elf32: i386 objects (contents, relocations with their in-place
# addends, symbols) and a program linked with ld -m elf_i386
ELF32_CASES = {
    "elf32_data_refs":
        "section .text\nmov eax, msg\nmov ecx, [msg+4]\nlea esi, [table+ebx*4]\npush msg\n"
        "section .data\nmsg: db 'hello', 0\ntable: dd 1, 2, msg, msg+3\n",
    "elf32_externs":
        "extern ext_fn, ext_var\nglobal f\nsection .text\nf: call ext_fn\nmov eax, [ext_var]\n"
        "mov eax, ext_var+8\njmp near ext_fn\ndw ext_var\ndb 0\nsection .data\np: dd f, ext_var, p+4\n",
    "elf32_local_branches":
        "global f\nsection .text\nf: call g\njmp f\njz h\ng: ret\nh: call f\nloop f\n",
    "elf32_bss_and_common":
        "section .text\nmov eax, [buf]\nmov [buf+4], ecx\ncommon cc 8\nmov eax, cc\nsection .bss\nbuf: resb 16\n",
    "elf32_mixed_bits":
        "section .text\nbits 16\nmov ax, word_v\nbits 32\nmov eax, word_v\npush word 5\n"
        "section .data\nword_v: dw 7\n",
    "elf32_equ_and_sizes":
        "global main:function\nsection .text\nmain: mov eax, len\nret\n.end:\nsection .rodata\n"
        "s: db 'abc'\nlen equ $ - s\n",
}
ELF32_HELLO = (
    "global _start\nsection .text\n_start:\n    mov eax, 4\n    mov ebx, 1\n    mov ecx, msg\n"
    "    mov edx, len\n    int 0x80\n    call done\ndone:\n    mov eax, 1\n    mov ebx, 42\n    int 0x80\n"
    "section .data\nmsg: db 'elf32', 10\nlen equ $ - msg\n"
)

# ---------------------------------------------------------------------------
# expressions: labels defined later in arithmetic (worked out at the end) and
# NASM's rule that a label is an address, not a scalar
# ---------------------------------------------------------------------------
_T = "\nl1: dd 1, 2\nl2:\nl3: dw 7\nl4:\n"           # l2 - l1 = 8, l4 - l3 = 2
EXPR_BIN = {
    "div": "bits 32\ndd (l2 - l1) / 4" + _T,
    "shr": "bits 32\ndw (l2 - l1) >> 1" + _T,
    "mul_add": "bits 32\ndd (l2 - l1) * 2 + 1" + _T,
    "neg": "bits 32\ndd -(l2 - l1)" + _T,
    "not": "bits 32\ndd ~(l2 - l1)" + _T,
    "db_mul": "bits 32\ndb (l2 - l1) * 2" + _T,
    "db_distance": "bits 32\ndb l2 - l1, l2 - $$" + _T,
    "dq_shl": "bits 32\ndq (l2 - l1) << 3" + _T,
    "sum_of_diffs": "bits 32\ndd ((l2 - l1) + (l4 - l3)) / 2" + _T,
    "diff_of_diffs": "bits 32\ndd (l2 - l1) - (l4 - l3)" + _T,
    "mod": "bits 32\ndd (l2 - l1) % 3" + _T,
    "cmp": "bits 32\ndb ((l2 - l1) == 8), ((l2 - l1) < 4)" + _T,
    "ternary": "bits 32\ndd (l2 - l1) > 4 ? 10 : 20" + _T,
    "items": "bits 32\ndd (l2 - l1) / 4, (l4 - l3) * 3, 5" + _T,
    "and_or": "bits 32\ndd ((l2 - l1) | 0x100) & 0xFFF" + _T,
    "number_minus": "bits 32\norg 0x100\ndd 0x500 - l1" + _T,
    "dollar": "bits 32\ndd (l2 - $) / 4" + _T,
    "dollar2": "bits 32\nnop\ndd (l2 - $$) / 2" + _T,
    "mov_imm": "bits 32\nmov eax, (l2 - l1) / 4" + _T,
    "mov_imm64": "bits 64\nmov rax, (l2 - l1) * 3" + _T,
    "mem_disp": "bits 64\nmov eax, [rbx + (l2 - l1) * 32]" + _T,
    "push_imm": "bits 32\npush dword (l2 - l1) / 4" + _T,
    "local": "bits 32\nf:\ndd (.e - .s) / 4\n.s: dd 1, 2, 3\n.e:\n",
    "local_after": "bits 32\nf:\ndd (.e - .s) / 4\n.s: dd 1, 2, 3\n.e:\ng:\n.s: dd 9\n.e:\n",
    "macro_local": "bits 32\n%macro tbl 0\ndd (%%e - %%s) / 4\n%%s: dd 1, 2\n%%e:\n%endmacro\ntbl\ntbl\n",
    "in_rep": "bits 32\n%assign i 0\n%rep 3\ndd (e%[i] - s%[i]) / 4\ns%[i]: times i+1 dd 0\ne%[i]:\n"
              "%assign i i+1\n%endrep\n",
    "jump_shrinks": "bits 32\ndd (le - ls) / 1\nls: jmp lt\nlt: nop\nle:\n",
    "jumps_between": "bits 64\ndw (le - ls) * 2\nls:\n" + "".join("jz e%d\nnop\ne%d:\n" % (i, i) for i in range(20)) + "le:\n",
    "define": "bits 32\n%define SZ ((l2 - l1) / 4)\ndd SZ, SZ * 2" + _T,
    "fn_define": "bits 32\n%define CNT(a, b) (((b) - (a)) / 4)\ndd CNT(l1, l2)" + _T,
    "backward_too": "bits 32\nl0: dd 0\ndd (l2 - l0) / 4" + _T,
    "global_first": "bits 32\nglobal x, y\ndd (y - x) / 2\nx: dd 1\ny:\n",
}
EXPR_ELF = {
    "elf_data": "section .data\ndd (l2 - l1) / 4\nl1: dd 1, 2\nl2:\n",
    "elf_text": "section .text\nmov eax, (l2 - l1) / 4\nl1: dd 1, 2\nl2:\n",
    "elf_two_items": "section .data\ndq (l2 - l1) * 8, (l2 - l1)\nl1: dd 1, 2\nl2:\n",
}
# NASM, which reads the source again, takes these; utasm cannot (the value
# is needed when the line is read): an error, never a wrong value
EXPR_REJECT = {
    "times_count": "bits 32\ntimes (l2 - l1) / 4 db 0" + _T,
    "resb_count": "bits 32\nsection .bss\nresb (l2 - l1) / 4\nsection .text" + _T,
    "equ_before": "bits 32\nn equ (l2 - l1) / 4\ndd n" + _T,
}
# each with the label defined before and after it, as bin and elf64
SCALAR_EXPRS = ["l1 * 2", "2 * l1", "-l1", "~l1", "!l1", "l1 | 1", "l1 ^ 1", "l1 & 0xff",
                "l1 >> 1", "l1 << 2", "l1 / 2", "l1 %% 2", "l1 < 2", "l1 <=> 1", "l1 == l1",
                "l1 && 1", "l1 || 0", "l1 + l1", "2 - l1", "+l1", "l1 - l1", "l1 ? 1 : 2",
                "(l1 - $$) >> 1"]


# ---------------------------------------------------------------------------
# limits: inputs past utasm's old fixed limits (name -> source, files, format)
# ---------------------------------------------------------------------------
def limit_cases():
    nl = lambda lines: "\n".join(lines) + "\n"
    long = "x" * 700
    c = {
        "times_line_300_items": ("times 3 db " + ", ".join(str(i % 256) for i in range(300)) + "\n", {}, "bin"),
        "times_db_string": ("times 1000 db 'ab'\n", {}, "bin"),
        "ifidn_long": (nl(["%%ifidn %s, %s" % (long, long), "db 1", "%else", "db 2", "%endif"]), {}, "bin"),
        "ifidn_long_differ": (nl(["%%ifidn %sA, %sB" % (long, long), "db 1", "%else", "db 2", "%endif"]), {}, "bin"),
        "defstr_long": (nl(["%defstr S " + " ".join(["w"] * 1500), "db S"]), {}, "bin"),
        "utf16_long": ("db __utf16__('" + "u" * 10000 + "')\n", {}, "bin"),
        "macro_40_params": (nl(["%macro m 40", "db %1, %20, %40", "%endmacro",
                                "m " + ", ".join(str(i) for i in range(1, 41))]), {}, "bin"),
        "macro_100_params": (nl(["%macro m 100", "db %1, %50, %100, %0", "%endmacro",
                                 "m " + ", ".join(str(i % 256) for i in range(1, 101))]), {}, "bin"),
        "macro_varargs_200": (nl(["%macro m 1-*", "%rep %0", "db %1", "%rotate 1", "%endrep", "%endmacro",
                                  "m " + ", ".join(str(i % 256) for i in range(200))]), {}, "bin"),
        "macro_body_2000_tokens": (nl(["%macro m 0"] + ["db 1, 2, 3, 4, 5, 6, 7, 8, 9, 10"] * 100
                                      + ["%endmacro", "m", "m"]), {}, "bin"),
        "macro_arg_500_tokens": (nl(["%macro m 1", "db %1", "%endmacro", "m " + "+".join(["1"] * 250)]), {}, "bin"),
        "macro_nest_100": (nl(["%%macro m%d 0\nm%d\n%%endmacro" % (i, i + 1) for i in range(100)]
                              + ["%macro m100 0\ndb 7\n%endmacro", "m0"]), {}, "bin"),
        "macro_recursion_200": (nl(["%assign n 0", "%rmacro r 0", "db n", "%assign n n+1", "%if n < 200", "r",
                                    "%endif", "%endmacro", "r"]), {}, "bin"),
        "rotate_100": (nl(["%macro m 1-*", "%rotate 60", "db %1", "%endmacro",
                           "m " + ", ".join(str(i) for i in range(100))]), {}, "bin"),
        "define_1000_tokens": (nl(["%define D " + " + ".join(["1"] * 500), "dd D"]), {}, "bin"),
        "define_nest_200": (nl(["%define D0 1"] + ["%%define D%d (D%d + 1)" % (i, i - 1) for i in range(1, 200)]
                               + ["dd D199"]), {}, "bin"),
        "interp_long": (nl(["%%define %s1 5" % ("p" * 300), "%assign k 1", "db %s%%[k]" % ("p" * 300)]), {}, "bin"),
        "rep_body_3000_tokens": (nl(["%rep 3"] + ["db 1, 2, 3, 4, 5, 6, 7, 8, 9, 10"] * 150 + ["%endrep"]), {}, "bin"),
        "push_100": (nl(["%%push c%d" % i for i in range(100)] + ["%pop"] * 100 + ["db 1"]), {}, "bin"),
        "if_nest_300": (nl(["%if 1"] * 300 + ["db 1"] + ["%endif"] * 300), {}, "bin"),
        "parens_3000": ("dd " + "(" * 3000 + "1" + ")" * 3000 + "\n", {}, "bin"),
        "line_10000_chars": ("db " + ", ".join(["1"] * 3400) + "\n", {}, "bin"),
        "sections_300_elf64": (nl(["section s%d\ndb %d" % (i, i % 256) for i in range(300)]), {}, "elf64"),
        "sections_300_elf32": (nl(["section s%d\ndb %d" % (i, i % 256) for i in range(300)]), {}, "elf32"),
    }
    inc = {"i%d.inc" % i: "db %d\n%%include \"i%d.inc\"\n" % (i % 256, i + 1) for i in range(300)}
    inc["i300.inc"] = "db 0\n"
    c["include_nest_300"] = ('%include "i0.inc"\n', inc, "bin")
    return c


# ---------------------------------------------------------------------------
# robustness: inputs that crashed or hung utasm (found by scripts/compat/
# fuzz.py, cut down): utasm must finish, without an internal error, and
# accept or reject each as NASM does. (name, source, format, options)
# ---------------------------------------------------------------------------
ROBUST_CASES = [
    ("percent_name_operand", "mov rax, %e\n", "elf64", ["-g"]),
    ("percent_name_data", "%defstr S hello wor\ndb S %a\n", "elf64", []),
    ("percent_name_mem", "addss xmm2, [ %a\n", "elf64", ["-g"]),
    ("percent_name_default", "bits 64\ndefault %s\n", "elf64", []),
    ("percent_name_line_start", "%foo bar\ndb 1\n", "bin", []),
    ("strlen_no_name", "%strlen\n", "bin", []),
    ("strlen_no_string", "%strlen x\n", "bin", []),
    ("substr_no_name", "%substr : qword j\n", "bin", ["-l", "x.lst"]),
    ("colon_operand", "dq 1 + :\n", "elf64", ["-g"]),
    ("colon_after_wrt", "dq ..plt + :\n", "elf64", []),
    ("section_no_name", "section\ndb 1\n", "elf64", []),
    ("section_no_name_bracket", "[section]\ndb 1\n", "elf32", []),
    ("push_trailing_section", "%push qword segment\n", "elf32", []),
    ("runaway_recursion", "%assign n 0\n%rmacro r 0\ndb 1, 2, 3, 4, 5, 6, 7, 8, 9, 10\ndb n\n%assign n n+1\n"
                          "%if n < 200\n%endif\nr\n%endmacro\nr\n", "elf64", []),
    ("runaway_recursion_listed", "%rmacro r 0\ndb 1, 2, 3\nr\n%endmacro\nr\n", "elf64", ["-l", "x.lst"]),
]


# ---------------------------------------------------------------------------
# addresses: base, index and scale in every order NASM takes ([rbx+rcx*4],
# [4*rcx+rbx], [rbx*1+rcx], [rax+rax*3], [rbx*3], ...), with displacements
# and labels, in bits 64, 32 and 16, and vector indexes. (bits, line)
# ---------------------------------------------------------------------------
def address_forms():
    def forms(regs, scales, disps):
        out = set()
        for b in regs:
            for d in disps:
                out.add("[lbl+%s]" % b if d == "lbl+" else "[%s%s]" % (b, d))
                d = "" if d == "lbl+" else d
                for s in scales:
                    out.add("[%s*%s%s]" % (b, s, d))
                    out.add("[%s*%s%s]" % (s, b, d))
                for i in regs:
                    for s in ["", "*1", "*2", "*4", "*8", "*3"]:
                        out.add("[%s+%s%s%s]" % (b, i, s, d))
                        if s:
                            out.add("[%s*%s+%s%s]" % (s[1:], i, b, d))
                            out.add("[%s%s+%s%s]" % (i, s, b, d))
                            out.add("[%s+%s*%s%s]" % (b, s[1:], i, d))
        return sorted(out)
    disps = ["", "+8", "-8", "+0x1000", "+lbl", "lbl+"]
    jobs = [("bits 64", "lea eax, " + f) for f in
            forms(["rax", "rsp", "rbp", "r12", "r13", "rbx"], ["1", "2", "3", "4", "5", "8", "9", "6"], disps)]
    jobs += [("bits 64", "lea eax, " + f) for f in forms(["eax", "esp", "ebp", "r13d"], ["1", "2", "3", "4", "8"], disps)]
    jobs += [("bits 32", "lea eax, " + f) for f in
             forms(["eax", "esp", "ebp", "ebx", "esi"], ["1", "2", "3", "4", "8", "9"], disps)]
    jobs += [("bits 16", "lea ax, " + f) for f in forms(["bx", "bp", "si", "di"], ["1", "2"], disps)]
    for v, dst in (("xmm1", "xmm0"), ("ymm2", "ymm0")):
        for b in ["rax", "rbp", "r13", ""]:
            for s in ["", "*4", "4*", "*8", "*1", "1*"]:
                idx = s + v if s.endswith("*") else v + s
                for f in ("[%s%s+16]" % (b + "+" if b else "", idx), "[%s%s]" % (idx, "+" + b if b else "")):
                    jobs.append(("bits 64", "vgatherdps %s, %s, %s" % (dst, f, dst.replace("0", "5"))))
    return jobs


# %+ outside a macro body, each side first as the %define / %assign it names
BIN_PROBES.update({
    "pp_paste_define_rhs": "%define C cd\n%define abcd 7\ndb ab %+ C\n",
    "pp_paste_chain": "db 1 %+ 2 %+ 3\n",
    "pp_paste_assign": "%assign x 3\ndb x %+ 4\n",
    "pp_paste_label": "foo %+ bar:\ndb 5\njmp foobar\n",
    "pp_paste_define_chain": "%define Q P\n%define P ab\n%define abcd 9\ndb Q %+ cd\n",
    "pp_paste_fn_define": "%define J(a,b) a %+ b\n%define xy 6\ndb J(x,y)\n",
    "pp_paste_in_macro": "%macro m 0\n%define P ab\n%define abcd 9\ndb P %+ cd\n%endmacro\nm\n",
    "ins_mem_scale_first": "lea eax, [8*rcx+rbx]\nlea eax, [rbx+4*rcx+16]\nlea eax, [16+4*rcx]\nlea eax, [3*rbx]\n",
    "ins_mem_scale_one": "lea eax, [rbx*1]\nlea eax, [rbx*1+rcx]\nlea eax, [rax+rax*3]\nlea eax, [2*rbx*2]\n",
})
