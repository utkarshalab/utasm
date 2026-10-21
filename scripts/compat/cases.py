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
 'pp_ifdef_mline': '%macro mm 0\nnop\n%endmacro\n%ifdef mm\ndb 1\n%else\ndb 2\n%endif\n',
 # NASM 2.15/2.16 single-line macro parameters: =eval (radix, unsigned),
 # &string, &&string-unless-one, x+ greedy, empty ones, overloads by count
 'pp_def_eval': '%define tonum(=x) x\ndd tonum(1+3), tonum(5*7)\n',
 'pp_def_radix': '%define h(=x/x) x\n%define u(=x/u) x\n%define b(=x/b) x\ndd h(255), u(-1), b(5)\n',
 'pp_def_str': '%define s(&x) x\n%define q(&&x) x\ndb s(abc), q("z"), q(w)\n',
 'pp_def_greedy': '%define g(a,b,c+) a + 66 %, b * 3 %, c\ndb g(1,2)\ndb g(1,2,3,4,5)\n',
 'pp_def_overload': '%define f(x) 1\n%define f(x,y) 2\n%define f(x) 3\ndb f(a), f(a,b)\n',
 'pp_def_empty_param': '%define e(foo,) foo + 1\n%define m() 7\ndb e(2,3), m()\n',
 'pp_def_func_name': '%define bar(x) (x*2)\ndb bar(4)\nbar equ 3\ndb bar\n',
 'pp_cond_comma': '%define g(a,c+) [a %, c]\nmov eax, g(rbx)\nmov eax, g(rbx, rcx)\n',
 'pp_map_groups': '%define bar(=x,y) (x*y)\ndw %map(bar::2,1+2,3+4,5+6,7+8)\n',
 'pp_map_join': "%define join(sep) ''\n%define _join(sep,str) sep,str\n"
                "%define join(sep,s1,sn+) %strcat(s1, %map(_join:(sep) %, sn))\n"
                "db join(':')\ndb join(':','a')\ndb join(':','a','b','c')\n",
 'pp_rep_nolist': '%rep .nolist 2\nnop\n%endrep\n%macro m 0-1.nolist\n%rep %1 1\nret\n%endrep\n%endmacro\nm\nm .nolist\n',
 'pp_if_trailing': '%if 0\ndb 4\n%else trailing\ndb 5\n%elif 1\ndb 6\n%endif junk\n',
 'pp_ctx_paste': '%macro m 1\n%push c\n%define %$n %1\n%%top_%$n:\nx_%$n: dd %{$n}_end - x_%$n\n%{$n}_end:\n%pop\n%endmacro\nm abc\n',
 'pp_ctx_assign_paste': '%push c\n%assign %$i 0\n%rep 3\n%assign %$v%$i %$i*2\nmov ecx, %$v%$i\n%assign %$i %$i+1\n%endrep\n%pop\n',
 'pp_ctx_label_macro': '%macro m 0\nnop\n%endmacro\n%push c\n%$x m\n%pop\n',
 'pp_cc_params': '%macro j 1\n.l_%+1: j%-1 .l_%+1\n%endmacro\nj z\nj ae\n',
 'pp_interp_paste': '%use altreg\n%assign n 2\n%define g_b b\n%define g_q\nmov eax, %[r %+ n %+ d]\nmov rax, %[r %+ n %+ g_q]\n',
 'data_dup': 'db 6 dup (33, 34), 35\ndb %(44,55), %(\'XX\')\ndw 3 dup (0xcc, 2 dup byte (\'PQ\'), ?), 0xabcd\n'
             'db 7 dup dword (?, word ?, ?)\ndd 4 dup (?)\n',
 'num_radix_rules': 'db 0h, 0x, 0b, 0dh, 0bh, 0dx, 0bx\ndd $1e+16, 1e16h, 1_0e16, 1e1_6\n',
 'num_radix_floats': 'dd 0d3.7282705e+4, 0x1.23456789p+15, 0q1.10642547422p+15\n'
                     'dd 0b1.0010_0011_0100_0101_0110_0111_1000_1001p+15\n',
 'enc_prefixes': '{rex} add eax, edx\n{rex} add al, dl\n{vex} vcomisd xmm0, xmm1\n{vex3} vcomisd xmm0, xmm1\n'
                 '{evex} vcomisd xmm0, xmm1\n',
 'enc_latevex': 'vpmadd52luq ymm3, ymm1, [rsi]\n{vex} vpmadd52luq ymm3, ymm1, [rsi]\ncpu latevex\n'
                'vpmadd52luq ymm3, ymm1, [rsi]\ncpu default\ncpu noevex\nvpmadd52luq ymm3, ymm1, [rsi]\n',
 'enc_amx': 'ldtilecfg [rsi]\ntilezero tmm1\ntileloadd tmm2, [rax,rdx*2]\ntileloadd tmm2, [rax]\n'
            'tdpbf16ps tmm1, tmm2, tmm3\ntilestored [rax+rdx], tmm1\ntilerelease\n',
 'enc_fp16': 'vaddph zmm1, zmm2, zmm3\nvaddph zmm1{k1}{z}, zmm2, [rax]\nvfmaddcph xmm1, xmm2, xmm3\n'
             'vcvtph2psx zmm1, ymm2\nvmovw xmm1, [rax]\n',
 'enc_xop_fma4': 'vfmaddps xmm1, xmm2, xmm3, xmm4\nvprotb xmm1, xmm2, xmm3\nvpcmov xmm1, xmm2, xmm3, xmm4\n',
 'enc_two_operand_avx': 'vaddps xmm1, xmm3\nvaddps zmm1{k1}, zmm3\nvpcmpeqb xmm1, [rax]\n',
 'enc_vcmp_alias': 'vcmpeq_ospd xmm1, xmm2, xmm3\nvcmpfalse_oqpd k1, zmm2, zmm3\n',
 'enc_kmov_sized': 'kmov byte k1, k2\nkmov k1, word [rax]\nkmov k1, eax\nkadd k1, dword k2, k3\nkmovb k1, dl\n',
 'enc_split_ea': 'mov eax, [rax,rcx*4]\nmov eax, [rax+8,rcx]\n',
 'enc_size_prefixes': 'osp rdfsbase rax\nclzero eax\nretw\nxcryptecb\npextrw rax, xmm0, 1\nmovd r8, mm1\n',
 'enc_x87_forms': 'fadd\nfld\nfstp\nffreep\nfadd to st1\nfsubr to st2\n',
 'struc_base_offset': 'struc s, -40\n.l: resd 1\n.w: resw 1\nendstruc\nmov [rbp + s.w], ax\n'
                      'istruc s\nat .w, db 5\niend\ndd s_size, s\n',
 'ptr_as_label': 'mov eax, dword ptr\nptr:\n',
 # a number pasted on a name: NASM expands the name ("%define v 9": 19)
 'pp_param_number_paste': '%define v 9\n%macro m 1\ndb %{1}v\nx%{1}v: db 0\ndb %1h\n%endmacro\nm 1\n',
 # a context-local %define standing alone keeps its tokens (a string)
 'pp_ctx_deftok': '%push c\n%define %$r "ax  "\n%substr %$q %$r 1, 2\n%deftok %$q %$q\nmov eax, %$q\n%pop\n',
 # "at .x": the istruc's structure's field, whatever label came last (NASM 2.16)
 'istruc_local_fields': 'struc S1\n.d: resd 1\n.w: resw 1\nendstruc\nstruc S2\n.w: resw 1\n.d: resd 1\nendstruc\n'
                        'istruc S1\nat .d, dd 1\nat .w, dw 2\niend\nlab:\nistruc S2\nat .w, dw 3\nat .d, dd 4\niend\n'}

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
# binary, "deps" the -M output, "pp" -E output assembled again, "ppt" the
# -E text itself)
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
# the value needed when the line is read, a label defined later: pass 1
# goes on without it, pass 2 knows it (an equ: worked out once the code is
# laid out - parser_late_equs)
EXPR_BIN.update({
    "times_count": "bits 32\ntimes (l2 - l1) / 4 db 0" + _T,
    "resb_count": "bits 32\nsection .bss\nresb (l2 - l1) / 4\nsection .text" + _T,
    "equ_before": "bits 32\nn equ (l2 - l1) / 4\ndd n" + _T,
    "equ_later_imm8": "bits 64\nadd ecx, len\nx: db 1,2,3\nlen equ y - x\ny:\n",
    "equ_later_chain": "bits 64\nmov eax, a\na equ b + 1\nb equ y - x\nx: times 5 nop\ny:\nadd eax, a\n",
    "equ_later_chain_rev": "bits 64\nadd eax, a\nb equ a * 2\na equ y - x\nx: nop\ny:\nadd eax, b\n",
    "equ_later_disp8": "bits 64\nmov eax, [rbx + len]\nlen equ y - x\nx: times 10 nop\ny:\n",
    "equ_later_jumps": "bits 64\nadd ecx, len\nlen equ y - x\nx: jmp z\ntimes 122 nop\nz: nop\ny:\n",
    "equ_later_const": "bits 64\nmov eax, [rbx + off]\noff equ base + 8\nbase equ 16\n",
    "equ_used_before": "bits 64\nmov eax, x\nmov ebx, k\nx equ k + 1\nk equ 3\n",
    "equ_later_alias": "bits 64\ndq p\np equ y\nsection .data\ny: dd 1\n",
    "times_later_labels": "bits 64\ntimes y - x nop\nx: db 1,2\ny:\n",
    "resb_later_equ": "bits 64\nsection .bss\nresb n\nn equ 3\nresb 1\n",
})
EXPR_ELF.update({
    "elf_equ_later": "section .text\nadd ecx, len\nlen equ y - x\nx: db 1,2,3\ny:\nmov eax, a\na equ len * 2\n",
    "elf_equ_later_alias": "section .text\ndq p\np equ y + 4\nsection .data\ny: dd 1, 2\n",
})
# lines whose encoding depends on the mode's address size (the count
# register, a16 / a32 / a64): the modes suite assembles them as bits 64, 32
# and 16
MODE_LINES = [
    "l: jcxz l", "l: jecxz l", "l: jrcxz l", "l: loop l", "l: loope l", "l: loopne l",
    "l: loop l, cx", "l: loop l, ecx", "l: loop l, rcx", "l: a16 loop l", "l: a32 jecxz l",
    "l: a16 jecxz l", "l: a32 jcxz l", "l: a64 loop l, ecx", "l: a16 loop l, ecx",
    "jecxz $ + 0x7f", "jcxz $ - 0x7e",
    "a32 movsb", "a16 movsb", "a64 movsb", "a32 rep movsd", "a16 stosb", "a32 lodsb", "a16 xlatb",
    "a32 xlatb", "a16 nop", "a32 nop", "a64 nop",
    "a32 mov al, [0]", "a16 mov al, [0]", "a32 mov eax, [0x10]", "a16 mov eax, [0x10]",
    "a32 mov rax, [0x10]", "a32 mov [0x20], al", "a32 lea eax, [0x10]", "a16 lea eax, [0x10]",
    "a32 add eax, [0x10]", "a16 add eax, [0x10]", "a32 inc dword [0x10]", "a16 mov ebx, [0x10]",
    "add eax, [word 0x10]", "add eax, [dword 0x10]",
]
# an equ that measures code jumps shorten: worked out once they are, so
# the jumps are as short as NASM makes them (it froze them before); a jump
# to a label alias defined later; resb of a name never defined
_J = "jz z\ntimes 100 nop\nz: nop\n"
EXPR_BIN.update({
    "measure_after_use": "bits 64\nstart:\n" + _J + "len equ $ - start\nadd ecx, len\nmov eax, len\n",
    "measure_before_after": "bits 64\nadd ecx, len\nstart:\n" + _J + "e:\nlen equ e - start\nsub ecx, len\n",
    "measure_times": "bits 64\nstart:\n" + _J + "len equ $ - start\ntimes len - 100 db 0\n",
    "measure_data": "bits 64\nstart:\n" + _J + "len equ $ - start\ndd len\n",
    "measure_boundary": "bits 64\nadd ecx, len\ns: jmp z\ntimes 124 nop\nz: nop\nlen equ $ - s\n",
    "measure_at_end": "bits 64\nadd ecx, len\nx: jmp z\ntimes 120 nop\nz: nop\ny:\nlen equ y - x\n",
    "alias_later_jump": "bits 64\njmp p\np equ y + 1\nnop\ny: nop\nnop\n",
})
EXPR_ELF.update({
    "elf_measure_macro": "section .text\n%macro f 0\n%%s: jz %%z\ntimes 100 nop\n%%z: nop\n"
                         "%%len equ $ - %%s\nadd ecx, %%len\n%endmacro\nf\nf\n",
    "elf_macro_locals": "section .text\n%macro f 0\n%%s: nop\n%endmacro\n%macro g 0\nnop\n%endmacro\n"
                        "%define D 1\nf\n%rep 2\nnop\n%endrep\ntimes 2 nop\ndb D\ng\nf\n",
})
# names never defined, or equs naming each other: an error, never a value
EXPR_REJECT = {
    "equ_undefined": "bits 64\nlen equ nothere + 1\nmov eax, len\n",
    "equ_circular": "bits 64\na equ b\nb equ a\nmov eax, a\n",
    "times_undefined": "bits 64\ntimes nothere nop\n",
    "resb_undefined": "bits 64\nsection .bss\nresb 2 * nothere\n",
    "data_undefined": "bits 64\ndd 2 * nothere\n",
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
        # file names in single quotes (eight characters or fewer lex as a
        # character constant)
        "include_single_quote": ("%include 'inc.inc'\n%include 'inc.inc'\ndb X\n",
                                 {"inc.inc": "%ifndef INCX\n%define INCX\nX equ 9\n%endif\n"}, "bin"),
        "pathsearch_single_quote": ("%pathsearch P 'inc.inc'\ndb P\n", {"inc.inc": "db 0\n"}, "bin"),
        "depend_single_quote": ("%depend 'inc.inc'\nnop\n", {"inc.inc": "db 0\n"}, "bin"),
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
    # %ifmacro with a parameter count (overloads, ranges); %iftoken; %?
    "pp_ifmacro_counts": "%macro m 1\n%endmacro\n%macro m 3\n%endmacro\n%macro v 2-*\n%endmacro\n%ifmacro m\ndb 0\n%endif\n%ifnmacro m\ndb 100\n%endif\n%ifmacro m 1\ndb 1\n%endif\n%ifnmacro m 1\ndb 101\n%endif\n%ifmacro m 2\ndb 2\n%endif\n%ifnmacro m 2\ndb 102\n%endif\n%ifmacro m 3\ndb 3\n%endif\n%ifnmacro m 3\ndb 103\n%endif\n%ifmacro m 0-1\ndb 4\n%endif\n%ifnmacro m 0-1\ndb 104\n%endif\n%ifmacro m 2-3\ndb 5\n%endif\n%ifnmacro m 2-3\ndb 105\n%endif\n%ifmacro m 4-*\ndb 6\n%endif\n%ifnmacro m 4-*\ndb 106\n%endif\n%ifmacro v 1\ndb 7\n%endif\n%ifnmacro v 1\ndb 107\n%endif\n%ifmacro v 5\ndb 8\n%endif\n%ifnmacro v 5\ndb 108\n%endif\n%ifmacro v 0-1\ndb 9\n%endif\n%ifnmacro v 0-1\ndb 109\n%endif\n%ifmacro v 1-2\ndb 10\n%endif\n%ifnmacro v 1-2\ndb 110\n%endif\n%ifmacro nope\ndb 11\n%endif\n%ifnmacro nope\ndb 111\n%endif\n%ifmacro nope 1\ndb 12\n%endif\n%ifnmacro nope 1\ndb 112\n%endif\n",
    "pp_iftoken": "%iftoken 1\ndb 1\n%endif\n%iftoken 1 2\ndb 2\n%endif\n%ifntoken\ndb 3\n%endif\n"
                  "%iftoken foo\ndb 4\n%endif\n",
    # a multi-line macro is called at the start of a line or after "label:"
    # only; elsewhere its name is a word (here a string, a label's macro)
    "pp_macro_after_label": "%macro mm 0\nnop\n%endmacro\nlab: mm\njmp lab\n",
    "pp_macro_name_defstr": "%macro mm 0\nnop\n%endmacro\n%defstr S mm\ndb S\n",
    "pp_macro_arg_is_macro": "%macro qq 0\nnop\n%endmacro\n%macro mm 1\ndb 1\n%endmacro\nmm qq\n",
    # %[...] standing alone: the tokens inside, expanded there and then
    "pp_brk_expr_define": "%define X 2+3\ndb %[X]*2\n",
    "pp_brk_now": "%assign i 1\n%define V 80+%[i]\n%assign i 5\ndb V\n",
    "pp_brk_list": "%define A 1, 2, 3\ndb %[A]\n",
    "pp_brk_string": "%define S 'ab'\ndb %[S], 0\n",
    "pp_brk_words": "%define M mov eax,\nbits 64\n%[M] 5\n",
    "pp_brk_empty": "%define E\ndb 1 %[E]\n",
    "pp_brk_nested": "%define Y 7\n%define X Y+1\ndb %[X]\n",
    "pp_brk_literal": "db %[2+3]\n",
    "pp_brk_rep": "%assign i 0\n%rep 3\ndb %[i]\n%assign i i+1\n%endrep\n",
    # NASM 2.16's preprocessor functions: their results, through %defstr
    "pp_fn_00": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %eval(-3)\ndb S\n",
    "pp_fn_01": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %eval(1+1, 2*3)\ndb S\n",
    "pp_fn_02": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %hex(255)\ndb S\n",
    "pp_fn_03": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %hex(-1)\ndb S\n",
    "pp_fn_04": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %num(42)\ndb S\n",
    "pp_fn_05": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %num(255, 4, 16)\ndb S\n",
    "pp_fn_06": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %num(5, 3)\ndb S\n",
    "pp_fn_07": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %num(-5)\ndb S\n",
    "pp_fn_08": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %num(255,,2)\ndb S\n",
    "pp_fn_09": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %num(7, -1, 8)\ndb S\n",
    "pp_fn_10": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %str(1+2)\ndb S\n",
    "pp_fn_11": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %str(a  b)\ndb S\n",
    "pp_fn_12": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %str('x')\ndb S\n",
    "pp_fn_13": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %str()\ndb S\n",
    "pp_fn_14": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %count()\ndb S\n",
    "pp_fn_15": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %count(a)\ndb S\n",
    "pp_fn_16": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %count(a, (b, c), d)\ndb S\n",
    "pp_fn_17": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %sel(2, a, b, c)\ndb S\n",
    "pp_fn_18": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %sel(5, a, b)\ndb S\n",
    "pp_fn_19": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %cond(1, x, y)\ndb S\n",
    "pp_fn_20": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %cond(0, x, y)\ndb S\n",
    "pp_fn_21": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %cond(0, x)\ndb S\n",
    "pp_fn_22": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %strcat('a', \"b\", 'cd')\ndb S\n",
    "pp_fn_23": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %strlen('')\ndb S\n",
    "pp_fn_24": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %substr('abcd', 2)\ndb S\n",
    "pp_fn_25": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %substr('abcd', 2, 2)\ndb S\n",
    "pp_fn_26": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %substr('abcd', -1)\ndb S\n",
    "pp_fn_27": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %tok('1+2')\ndb S\n",
    "pp_fn_28": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %isdef(FOO)\ndb S\n",
    "pp_fn_29": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %isnum(5)\ndb S\n",
    "pp_fn_30": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %isnum(x)\ndb S\n",
    "pp_fn_31": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %isstr('a')\ndb S\n",
    "pp_fn_32": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %isid(x)\ndb S\n",
    "pp_fn_33": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %isempty()\ndb S\n",
    "pp_fn_34": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %istoken(a b)\ndb S\n",
    "pp_fn_35": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %isidn(a, a)\ndb S\n",
    "pp_fn_36": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %isidni(A, a)\ndb S\n",
    "pp_fn_37": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %isn(0)\ndb S\n",
    "pp_fn_38": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %isndef(FOO)\ndb S\n",
    "pp_fn_39": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %ismacro(m)\ndb S\n",
    "pp_fn_40": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %is(2 > 1)\ndb S\n",
    "pp_fn_41": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %abs(-7)\ndb S\n",
    "pp_fn_42": "%define FOO\n%macro m 0\n%endmacro\n%defstr S %eval(%count(1,2))\ndb S\n",
    "pp_fn_map": "%define F(a) a*2\ndb %map(F, 1, 2)\n%define G(a,b) a+b\ndb %map(G:(10), 1, 2), 9, %map(F)\n",
    "pp_fn_in_code": "bits 64\n%define N 3\nmov eax, %eval(N * 4)\ndb %cond(%isdef(N), 1, 2), %sel(N, 7, 8, 9)\n%tok('nop')\n",
    "pp_defstr_quotes": "%defstr A 'x'\n%defstr B \"y\"\n%defstr C a 'b' c\ndb A, B, C\n",
    "pp_macro_name": "%macro mm 0\n%defstr S %?\ndb S\n%endmacro\nmm\n%macro nn 0\n%defstr T %??\ndb T\n%endmacro\nnn\n",
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


# ---------------------------------------------------------------------------
# warnings: NASM's warnings, with its -w options (name -> source)
# ---------------------------------------------------------------------------
WARN_CASES = {
    "warn_user": "%warning hello there\nnop\n",
    "warn_zeroing": "db 1\ndb ?\ndw ?, 5\ndd 1, ?\ntimes 3 db ?\nresb 2\ndt ?\ndq ?, ?\n"
                    "section .bss\ndb ?\nresb 4\nresb 64\n",
    "warn_section_attr": "section .a\ndb 1\nsection .b follows=.a\ndb 2\nsection .c vstart=0x1000\n"
                         "db 3\nsection .d start=0x2000\ndb 4\n",
    "warn_lock": "lock xchg eax, ebx\nlock xchg ebx, [rax]\nlock add eax, ebx\nlock mov [rax], eax\n"
                 "lock add [rax], ebx\nLOCK XCHG [rax], ebx\nlock cmpxchg [rax], ecx\n",
    "warn_overflow": "db 256, -257, 255, -256\ndw 65536, -65537\ndd 0x100000000, -0x100000001\n"
                     "mov al, 256\nmov ax, 65536\nmov eax, -0x100000001\nmov byte [rax], 256\n"
                     "mov dword [rax], 0x100000000\nadd al, 300\njmp short x\nmov ecx, -16 >> 2\nx: nop\n",
    "warn_in_macro": "%macro m 0\ndb ?\n%warning in macro\n%endmacro\nm\nm\n",
    "warn_two_pass": "%warning early\ndb ?\nmov eax, LATER\nLATER equ 5\n",
    "warn_then_error": "db ?\n%warning first\nmov eax, [rbx*2+rcx*2]\n",
}
WARN_OPTIONS = [[], ["-Werror"], ["-w-zeroing", "-w-user"], ["-w+error=zeroing"], ["-w-all"],
                ["-Wno-number-overflow"], ["-w+all"]]


# %macro / %unmacro headers and their errors; data lists
DIAG_CASES += [
    ("%macro without a count", "nop\n%macro s\nnop\n%endmacro\n"),
    ("%macro without a name", "nop\n%macro\n%endmacro\n"),
    ("%macro bad count", "%macro s x\n%endmacro\n"),
    ("%macro count after -", "nop\n%macro s 0-\n%endmacro\n"),
    ("%macro min over max", "%macro s 2-1\n%endmacro\n"),
    ("%rmacro without a count", "%rmacro s\n%endmacro\n"),
    ("%macro until the end", "nop\n%macro s 0\nnop\n"),
    ("%endmacro alone", "nop\n%endmacro\n"),
    ("%endm alone", "nop\nnop\n%endm\n"),
    ("%endrep alone", "nop\n%endrep\n"),
    ("%unmacro without a count", "%macro s 0\nnop\n%endmacro\n%unmacro s\n"),
    ("empty data item", "nop\ndb 1,,2\n"),
]
WARN_CASES.update({
    "warn_macro_defaults": "%macro s 0 junk\nnop\n%endmacro\ns\n%macro t 0-1 5,6\n%endmacro\n"
                           "%macro u 0-1 (5,6)\n%endmacro\n%macro v 1-* 5,6,7\n%endmacro\n",
    "warn_db_empty": "db\ndd\nnop\n",
})
BIN_PROBES.update({
    "pp_endm": "%macro s 0\nnop\n%endm\ns\ns\n",
    "pp_unmacro_overload": "%macro s 0\ndb 1\n%endmacro\n%macro s 1\ndb %1\n%endmacro\n%unmacro s 1\ns\n"
                           "%macro t 0-1\ndb 3\n%endmacro\n%unmacro t 0\nt\n"
                           "%macro u 1+\ndb 4\n%endmacro\n%unmacro u 1\nu 1\n",
    "pp_macro_empty_default": "%macro s 1-3 5\ndb %1, %2, %3\n%endmacro\ns 1\ns 1, 2\ns 1, 2, 3\n",
    "dir_data_trailing_comma": "db 1,\ndw 2, \ndd 3, 4,\ndq 5,\ndt 1.0,\ndb 'ab',\ntimes 2 db 6,\n",
})


# labels defined later, in instructions: the short forms NASM gives once it
# knows the value (the second pass, core/known.s)
EXPR_BIN.update({
    "distance_imm": "bits 64\nadd rsp, (l2 - l1)\nnop\nl1: times 16 db 0\nl2:\n",
    "distance_disp": "bits 64\nmov eax, [rbx + (l2 - l1)]\nl1: dd 1\nl2:\n",
    "distance_in_macro": "bits 64\n%macro m 0\npush (%%e - %%s)\n%%s: times 3 nop\n%%e:\n%endmacro\nm\nm\nm\n",
    "distance_and_equ": "bits 64\nmov eax, LATER\nLATER equ 5\npush (l2 - l1)\nl1: nop\nl2:\n",
    "cmp_then_jump": "bits 64\ncmp eax, (l2 - l1) / 4\njz l1\nl1: dd 1, 2\nl2:\n",
    "imm_across_jumps": "bits 64\nmov ecx, (le - ls) / 2\nadd rsp, (le - ls)\nls:\n" +
                        "".join("jz e%d\nnop\ne%d:\n" % (i, i) for i in range(12)) + "le:\n",
    "self_push": "bits 64\ns: push dword (e - s)\ne:\n",
    "self_add": "bits 64\ns: add eax, (e - s) * 30\ne:\n",
})
EXPR_ELF.update({
    "elf_distance_imm": "section .text\nadd rsp, (l2 - l1)\nsub rsp, (l2 - l1) / 2\nl1: times 20 db 0\nl2:\n",
})


# ELF: section defaults by name and with attributes, TLS, sectalign, extern
# and global types and bindings, common, unused externs, differences across
# sections (PC-relative), negated special floats
ELF_PROBES.update({
    "elf_tls_sections": "section .tdata\ndd 1\nsection .tbss\nresd 1\nsection .tdata2 progbits alloc write tls\ndd 2\n",
    "elf_known_sections": "section .init_array\ndq 0\nsection .fini_array\ndq 0\nsection .preinit_array\ndq 0\n"
                          "section .comment\ndb 'x', 0\nsection .ldata\ndd 1\nsection .lbss\nresd 1\nsection .lrodata\ndd 2\n",
    "elf_attrs_align1": "section .text progbits\nnop\nsection .data progbits\ndd 1\nsection .bss nobits\nresb 1\n"
                        "section .x write align=8\ndb 1\n",
    "elf_sectalign": "section .data\ndb 1\nsectalign 32\nsection .text\nsectalign 64\nnop\n"
                     "section .rodata\nsectalign off\nalign 64\ndb 2\nsectalign on\n",
    "elf_extern_types": "extern f:function, d:data, w:weak, h:function hidden\nsection .text\ncall f\ncall w\ncall h\nmov eax, [d]\n",
    "elf_global_weak": "global g:function weak, k:weak\nsection .text\ng: ret\nk: ret\n",
    "elf_common_align": "common c 16\ncommon d 8:4\nsection .text\nnop\n",
    "elf_extern_unused": "extern used, unused\nsection .text\ncall used\n",
    "elf_xsec_data": "extern e\nsection .data\na: dd 1\nsection .text\nb: nop\nsection .data\n"
                     "dq b - a\ndd b - a\ndq b - $\ndd b - $ + 4\ndw b - $\ndd e - a\ndq e - $\n",
    "elf_xsec_code": "extern e\nsection .data\na: dd 1\nsection .text\nnop\nmov eax, a - $\nadd eax, a - $\npush a - $\n"
                     "cmp eax, e - $\nmov ax, a - $\nimul eax, ebx, a - $\nmov rax, a - $\n",
})
BIN_PROBES.update({
    "float_special_neg": "dd __Infinity__, -__Infinity__, -__QNaN__\ndq -__Infinity__\ndw -__Infinity__\n",
})
DIAG_CASES += [
    ("difference of two other sections", "section .text\nb: nop\nsection .bss\na: resb 4\nsection .data\ndq b - a\n"),
    ("current section minus another", "section .data\na: dd 1\nsection .text\nb: nop\nsection .data\ndq a - b\n"),
    ("absurdly large alignment", "nop\nalign 0x100000000\n"),
    ("absurdly large alignment, top bit", "nop\nalign 0x8000000000000000\n"),
]

# a multi-line macro's name in the middle of a line is no call: the symbol
# is not defined (utasm expanded the macro there)
DIAG_CASES += [
    ("macro name as a data item", "%macro mm 0\nnop\n%endmacro\ndb 1, mm\n"),
    ("macro name as an immediate", "bits 64\n%macro mm 0\nnop\n%endmacro\nmov eax, mm\n"),
    ("macro given its own name", "%macro mm 1\ndb %1\n%endmacro\nmm mm\n"),
]

# operand sizes utasm used to guess, and empty address terms
DIAG_CASES += [
    ("unsized inc", "nop\ninc [rax]\n"),
    ("unsized mov imm", "nop\nmov [rbx + 8], 5\n"),
    ("unsized shift by cl", "nop\nnop\nshl [rax], cl\n"),
    ("unsized push", "push [rax]\n"),
    ("unsized fld", "nop\nfld [rax]\n"),
    ("unsized lock add", "nop\nlock add [rbx], 1\n"),
    ("empty address", "nop\nmov eax, [ ]\n"),
    ("dangling plus", "mov eax, [rbx + ]\n"),
]
BIN_PROBES.update({
    "op_string_constants": "cmp eax, \"'\"\ncmp eax, '\"'\nmov al, `'`\ncmp eax, \"ab\"\nmov eax, \"'\" + 1\n",
})

# ---------------------------------------------------------------------------
# explanations: utasm's own (rich) diagnostics - the line shown, the place
# marked, the notes. (source, the line marked as "line|mark", the notes)
# ---------------------------------------------------------------------------
EXPLAIN_CASES = [
    ("size clash", "bits 64\nstart:\n    mov al, rax   ; oops\n",
     "    mov al, rax   ; oops|    ^~~~~~~~~~~",
     ["note: `al' is an 8-bit register, `rax' a 64-bit register",
      "note: the operands' sizes differ: 8 and 64 bits"]),
    ("misspelt mnemonic", "bits 64\n\tmvo eax, 1\n", "\tmvo eax, 1|\t^~~", ["hint: did you mean 'mov'?"]),
    ("undefined symbol", "bits 64\nmov eax, [counter]\n", "mov eax, [counter]|          ^~~~~~~", []),
    ("number as destination", "bits 64\nmov 5, eax\n", "mov 5, eax|^~~~~~~~~~",
     ["note: `5' is a number, `eax' a 32-bit register",
      "note: the first operand cannot be a number: it is where the result goes"]),
    ("no size", "bits 64\nlabel: inc [rax]\n", "label: inc [rax]|           ^~~~~",
     ["note: `[rax]' has no size: write `dword [rax]' (or byte, word, qword)"]),
    ("syntax error", "bits 64\nmov eax, [ ]\n", "mov eax, [ ]|           ^", []),
    ("warning", "bits 64\ndb ?\n", "db ?|^~~~", []),
]


# a label alone on its line (NASM's label-orphan); in a macro, the body line
WARN_CASES.update({
    "warn_label_orphan": "foo\nstart\nnop\nbar:\n.local_x\n",
    # an attribute NASM does not know: ignored, with its warning
    "warn_section_attr_unknown": "section .a foo=3\ndb 1\nsection .b progbits bar baz=x align=4\ndb 2\n",
})
EXPLAIN_CASES += [
    ("error in a macro", "bits 64\n%macro load 1\n    mov al, %1\n%endmacro\nnop\nload rax\n",
     "    mov al, %1|    ^~~~~~~~~~",
     ["note: `al' is an 8-bit register, `%1' a 64-bit register"]),
    ("misspelt alone", "bits 64\nrett\n", "rett|^~~~", ["hint: did you mean 'ret'?"]),
]
# utasm's own warnings, with the option that turns them on: (name, source,
# options, lines that must warn with this text, lines that must not)
LINT_CASES = [
    ("pie", "bits 64\nmov eax, msg\nmov eax, [msg]\nlea rax, [rel msg]\nmov rax, msg\ndd msg\n"
            "call fn\nmov eax, [later]\nfn: ret\nsection .data\nmsg: db 1\nlater: dd 2\n",
     ["-w+pie"], {2: "absolute 32-bit address of `msg' will not link into a PIE",
                  3: "absolute 32-bit address of `msg'", 6: "`msg'", 8: "`later'"}, [4, 5, 7]),
    ("pie off by default", "bits 64\nmov eax, msg\nsection .data\nmsg: db 1\n", [], {}, [2]),
    ("pie with default rel", "bits 64\ndefault rel\nmov eax, [msg]\nsection .data\nmsg: dd 1\n",
     ["-w+pie"], {}, [3]),
    ("pie: -w+all", "bits 64\nmov eax, msg\nsection .data\nmsg: db 1\n", ["-w+all"], {2: "[-w+pie]"}, []),
    ("pie: a flat binary", "bits 64\nmov eax, msg\nmsg: db 1\n", ["-w+pie", "-fbin"], {}, [2]),
    # "//" is a comment in utasm, a signed division in NASM: on by default
    ("slash-comment", "bits 64\nmov eax, -7 // 2\nmov eax, 5 // five\nmov eax, 5 // 2 bytes\n"
                      "dd 4 // (1 + 1)\n// 2\nmov eax, 1 // 0x10\nmov eax, 1 // 2.5\n",
     [], {2: "`//' starts a comment here; NASM reads it as a signed division", 5: "[-w+slash-comment]",
          7: "`//'"}, [3, 4, 6, 8]),
    ("slash-comment off", "bits 64\nmov eax, -7 // 2\n", ["-w-slash-comment"], {}, [2]),
]

# -f win64 (scripts/compat/suites.py coff): objects compared field by field
COFF_CASES = {
    "basic": "global main\nextern printf\nsection .text\nmain:\n sub rsp, 40\n lea rcx, [rel msg]\n call printf\n"
             " add rsp, 40\n ret\nsection .data\nmsg: db 'hi', 10, 0\nsection .bss\nbuf: resb 16\n",
    "relocs": "extern e\nglobal g\nsection .text\ng: nop\nl: nop\n mov rax, l\n mov rax, e\n mov eax, [rel l]\n"
              " mov eax, [rel e]\n mov dword [rel l], 5\n mov dword [rel e+4], 5\n call e\n call l\n jmp e\n"
              "section .data\nd: dq l, e, e+8, g\n dd l, e\n dd l wrt ..imagebase\n",
    "rel_more": "extern e\nsection .text\nl: nop\n mov eax, [rel e]\n mov dword [rel e], 7\n mov byte [rel l], 7\n"
                " dd e - $\n dd l - $\n mov eax, [l]\n mov eax, [e]\n",
    "rel_sections": "extern e\nsection .data\nd: dd 1\nsection .text\n mov rax, d\n lea rax, [rel d+4]\n dq d + 3\n"
                    " dd d wrt ..imagebase\n",
    "push_imm": "extern e\nsection .text\npush e\npush qword e\nmov qword [rax], e\n",
    "xsec_call": "section .text\ncall f2\nsection .text2\nf2: ret\n",
    "pcrel_xsec": "section .data\na: dd 1\nsection .text\nnop\n dd a - $\n",
    "forward": "section .text\ncall later\njmp later2\nlater: ret\nsection .data\ndq later2\nsection .text\nlater2: ret\n",
    "long_names": "global a_rather_long_symbol_name\nsection .text\na_rather_long_symbol_name: ret\n"
                  "section .a_long_section_name\ndb 1\nsection .rdata\ndb 2\n",
    "eight": "global abcdefgh, abcdefghi\nsection .text\nabcdefgh: nop\nabcdefghi: nop\nsection .abcdefgh\nnop\n"
             "section .abcdefghi\nnop\n",
    "attrs": "section .t1 code\nnop\nsection .d1 data\ndb 1\nsection .b1 bss\nresb 4\nsection .r1 rdata\ndb 1\n"
             "section .a16 data align=16\ndb 1\nsection .info info\ndb 1\nsection .x\ndb 1\n",
    "attrs_align": "section .s1 text\nnop\nsection .s2 rdata align=4\ndb 1\nsection .s3 info align=8\ndb 1\n"
                   "section .s4 bss align=2\nresb 1\nsection .s5 code align=8192\nnop\nsection .data align=2\ndb 1\n"
                   "section .text align=4\nnop\n",
    "names": "".join("section %s\ndb 1\n" % n for n in
                     [".pdata", ".xdata", ".drectve", ".comment", ".tls$", ".CRT$XCU", ".code", ".rodata",
                      ".tdata", ".data$x", ".text$mn", ".bss$x", ".rdata$r", ".idata$2"]),
    "redeclared": "section .data align=8\ndb 1\nsection .data align=16\ndb 2\n",
    "align": "section .text\nnop\nalign 16\nnop\nsection .data\ndb 1\nalign 32\ndb 2\nsection .bss\nalignb 64\nresb 1\n",
    "empty": "nop\n",
    "nothing": "",
    "only_data": "section .data\ndb 1\n",
    "bss": "section .bss\nresb 1\n",
    "reopened": "section .text\nnop\nsection .data\ndb 1\nsection .text\nnop\n",
    "common": "common c 16\nglobal s\nsection .text\ns: ret\n",
    "static": "static st\nsection .text\nst: ret\nlocal1: ret\n.inner: ret\n",
    "absolute_equ": "global k\nk equ 42\nextern e\nsection .text\nmov eax, k\nret\n",
    "order": "global b\nextern x\nsection .text\na: call x\nb: ret\nextern y\ncall y\nglobal c\nc equ 5\n",
    "constants": "k equ 42\nstruc pt\n.x resd 1\nendstruc\nsection .text\n%macro m 0\n%%l: nop\n%endmacro\nm\n"
                 "mov eax, k\n..@x: nop\n",
    "absolute": "absolute 0x100\nab: resb 4\nsection .text\nnop\n",
    "istruc": "struc s\n.a resb 4\n.b resb 4\nendstruc\nsection .data\nistruc s\nat s.a, db 1\nat s.b, db 2\niend\n",
    "contexts": "section .text\n%push\n%$x: nop\n%pop\n%push\n%$y: nop\n%pop\n",
    "format": "%ifidn __OUTPUT_FORMAT__, win64\ndb 1\n%endif\ndb __BITS__\n",
    "seh": "global f\nsection .text\nf: ret\nf_end:\nsection .pdata\n"
           "dd f wrt ..imagebase, f_end wrt ..imagebase, xd wrt ..imagebase\nsection .xdata\nxd: db 1, 0, 0, 0\n",
    "label_only": "a:\n",
    # a section line in a struc ends its layout; endstruc then puts
    # <name>_size where it is (NASM's struc is [absolute 0] until endstruc)
    "struc_section": "struc s\n.a resb 1\nsection .text\nnop\nendstruc\nnop\n",
    "struc_bracket_section": "struc s\n.a resb 1\n[section .text]\nx: nop\nendstruc\nmov eax, s_size\n",
}
# what COFF has no relocation for (NASM writes a broken object), and the
# symbol types it cannot say (NASM's error): (name, source, line, message)
COFF_ERRORS = [
    ("dw extern", "extern e\nsection .data\nnop\ndw e\n", 4, "COFF format has no 16-bit relocation"),
    ("db extern", "extern e\nsection .data\ndb e\n", 3, "COFF format has no 8-bit relocation"),
    ("dw label", "section .data\nl: dw l\n", 2, "COFF format has no 16-bit relocation"),
    ("dq extern - $", "extern e\nsection .data\ndq e - $\n", 3, "COFF format has no 64-bit relative relocation"),
    ("jmp short extern", "extern e\nsection .text\njmp short e\n", 3,
     "COFF format has no 8-bit relative relocation"),
    ("wrt ..gotpcrel", "extern e\nsection .text\nmov rax, [rel e wrt ..gotpcrel]\n", 3,
     "COFF format has no ..gotpcrel relocation"),
    ("dq imagebase", "extern e\nsection .data\ndq e wrt ..imagebase\n", 3,
     "COFF format has no 64-bit image-relative relocation"),
    ("global hidden", "global f:function hidden\nsection .text\nf: ret\n", 1,
     "COFF format does not support any special symbol types"),
    ("global weak", "global f:weak\nsection .text\nf: ret\n", 1,
     "COFF format does not support any special symbol types"),
    ("extern weak", "extern w:weak\nsection .text\ncall w\n", 1,
     "COFF format does not support any special symbol types"),
    ("common alignment", "common c 8:4\n", 1, "COFF format does not support any special symbol types"),
]

# %% and %$ names (..@N.name): NASM numbers macro calls, %push contexts and
# its standard-macro directives (section, global, align, struc ...) from one
# counter
ELF_PROBES.update({
    "elf_macro_numbers": "%macro m 0\n%%l: nop\n%endmacro\nm\nsection .text\nm\nsection .data\nalign 4\nm\n"
                         "global g\ng: nop\nextern y\ncommon c 4\nm\n[section .text]\nm\nbits 64\n"
                         "default rel\ncpu x64\nsectalign 4\nalignb 4\nm\nincbin '/dev/null'\nm\n",
    # "global x" with no x: no symbol (NASM's); an empty source: no
    # section; a section line in a struc ends its layout, and endstruc puts
    # <name>_size where it then is
    "elf_global_undefined": "global x, y:function\nsection .data\ndb 1\n",
    # a size over a jump that is shortened: the size of the code as it is
    "elf_size_shortened": "global f:function (f.end - f), g:function (g.end - g)\nsection .text\nf: jmp .l\n"
                          "times 10 nop\n.l: ret\n.end:\ng: jmp f\njmp .x\ntimes 200 nop\n.x: ret\n.end:\n",
    "elf_nothing": "",
    "elf_label_first": "a:\nsection .data\ndb 1\n",
"elf_context_names": "section .text\n%macro m 0\n%%l: nop\n%endmacro\nm\n%push\n%$x: nop\nm\n%pop\n%push one\n"
                         "%$y: nop\n%push two\n%$$z: nop\n%pop\n%pop\nm\n",
})


# %use ifunc and %use masm (NASM's packages); a label before a multi-line
# macro ("f proc", "lab: m", %00); "%macro m 0+"; lea of a label
BIN_PROBES.update({
    "use_ifunc": "bits 64\n%use ifunc\ndb ilog2(8), ilog2e(64), ilog2f(9), ilog2c(9), ilog2fw(9), ilog2cw(9), ilog2w(16)\n"
                 "db ilog2f(0), ilog2c(0), ilog2c(1), ilog2f(1)\n"
                 "dq ilog2f(-1), ilog2c(-1), ilog2f(0x8000000000000000), ilog2c(0x8000000000000001)\n"
                 "mov eax, ilog2(4096)\ntimes ilog2c(5) nop\n",
    "use_ifunc_builtins": "bits 64\ndb __?ilog2f?__(10), __ilog2c__(10), __ilog2e__(32), __?ilog2w?__(3)\n",
    "use_ifunc_defined": "bits 64\n%use ifunc\n%ifdef __?USE_IFUNC?__\ndb 2\n%endif\n%ifdef __USE_IFUNC__\ndb 3\n%endif\n",
    "use_masm_ptr": "bits 64\n%use masm\nmov eax, dword ptr [rbx]\nmov eax, offset x\nfld tbyte ptr [rax]\n"
                    "mov rax, qword ptr x\nmov eax, ptr [rbx]\nmov ecx, ptr x\nmov eax, dword ptr fs:[rbx]\n"
                    "mov eax, dword ptr [rbx + 4]\nmov dword ptr [rax], 5\nadd byte ptr [rax], 1\n"
                    "inc word ptr [rax]\nmov eax, [flat:rbx]\nlea rax, x\nx: dq 0\nend\n",
    "use_masm_proc": "bits 64\n%use masm\nf proc near\nret\nf endp\nret\ng proc\nret 8\ng endp\nh proc far\nret\nh endp\n"
                     "i proc foo\nret\ni endp\nj proc far uses rbx\nret\nj endp\nproc\nret\nendp\n"
                     "dq f, g, h, i, j\n",
    "use_masm_segment": "bits 64\n%use masm\nfoo segment\nnop\nbar ends\nnop\nsegment .data\ndb 1\nend start\n",
    "use_masm_twice": "bits 64\n%use masm\n%use masm\nf proc\nret\nf endp\n%ifdef __?USE_MASM?__\ndb 1\n%endif\n",
    "label_before_macro": "bits 64\n%macro m 0\nnop\n%endmacro\n%macro k 0\n%00: int3\n%endmacro\nlab: m\nlab2 m\n"
                          "lab3: k\nlab4 k\ndq lab, lab2, lab3, lab4\n%macro m1 1\nnop\n%endmacro\nlab5 m1 1\ndq lab5\n",
    "label_push_macro": "bits 64\n%macro m 0\nnop\n%endmacro\npush m\n",
    "macro_00_empty": "bits 64\n%macro m 0\ndb 7, %00 1\n%endmacro\nm\n",
    "macro_zero_plus": "bits 64\n%imacro qq 0+\ndb 1\n%endmacro\nqq start\nQQ\n%macro q 0+\ndb %0\n%endmacro\nq\nq a, b\n",
    "macro_nolist_dot": "bits 64\n%imacro mm 0.nolist\nnop\n%endmacro\nmm\n",
    "lea_label": "bits 64\nlea rax, x\nlea rax, 5\nlea rax, [x]\nx: dq 0\n",
    "lea_label_rel": "bits 64\ndefault rel\nlea rax, x\nlea rax, [x]\nlea rax, y\nx: dq 0\ny: dq 0\n",
})
# NASM's warnings: ptr (MASM's word), an absolute address under default rel,
# ilog2w of a number that is no power of two
WARN_CASES.update({
    "warn_ptr": "mov eax, [rbx + ptr]\nptr equ 4\n",
    "warn_ea_absolute": "default rel\nmov ax, [5]\nmov ax, [abs 5]\nmov ax, [fs:5]\n",
    "warn_ilog2w": "%use ifunc\ndb ilog2w(9), ilog2fw(16), ilog2cw(10)\n",
})
DIAG_CASES += [
    ("ilog2 of no power of two", "%use ifunc\ndb 1\ndb ilog2(9)\n"),
    ("lea of a register", "bits 64\nnop\nlea rax, rbx\n"),
]


# a parameter with what follows it pasted on: %{1}0, %{1}y, %{1}%{2}; a
# body listed as NASM lists it (%{2:3} as %2:3), %line, %exitrep, a macro
# defined by a macro
BIN_PROBES.update({
    "paste_braced": "bits 64\n%macro m 2\ndb %{1}0, %{1}%{2}\n%{2}y: db 2\ndq %{2}y\nx%{1}: dq x%{1}\n%endmacro\nm 1, z\n",
    "paste_hex": "bits 64\n%macro m 1\nmov eax, 0x%{1}\ndb %1%1\n%endmacro\nm 1f\nm 3\n",
    "pp_body_braces": "%macro m 1-*\ndb %{1}\ndb %{-1:1}\ndb %{3:2}, %{2: 3}\ndb %1, %{1:1}\ndb %{1}+%{2:2}\n%endmacro\nm 1, 2, 3, 4\n",
    "pp_line_text": "nop\n%line 100 foo.s\ndb __LINE__\n  dw 5 ; a comment\n",
    "pp_exitrep_nested": "%assign i 0\n%rep 4\n%rep 2\ndb i\n%exitrep\ndb 9\n%endrep\n%assign i i+1\n%endrep\n",
    "pp_macro_by_rep": "%rep 2\n%macro x 0\ndb 3\n%endmacro\n%endrep\nx\n",
})

# a multi-line macro defined again with the same parameter range
WARN_CASES.update({
    "warn_macro_redef": "%macro m 0\nnop\n%endmacro\n%macro m 0\nint3\n%endmacro\n%macro m 1\nnop\n%endmacro\nm\n",
})

# .cfi_ directives (scripts/compat/suites.py cfi): GAS's source, utasm's,
# the mode; .eh_frame compared byte for byte
CFI_CASES = {
    'basic': ('\t.text\n\t.globl f\nf:\n\t.cfi_startproc\n\tpushq %rbp\n\t.cfi_def_cfa_offset 16\n\t.cfi_offset %rbp, -16\n\tmovq %rsp, %rbp\n\t.cfi_def_cfa_register %rbp\n\tnop\n\tpopq %rbp\n\t.cfi_def_cfa %rsp, 8\n\tret\n\t.cfi_endproc\n',
          'section .text\nglobal f\nf:\n    .cfi_startproc\n    push rbp\n    .cfi_def_cfa_offset 16\n    .cfi_offset rbp, -16\n    mov rbp, rsp\n    .cfi_def_cfa_register rbp\n    nop\n    pop rbp\n    .cfi_def_cfa rsp, 8\n    ret\n    .cfi_endproc\n', 64),
    'rules': ('\t.text\ng:\n\t.cfi_startproc\n\tsubq $24, %rsp\n\t.cfi_adjust_cfa_offset 24\n\tpushq %rbx\n\t.cfi_adjust_cfa_offset 8\n\t.cfi_rel_offset %rbx, 0\n\t.cfi_remember_state\n\tpopq %rbx\n\t.cfi_restore %rbx\n\t.cfi_adjust_cfa_offset -8\n\t.cfi_restore_state\n\t.cfi_adjust_cfa_offset 8\n\t.cfi_undefined %r12\n\t.cfi_same_value %r13\n\t.cfi_register %r14, %r15\n\t.cfi_offset %r15, 16\n\t.cfi_offset %xmm3, -24\n\t.cfi_restore %xmm3\n\t.cfi_offset %xmm20, -32\n\t.cfi_offset 70, -40\n\t.fill 300, 1, 0x90\n\t.cfi_def_cfa_offset 200\n\t.fill 70000, 1, 0x90\n\t.cfi_def_cfa_offset 8\n\t.fill 70, 1, 0x90\n\t.cfi_escape 0x2e, 0x10\n\tret\n\t.cfi_endproc\n',
          'section .text\ng:\n    .cfi_startproc\n    sub rsp, 24\n    .cfi_adjust_cfa_offset 24\n    push rbx\n    .cfi_adjust_cfa_offset 8\n    .cfi_rel_offset rbx, 0\n    .cfi_remember_state\n    pop rbx\n    .cfi_restore rbx\n    .cfi_adjust_cfa_offset -8\n    .cfi_restore_state\n    .cfi_adjust_cfa_offset 8\n    .cfi_undefined r12\n    .cfi_same_value r13\n    .cfi_register r14, r15\n    .cfi_offset r15, 16\n    .cfi_offset xmm3, -24\n    .cfi_restore xmm3\n    .cfi_offset xmm20, -32\n    .cfi_offset 70, -40\n    times 300 nop\n    .cfi_def_cfa_offset 200\n    times 70000 nop\n    .cfi_def_cfa_offset 8\n    times 70 nop\n    .cfi_escape 0x2e, 0x10\n    ret\n    .cfi_endproc\n', 64),
    'signal_sections': ('\t.text\nh:\n\t.cfi_startproc\n\tnop\n\t.cfi_endproc\nh2:\n\t.cfi_startproc\n\t.cfi_signal_frame\n\tnop\n\t.cfi_endproc\n\t.section .text.other,"ax",@progbits\nk:\n\t.cfi_startproc\n\tnop\n\t.cfi_endproc\n\t.text\nh3:\n\t.cfi_startproc simple\n\t.cfi_def_cfa %rsp, 8\n\tnop\n\t.cfi_endproc\n',
          'section .text\nh:\n    .cfi_startproc\n    nop\n    .cfi_endproc\nh2:\n    .cfi_startproc\n    .cfi_signal_frame\n    nop\n    .cfi_endproc\nsection .text.other exec\nk:\n    .cfi_startproc\n    nop\n    .cfi_endproc\nsection .text\nh3:\n    .cfi_startproc simple\n    .cfi_def_cfa rsp, 8\n    nop\n    .cfi_endproc\n', 64),
    'jumps': ('\t.text\nj:\n\t.cfi_startproc\n\tpushq %rbx\n\t.cfi_def_cfa_offset 16\n\tjmp 1f\n\t.fill 10, 1, 0x90\n1:\tpopq %rbx\n\t.cfi_def_cfa_offset 8\n\tret\n\t.cfi_endproc\n',
          'section .text\nj:\n    .cfi_startproc\n    push rbx\n    .cfi_def_cfa_offset 16\n    jmp .l\n    times 10 nop\n.l: pop rbx\n    .cfi_def_cfa_offset 8\n    ret\n    .cfi_endproc\n', 64),
    'i386': ('\t.text\nf:\n\t.cfi_startproc\n\tpushl %ebp\n\t.cfi_def_cfa_offset 8\n\t.cfi_offset %ebp, -8\n\tmovl %esp, %ebp\n\t.cfi_def_cfa_register %ebp\n\tleave\n\t.cfi_def_cfa %esp, 4\n\tret\n\t.cfi_endproc\n',
          'section .text\nf:\n.cfi_startproc\npush ebp\n.cfi_def_cfa_offset 8\n.cfi_offset ebp, -8\nmov ebp, esp\n.cfi_def_cfa_register ebp\nleave\n.cfi_def_cfa esp, 4\nret\n.cfi_endproc\n', 32),
    'leading_rules': ('\t.text\nf:\n\t.cfi_startproc\n\t.cfi_def_cfa_offset 16\n\tnop\n\t.cfi_endproc\ng:\n\t.cfi_startproc\n\t.cfi_def_cfa_offset 16\n\tret\n\t.cfi_endproc\nh:\n\t.cfi_startproc\n\tret\n\t.cfi_endproc\n',
          'section .text\nf:\n.cfi_startproc\n.cfi_def_cfa_offset 16\nnop\n.cfi_endproc\ng:\n.cfi_startproc\n.cfi_def_cfa_offset 16\nret\n.cfi_endproc\nh:\n.cfi_startproc\nret\n.cfi_endproc\n', 64),
    # GAS's register spelling in the directives (".cfi_offset %rbp")
    'gas_registers': ('\t.text\nf:\n\t.cfi_startproc\n\tpushq %rbp\n\t.cfi_def_cfa_offset 16\n\t.cfi_offset %rbp, -16\n\tmovq %rsp, %rbp\n\t.cfi_def_cfa_register %rbp\n\tpopq %rbp\n\t.cfi_def_cfa %rsp, 8\n\tret\n\t.cfi_endproc\n',
          'section .text\nf:\n.cfi_startproc\npush rbp\n.cfi_def_cfa_offset 16\n.cfi_offset %rbp, -16\nmov rbp, rsp\n.cfi_def_cfa_register %rbp\npop rbp\n.cfi_def_cfa %rsp, 8\nret\n.cfi_endproc\n', 64),
}
# misuses, with GAS's messages: (name, source, line (0: at the end), text)
CFI_ERRORS = [
    ("rule outside", "section .text\n.cfi_def_cfa_offset 16\n", 2,
     "CFI instruction used without previous .cfi_startproc"),
    ("startproc twice", "section .text\n.cfi_startproc\n.cfi_startproc\n", 3,
     "previous CFI entry not closed (missing .cfi_endproc)"),
    ("open at the end", "section .text\n.cfi_startproc\nnop\n", 0,
     "open CFI at the end of file; missing .cfi_endproc directive"),
    ("bad register", "section .text\n.cfi_startproc\n.cfi_offset foo, 8\n.cfi_endproc\n", 3,
     "bad register expression `foo'"),
    ("unknown directive", "section .text\n.cfi_bogus\n", 2, "unknown CFI directive `.cfi_bogus'"),
    ("restore_state alone", "section .text\n.cfi_startproc\n.cfi_restore_state\n.cfi_endproc\n", 3,
     "CFI state restore without previous remember"),
    ("endproc alone", "section .text\nnop\n.cfi_endproc\n", 3,
     ".cfi_endproc without corresponding .cfi_startproc"),
]

# resb / alignb past a code section's buffer (fuzz seed 3: a fault in the
# next byte's write; at the end, the output cut short)
ROBUST_CASES += [
    ("resb_past_buffer", "bits 32\nresb 0x80000\nnop\n", "bin", []),
    ("resb_past_buffer_win64", "nop\nresb 0x80000\nnop\n", "win64", []),
]
BIN_PROBES.update({
    "resb_large_code": "bits 64\nresb 0x80000\nnop\n",
    "resb_large_last": "bits 64\nnop\nresb 0x80000\n",
    "alignb_large_last": "bits 64\nnop\nalignb 0x40000\n",
    "resb_large_then_data": "bits 64\nnop\nresb 0x80000\ndb 7\ntimes 0x30000 db 1\n",
})

# reservations and repetitions past what an output can hold (NASM panics,
# runs for ever or wraps; utasm faulted or hung): utasm's errors, at their
# lines
ROBUST_CASES += [
    ("resb_unsigned_huge", "bits 32\nsection .bss\nresb (l2 - l1) / 4\nmov ebx, 17o\nsection .text\nl4:\nl2:\n"
     "l3: dw 7\nl1: dd 1, 2\n", "bin", []),
    ("resb_unsigned_huge_text", "bits 32\nsection .bss\nl1: dd 1, 2\nsection .text\nresb (l2 - l1) / 4\nl2:\n"
     "l3: dw 7\nl4:\n", "bin", ["-l", "x.lst"]),
]
LIMIT_ERRORS = [
    ("negative reservation", "section .text\nnop\nresb -2\n", 3, "attempt to reserve negative space"),
    ("reservation past 4 GiB", "section .text\nresb 0x100000000\n", 2, "section `.text' larger than 4 GiB"),
    ("reservation that overflows", "section .text\nresq 0x4000000000000000\n", 2, "section `.text' larger than 4 GiB"),
    ("times past 2^32", "section .text\ntimes 0x100000000 nop\n", 2,
     "TIMES value is too large (more than 4294967295)"),
]

# immediates, NASM's way: an unsized memory operand takes a sized
# immediate's size; "mov r64, dword x" is C7; strict keeps the full field
# (no sign-extended imm8, mov r64 its imm64); "byte" forces the imm8 form;
# a value is cut to the operation's width before the imm8 form is chosen
BIN_PROBES.update({
    "imm_size_from_imm": "bits 64\nmov [rax], dword 5\nmov [rax], byte 1\nmov [rax], word 1\n"
                         "add [rax], dword 5\nadd [rax], strict dword 5\ntest [rax], byte 5\ncmp [rax], word 9\n",
    "imm_mov_r64": "bits 64\nmov rax, dword 5\nmov rax, dword -1\nmov rax, strict 5\nmov rax, strict dword 5\n"
                   "mov rax, strict 0xffffffff80000000\nmov rax, qword 5\nmov rax, 0x80000000\n",
    "imm_strict": "bits 64\nadd ecx, strict dword 4\nxor ecx, strict dword -1\nadd rax, strict 5\n"
                  "push strict dword 5\nimul eax, ecx, strict 5\npshufd xmm0, xmm1, strict 5\nshl eax, strict 1\n",
    "imm_width_cut": "bits 16\nadd ax, 0FFFFh\npush 0ffffh\npush byte 0FFFFh\nadd cx, byte 0FFFFh\n"
                     "bits 32\npush 0ffffffffh\nadd eax, 0FFFFFFFFh\nbits 64\nadd rcx, 0FFFFFFFFh\n"
                     "and rax, 0xffffffff\nimul rax, rcx, 0xffffffff\n",
    # xacquire / xrelease: the ModRM form of mov, not A0-A3
    "hle_mov_modrm": "bits 32\nmov [sym], eax\nxrelease mov [sym], eax\nxacquire mov [sym], al\nsym: dd 0\n",
    # a forward jump to a label and an offset is shortened as one to the label
    "jmp_label_offset": "bits 64\njmp x+2\njz x+1\nx: nop\nnop\nnop\n",
    # far indirect in 64-bit code: m16:64 by default, "dword" m16:32
    "jmp_far_64": "bits 64\njmp far [rax]\njmp far dword [rax]\ncall far dword [rax]\ncall far qword [rax]\n",
})
WARN_CASES.update({
    "warn_imm_bounds": "bits 64\nadd rcx, 0xFFFFFFFF\ncmp rax, 0x80000000\nmov qword [rax], 0x180000000\n"
                       "mov rax, dword 0x80000000\npush 0xffffffff\nadd eax, 0x1ffffffff\npush byte 0x1ff\n"
                       "imul eax, ecx, byte 0x1ff\nbits 16\nadd ax, 0FFFFFFFFh\nadd ax, byte 0FFFFFFFFh\n"
                       "push 0ffffffffh\n",
    # o16 / o32 / o64 against the operands' size: the prefix wins
    "warn_prefix_opsize": "bits 16\no32 inc ax\no16 movsd\no32 cwd\no32 push 5\nbits 64\no64 add eax, 1\n"
                          "o32 in ax, dx\no16 nop\n",
})
DIAG_CASES += [
    ("sized immediate of another size", "nop\nmov eax, word 5\n"),
    ("dword immediate to a qword add", "nop\nadd qword [rax], dword 5\n"),
]
# o16 / o32 / o64 are the operation's size, as NASM; far jumps through memory
MODE_LINES += [
    "o16 nop", "o32 nop", "o64 nop", "o16 iret", "o32 iret", "o64 iret", "o16 retf", "o32 retf",
    "o16 pushf", "o32 pushf", "o16 movsd", "o32 movsw", "o32 cwd", "o16 cbw", "o32 inc ax", "o16 inc eax",
    "o16 add eax, 1", "o32 add ax, 1", "o64 add eax, 1", "o32 lodsb", "o16 lgdt [0x10]", "o32 lgdt [0x10]",
    "jmp far [0x10]", "call far [0x10]", "jmp far dword [0x10]", "call far word [0x10]",
    "o16 push 5", "o32 push 5", "o16 mov [0x10], ax", "o32 mov word [0x10], 5",
]
# -O0 / -O1 / -Ox: NASM's levels
CLI_FILES["opt.s"] = ("bits 64\na: nop\njmp a\njz a\njmp b\njz b\nadd eax, 5\nadd rax, 5\nmov rax, 5\n"
                      "mov rax, -5\npush 5\nimul eax, ecx, 5\nb: nop\n")
CLI_CASES += [
    ("-O0", ["-f", "bin", "-O0", "opt.s"], "bin"),
    ("-O1", ["-f", "bin", "-O1", "opt.s"], "bin"),
    ("-Ox", ["-f", "bin", "-Ox", "opt.s"], "bin"),
    ("-O2", ["-f", "bin", "-O2", "opt.s"], "bin"),
]
# xacquire / xrelease: NASM's prefix-hle warnings; LOCK needs the memory
# operand first (xchg's either)
WARN_CASES.update({
    "warn_hle": "bits 64\nxacquire lock add [rsi], eax\nxacquire add [rsi], eax\nxrelease add [rsi], eax\n"
                "xacquire add ecx, [rax]\nxrelease lock add ecx, [rax]\nxacquire xchg [rax], ebx\n"
                "xacquire xchg ebx, [rax]\nxrelease mov [rax], ecx\nxacquire mov [rax], ecx\n"
                "xrelease mov ecx, [rax]\nxacquire nop\nxrelease lock xadd [rax], ecx\n"
                "xrelease lock mov [rax], ecx\nlock add ecx, [rax]\n",
})
# "comm" is no directive (NASM's is common): a label of that name (the old
# GAS-style handler faulted on any line starting with it)
BIN_PROBES.update({
    "comm_is_a_label": "bits 64\ncomm db 1\ncomm2: dd comm\n",
})
# [byte x] keeps its byte (cut, with NASM's warning); empty sections at
# their aligned address; pinsrb's r/m8 as r32 (no REX for sil); a size on a
# vector register (insertps xmm0, dword xmm1); zmm register blocks (rs4)
BIN_PROBES.update({
    "disp8_forced": "bits 64\nmov eax, [byte rsp+0x01]\nmov eax, [byte rsp+0xFF]\nmov eax, [byte rsp-0xFF]\n",
    "bin_empty_sections": "section .text\nnop\nsection .data\nd:\nsection .bss\nb:\nsection .x align=16\nx:\n"
                          "section .text\ndw d, b, x\n",
    "bin_empty_bss_after_data": "section .text\nnop\nsection .data\ndb 1, 2, 3\nsection .bss\nalignb 4\ne:\n"
                                "section .text\ndw e\n",
    "pinsrb_byte_regs": "bits 64\npinsrb xmm1, sil, 0\npinsrb xmm0, dil, 1\npinsrb xmm8, r9b, 1\npinsrb xmm0, al, 1\n",
    "vector_reg_sized": "bits 64\ninsertps xmm0, dword xmm1, 16\nmovss xmm0, dword xmm1\naddps xmm0, oword xmm1\n",
    "zmm_register_blocks": "bits 64\nv4fmaddps zmm0, zmm1+3, [rax]\nv4fnmaddss zmm6, zmm7+3, [rax]\n"
                           "v4dpwssd zmm10+0, zmm11+3, [rax]\nv4dpwssds zmm8, zmm9, [rax]\n",
})
WARN_CASES.update({
    "warn_obsolete": "bits 16\npop cs\ncpu 8086\npop cs\ncpu 386\npop cs\ncpu any\npcommit\n",
})
DIAG_CASES += [
    ("a high register in pinsrb", "nop\npinsrb xmm0, ah, 1\n"),
    ("a register block of five", "nop\nv4dpwssd zmm10, zmm11+4, [rax]\n"),
]
MODE_LINES += ["pop cs", "pcommit", "pinsrb xmm1, sil, 0", "pinsrb xmm1, al, 0"]
# "times N resb K" is one reservation (one warning, "<res Nh>" listed);
# a times line's bytes and "<rep Nh>" past 18 columns wrap, as NASM lists
BIN_PROBES.update({
    "times_res_one": "nop\ntimes 2 resb 4\ntimes 4 resb 16\ntimes 1 resb 20\ntimes 5 resw 0x100\nnop\n",
    "times_rep_wrap": "times 2 db 1,2,3,4,5\ntimes 2 db 1,2,3,4,5,6\ntimes 20 db 1,2,3,4,5\n"
                      "times 0x100 db 1,2,3,4\ntimes 2 db 1,2,3,4,5,6,7,8,9\n",
})
# floats: NASM's 8-bit format (db), bfloat16, $-prefixed hex floats,
# __NaN__, %use fp's bf16; a constant too big: infinity, with the warning
BIN_PROBES.update({
    "float8_data": "db 0.0, 0.001953125, 0.0625, 1.0, -1.5, 240.0, 1.0e10, 0.5e-10, __Infinity__, __QNaN__\n",
    "float_bfloat16": "bits 64\nmov ax, __bfloat16__(1.5)\nmov al, __float8__(-2.0)\nmov ax, __?bfloat16?__(3.1415)\n",
    "float_dollar_hex": "dw $1.0, $1.0p-1, $1.23456789p+10\ndd $1.8p3\ndq $0.1p-1000\n",
    "float_nan_name": "dw __NaN__\ndd __NaN__\ndq __NaN__\ndt __NaN__\ndo __NaN__\n",
    "float_use_fp_bf16": "%use fp\nbf16 1.0, -1.5, NaN, Inf, 2000.0\ndb float8(1.0)\n",
})
WARN_CASES.update({
    "warn_float_overflow": "dd 1.0e50\ndq 1.0e400\ndd 1.0\ndb 1.0e10\n",
})
# packed BCD in dt (123p, 0p123); %rep 0 runs the body no times (it ran
# once), a negative count too, with NASM's warning; a float item before
# does not make a later "-1" a float's negation
BIN_PROBES.update({
    "bcd_dt": "dt 765432109876543210p, -456p, +789p\ndt 0p123, -0p765_432_109_876_543_210\ndt 1.5, 123p\n",
    "rep_zero": "%rep 0\ndb 1\n%endrep\n%assign n 3\n%rep 3-n\ndb 2\n%endrep\ndb 3\n",
    "float_then_negative": "dd 1.5\n%substr s 'abc' 2,-1\ndb s\n%assign v -2\ndb v\ndb -1\n",
})
WARN_CASES.update({
    "warn_bcd_rep": "dt 98765432109876543210p\n%rep -1\ndb 1\n%endrep\nnop\n",
})
CLI_FILES["assign.s"] = '%assign v 5\n%strlen n "abc"\n%macro m 0\n%assign w -3\ndb w\n%endmacro\ndb v, n\nm\n'
CLI_CASES += [("-E with %assign", ["-f", "bin", "assign.s"], "pp")]
# %defalias / %idefalias / %undefalias and the %ifdefalias family (NASM 2.15)
BIN_PROBES.update({
    "alias_chain": "%defalias a b\n%defalias b c\n%define c 7\ndb a, b, c\n",
    "alias_icase": "%idefalias FOO bar\n%define bar 3\ndb foo, Foo, FOO\n",
    "alias_tests": "%defalias a b\n%ifdefalias a\ndb 1\n%endif\n%ifndefalias b\ndb 2\n%endif\n"
                   "%if 0\n%elifdefalias a\ndb 5\n%endif\n%ifdef a\ndb 6\n%endif\n",
    "alias_define_undef": "%defalias a b\n%assign a 5\ndb b\n%define a 1\n%undefalias a\n%define a 2\ndb a, b\n"
                          "%defalias c d\n%xdefine c 6\ndb d\n%undef c\n%ifdef d\ndb 9\n%endif\n",
})
# %?? in a single-line macro's arguments; %[...] inside %[...]; an %assign
# expands to its value (%defstr sees it); pasted text read again (1e+36,
# xyzzy1e + 10); __utf16__ in an expression; macro defaults as NASM counts
# them; %ifmacro m 1+; %iftoken of an empty %define
BIN_PROBES.update({
    "pp_qq_in_define_args": "%define label(p, s) p %+ s\nlabel_1:\nmov ax, label(%??, _1)\nlabel_2:\nmov ax, label(%?, _2)\n",
    "pp_interp_nested": "%assign n 2\n%assign foo2 22\n%assign foo22 3\n%assign foo%[foo%[n]] 9\ndb foo22\n"
                        "dd foo%[foo%[n]]*100\n%define foo33bar 99\n%assign foo3 33\ndd %[foo%[foo3]bar]\n",
    "pp_assign_is_text": "%assign b1 1\n%defstr s b1\ndb s\n%assign c 1\n%macro m 0\n%assign bl%[c] c\n"
                         "%defstr bs bl%[c]\ndb bl%[c]\ndb bs\n%endmacro\nm\n%strlen n 'abc'\n%defstr ns n\ndb ns\n",
    "pp_paste_rescan": "%macro df 2\ndd %1e+%2\n%endmacro\ndf 1, 36\ndf 1.2, 5\n%define N 1e%++%+ 5\ndd N, 1e+5\n"
                       "%define foo xyzzy\n%define bar 1e+10\n%define xyzzy1e 15\n%macro dx 2\n%assign xx %1%2\ndw xx\n"
                       "%endmacro\ndx foo, bar\n",
    "utf_in_expression": "mov ax, __utf16__(`a`)\nmov ax, __utf16be__(`a`)\ndw __utf16__(`ab`)\n",
    "macro_defaults_count": "%macro m 1 a\ndb %0, %2\n%endmacro\nm 5\n%macro r 0-* 7,8\ndb %0, %1, %2\n%endmacro\nr\nr 1\n"
                            "%macro g 1-2+ 3,4\ndb %2\n%endmacro\ng 1\n",
    "ifmacro_plus": "%macro two 2\nnop\n%endmacro\n%ifmacro two 1+\ndb 1\n%endif\n%ifmacro two 3+\ndb 2\n%endif\n",
    "iftoken_empty_define": "%define Z\n%define T 1 2\n%iftoken Z\ndb 1\n%else\ndb 2\n%endif\n%iftoken T\ndb 3\n%else\ndb 4\n%endif\n",
})
WARN_CASES.update({
    "warn_message_text": "%macro m 1-2+ a,b\n%warning %0 %1 %2\n%endmacro\nm one\nm one,two,three\n",
})
DIAG_CASES += [
    ("a directive from a %define", "nop\n%define IFNDEF %ifndef\nIFNDEF foo\n"),
    ("%rep past the limit", "nop\n%rep 2000000\nnop\n%endrep\n"),
]
CLI_FILES["increp.s"] = '%rep 3\ndb 0\n%include "two.inc"\n%endrep\n%define F "two.inc"\n%include F\ndb 1\n'
CLI_FILES["two.inc"] = "db 2\n"
CLI_CASES += [("%include in %rep", ["-f", "bin", "increp.s"], "bin"),
              ("--limit-rep", ["-f", "bin", "--limit-rep", "5", "increp.s"], "bin")]

# a bits 16 near branch reaches anywhere in its 64 KB (IP wraps); padding
# K - ($ - $$) that is below 0 until the jumps before it are shortened;
# [cpu 386] and the directives a [ ] takes; %elifmacro with no name is false
BIN_PROBES.update({
    "jmp16_wraps": "bits 16\norg 0\njmp near init\ntimes 0x9956 - ($ - $$) db 0\ninit:\n",
    "padto_after_shortening": "bits 64\njmp x\njmp x\nx: nop\ntimes 6-($-$$) db 0\n",
    "bracket_directives": "[bits 16]\n[cpu 386]\n[default rel]\n[section .text]\n[warning -all]\n[absolute 0]\n"
                          "[section .text]\nnop\n",
    "elifmacro_no_name": "%if 0\n%elifmacro\ndb 1\n%else\ndb 2\n%endif\n%if 0\n%ifmacro\n%endif\n%endif\n",
    # a %elif NASM cannot work out (a name not defined, a label, no macro
    # name) ends its %if: no later branch, no message
    "elif_never": "x: nop\n%if 0\n%elif foo\ndb 1\n%else\ndb 2\n%endif\n%if 0\n%elif x\ndb 3\n%elif 1\ndb 4\n%endif\n"
                  "%if 0\n%elifnmacro\ndb 5\n%else\ndb 6\n%endif\n%if 1\ndb 7\n%elif foo\n%else\ndb 8\n%endif\n",
    # padding that grows from none as the jumps before it shrink: listed on
    # its own line
    "align_grows_from_none": "bits 64\njmp x\njmp x\ntimes 6 nop\nalign 8\nx: nop\n",
    "padto_grows_from_none": "bits 64\njmp x\njmp x\nx: nop\ntimes 11-($-$$) db 0\nnop\n",
})
# a size before far ("call qword far [rax]"); MASM's displacement before
# the brackets (bar[rbx], 4[rbx]); a segment register and a colon before a
# memory operand (gs:[rbx], fs:0x28, es:[di], qword gs:[x], %use masm's
# "qword ptr gs:foo"); lea ignores the size of what it addresses; padding
# of nops that grows as the jumps before it shrink (NASM's fwdopt)
BIN_PROBES.update({
    "far_after_size": "bits 64\ncall qword far [rax]\njmp qword far [rax]\ncall dword far [rax]\njmp dword far [rax]\n"
                      "call far [rax]\nbits 16\njmp word far [bx]\njmp dword far [bx]\n",
    "masm_disp_before_brackets": "bits 64\nmov ecx, bar[rbx]\nmov ecx, 4[rbx]\nmov ecx, bar[rbx+4]\nlea rax, bar[rbx*2]\n"
                                 "bits 32\nmov eax, bar[ebx]\nbar: dd 0\n",
    "segment_colon_operand": "bits 64\nmov rdi, gs:[rbx]\nmov rdi, gs:foo\nmov rdi, fs:0x28\nmov rdi, qword gs:[rbx]\n"
                             "mov gs:[rbx], rdi\nbits 16\nmov ax, es:[di]\nmov ax, ss:[bp+2]\nfoo: dw 0\n",
    "masm_ptr_segment": "%use masm\nbits 64\nmov rdi, qword ptr gs:foo\nmov eax, dword ptr fs:[rbx]\nfoo: dq 0\n",
    "lea_sized_memory": "bits 64\nlea rsi, dword [foo]\nlea rsi, byte [rax]\nlea esi, qword [rax]\nlea rsi, word [rax]\n"
                        "bits 32\nlea esi, byte [eax]\nfoo:\n",
    "padto_nops_after_shortening": "bits 64\n%assign i 0\n%rep 60\nn%[i]: jmp n%[i+1]\n%assign i i+1\n%endrep\n"
                                   "n60: jmp n0\ntimes 130-($-$$) nop\nhlt\n",
})
# "imul rax," (a macro's empty last argument): the comma ends the
# operands; labels of an absolute block used before it, its base with the
# org; %[...] with more than a name (macros in it expanded); a16 / a32 / a64
# inside the brackets; [qword x]: mov's A0-A3 with a 64-bit address; [rel 5]
# is absolute (ModRM, no moffs)
BIN_PROBES.update({
    "trailing_comma": "bits 64\nimul rax,\nadd eax, 1,\npush rax,\n%macro m 1-2\nmov eax, %1, %2\n%endmacro\nm 5\n",
    "absolute_forward": "bits 16\norg 0x7c00\nx: mov [b1], dl\nmov [b2], edx\nret\nabsolute x+7\nb1: resb 1\nb2: resd 2\n",
    "absolute_forward_plain": "bits 16\nmov [b1], dl\nret\nabsolute 0x100\nb1: resb 1\n",
    "pp_interp_expression": "%assign i 3\n%define J 1+2\nn3: db 0\nn1: db 0\ndb n%[i+1]\ndb n%[J]\n",
    "asize_in_brackets": "bits 64\nmov eax,[a32 foo]\nmov al,[a64 foo]\nmov eax,[a32 ebx+4]\nmov al,[a64 abs foo]\n"
                         "bits 32\nmov eax,[a16 0x10]\nbits 16\nmov ax,[a32 0x10]\nfoo:\n",
    "qword_moffs64": "bits 64\nmov rax,[qword 0x10]\nmov al,[qword 0xffffffffcccccccc]\nmov [qword 0x10], eax\n"
                     "mov ax,[a64 qword 0x10]\nmov eax,[qword foo]\nmov rax,[abs qword foo]\nfoo:\n",
    "rel_number_absolute": "bits 64\nx equ 5\nmov al,[rel 0x10]\nmov al,[rel x]\nmov eax,[rel 0x20]\ny: mov al,[rel y]\n",
})
ELF_PROBES.update({
    # a struc's name and fields, an absolute block's labels: local ABS
    # symbols, as an equ's (NASM writes them with -g or not)
    "struc_absolute_symbols": "x equ 5\nstruc s\n.a: resb 1\n.b: resd 1\nendstruc\nabsolute 0x10\nb1: resb 1\n"
                              "section .text\nmov eax, [b1]\nnop\n",
})
# a %define is not expanded inside its own expansion ("%define foo foo");
# a label's name is expanded ("foo:" with %define foo bar), also after %+;
# a %macro does not call itself (only %rmacro does: "f" in f is a label)
BIN_PROBES.update({
    "define_self_reference": "%define foo foo\n%define a b\n%define b a\nfoo: dd foo\nb: dd a, b\n",
    "define_in_label": "%define foo bar\n%define L lab_ %+ 3\n%assign n 3\nfoo: dd bar\nL: dd lab_3\n"
                       "start_ %+ n: dd start_3\n%define d 7\nlbl %+ d: dd lbl7\n",
    "macro_not_recursive": "%macro f 0\ntimes 3 nop\nf\n%endmacro\nf\n%macro a 0\nb\n%endmacro\n"
                           "%macro b 0\ndb 7\n%endmacro\na\na\n",
    "rmacro_recursive": "%rmacro r 1\n%if %1 > 0\ndb %1\nr %1-1\n%endif\n%endmacro\nr 3\n",
})
# many sections: their names looked up by a hash, their relocations and
# jumps grouped once (each was a walk of all of them per section)
ELF_PROBES.update({
    "many_sections": "%assign n 0\n%rep 300\n%assign g (n & ~3) + 2\nsection .s%[n] progbits exec\nl%[n]: nop\n"
                     "jmp l%[g]\n%assign n n+1\n%endrep\nsection .s0\njmp l299\n",
})
# "baz - $" across sections: a number in a flat binary; the second pass's
# values taken again until they settle ("[ebx + bar - $]" its disp8);
# numbers past 64 bits keep the low 64 with NASM's warning; a displacement
# is 32 (16) bits, so [eax + 0xffffffff] is [eax - 1], a disp8; a lone "%"
# at the end of a line is one token; "section a,b" is one name; a name
# declared global before it is defined is still an address
BIN_PROBES.update({
    "cross_section_distance": "bits 32\nmov ebx,[ebx + bar - $]\nmov eax,[baz - $]\nmov ecx, baz - $\n"
                              "bar: hlt\nsection .data\nbaz: dd 0\n",
    "known_runs_settle": "bits 32\nmov ebx,[ebx + 5 - $]\nmov eax,[baz + 0 - $]\nsection .data\nbaz: dd 0\n",
    "number_past_64_bits": "bits 64\nmov al, [qword 0x1ffffffffffffffff]\ndq 0x10000000000000000\ndq 18446744073709551617\n",
    "displacement_wraps": "bits 64\nmov cl, [rax + 0xffffffff]\nbits 32\nmov cl, [eax + 0xffffffff]\n"
                          "mov cl, [byte eax + 0xffffffff]\nbits 16\nmov cl, [di + 0xffff]\nmov cl, [di + 0x1ffff]\n"
                          "mov cl, [byte di + 0xffff]\n",
    "iftoken_lone_percent": "%iftoken %\ndb 1\n%else\ndb 2\n%endif\n%iftoken %%\ndb 3\n%endif\n",
    "global_before_defined": "bits 64\nglobal foo\nsection .text\nmov rax, foo\ndq foo\nsection .data\ndd foo\nfoo: dd 0\n",
})
ELF_PROBES.update({
    "section_name_comma": "section __LD,__compact_unwind\ndd 0\n",
    "global_declared_first": "global foo\nsection .data\ndq foo\nfoo: dd 0\nsection .text\nmov rax, foo\n"
                             "global bar\ndq bar\nbar: dd 0\n",
    "pcrel_across_sections": "bits 64\nsection .text\nnop\nmov eax, [baz - $]\nlea rax, [rdi + rod1 - $$]\n"
                             "mov ecx, baz - $\ndefault rel\nmov eax, [baz - $]\nsection .rodata\nrod1: dd 0\n"
                             "section .data\nbaz: dd 0\ndd baz - $\n",
    "pcrel_across_sections_back": "bits 64\nsection .rodata\nrod1: dd 0\nsection .text\nnop\n"
                                  "lea rax, [rdi + rod1 - $$]\nmov eax, rod1 - $$\n",
})
ELF32_CASES.update({
    "pcrel_across_sections": "nop\nmov eax, [baz - $]\nmov ebx, [ebx + baz - $]\nmov ecx, baz - $\ndd baz - $\n"
                             "dw baz - $\nsection .data\nbaz: dd 0\n",
})
# %num's digits: N > 0 exactly N (the low ones), N < 0 at least -N;
# "add eax, byte foo": imm8 with an 8-bit relocation; %pragma's prefixes
# on global and local names; "required" writes an extern unused
BIN_PROBES.update({
    "num_digits": "%define a 64\n%define b -30\ndb %num(a*b,10), `\\n`\ndb %num(a*b,3), `\\n`\n"
                  "db %num(a*b,-3), `\\n`\ndb %num(a*b,10,2), `\\n`\ndb %num(255,4,16), `\\n`\ndb %num(5,-4), `\\n`\n",
})
ELF_PROBES.update({
    "imm_byte_relocation": "extern foo, bar\nadd eax, byte foo\nadd edx, byte (bar-$$)\n",
    "pragma_prefixes": "%pragma elf gprefix\n%pragma elf lprefix .L.\n%pragma output gprefix _\n"
                       "%pragma output lprefix L.\nextern malloc\nglobal call_malloc\ncall_malloc:\n"
                       "call malloc\nret\nmyfunc:\njmp call_malloc\n",
    "pragma_output_prefixes": "%pragma output gprefix _\n%pragma output lprefix L.\nextern ext\nglobal gl\n"
                              "section .data\ngl: dd ext\nloc: dd 0\n.sub: dd 0\nx equ 5\n",
    "required_extern": "required r1\nextern e1\nglobal g\ng: nop\n",
})
# AVX-512 with {sae} before the immediate - five operands (vcmppd, vcmpsd,
# vfixupimm*, vgetmant*s*, vrndscales*); the memory-only hand encoders
# (prefetchwt1: 0F 0D /2, its REX)
BIN_PROBES.update({
    "evex_sae_five_operands": "bits 64\nvcmppd k5,zmm30,zmm29,{sae},0xab\nvcmpps k5{k7},zmm30,zmm29,{sae},0x7b\n"
                              "vcmpsd k1,xmm2,xmm3,{sae},0x10\nvcmpss k5,xmm30,xmm29,{sae},0xab\n"
                              "vfixupimmpd zmm1,zmm2,zmm3,{sae},0x10\nvfixupimmps zmm1{k2}{z},zmm2,zmm3,{sae},0x10\n"
                              "vfixupimmsd xmm1,xmm2,xmm3,{sae},5\nvgetmantsd xmm1,xmm2,xmm3,{sae},5\n"
                              "vrndscaless xmm30,xmm29,xmm28,{sae},0xab\nvcmppd k5,zmm30,zmm29,0xab\n",
    "prefetch_hand_encoded": "bits 64\nprefetchwt1 [rcx]\nprefetchwt1 byte [rcx]\nprefetchwt1 [rax+r14*8+0x123]\n"
                             "prefetchwt1 [r9]\nprefetchw [r10]\nclflush [r11]\nclflushopt [r12+rax]\n",
})
# what NASM rejects, rejected with its message on its line: (name, format,
# source)
REJECT_CASES = [
    ("times negative", "bin", "bits 16\nnop\ntimes -1 db 0\n"),
    ("times negative incbin", "bin", "bits 16\ntimes -3 incbin \"p.s\"\n"),
    ("times padding past its end", "bin", "bits 16\norg 0x7c00\ntimes 520 nop\ntimes 510-($-$$) db 0\ndw 0xaa55\n"),
    ("times padding past its end elf", "elf64", "times 4 nop\ntimes 2-($-$$) db 0\n"),
    ("times past even shortened", "bin", "bits 64\njmp x\njmp x\nx: nop\ntimes 4-($-$$) db 0\n"),
    ("times a label distance", "bin", "bits 64\nx: times 3 nop\ntimes x-$ db 0\n"),
    ("jc alone", "bin", "bits 16\nnop\njc\n"),
    ("jmp alone", "elf64", "nop\njmp\n"),
    ("call alone", "elf64", "call\n"),
    ("loop alone", "elf32", "loop\n"),
    ("jrcxz alone", "elf64", "jrcxz\n"),
    ("%ifmacro no name", "bin", "%ifmacro\n%endif\n"),
    ("%ifnmacro no name", "bin", "nop\n%ifnmacro\n%endif\n"),
    ("%ifmacro a number", "bin", "%ifmacro 5\n%endif\n"),
    ("%if undefined", "bin", "%if foo\ndb 1\n%endif\n"),
    ("%if undefined compared", "bin", "%if foo == bar\n%endif\n"),
    ("%if undefined after &&", "bin", "%if 0 && foo\n%endif\n"),
    ("%if a format name", "bin", "%if __OUTPUT_FORMAT__ == bin\n%endif\n"),
    ("%if a label later", "bin", "%if y\n%endif\ny: nop\n"),
    ("%if a label", "bin", "x: nop\n%if x\n%endif\n"),
    ("%ifn a label", "bin", "x: nop\n%ifn x+1\n%endif\n"),
    ("%if an extern", "elf64", "extern e\n%if e\n%endif\n"),
    ("%assign a label", "elf64", "x: nop\n%assign v x\n"),
    ("%assign undefined", "bin", "%assign v foo+bar\n"),
    ("[map] in an object", "elf64", "[map all x.map]\nnop\n"),
    ("[org] in an object", "elf32", "[org 0]\nnop\n"),
    ("[map] in win64", "win64", "[map]\n"),
    ("unknown in brackets", "bin", "[foo 0]\n"),
    ("db in brackets", "bin", "[db 1]\n"),
    ("times in brackets", "bin", "[times 2 nop]\n"),
    ("an instruction in brackets", "elf64", "[mov eax, 1]\n"),
    ("align in brackets", "bin", "[align 4]\n"),
    ("struc in brackets", "bin", "[struc s]\n"),
    ("incbin in brackets", "bin", "[incbin \"p.s\"]\n"),
    ("brackets after a label", "bin", "x: [bits 32]\n"),
    ("common in bin", "bin", "common c 4\n"),
    ("common with alignment in bin", "bin", "common c 4:4\n"),
    ("jmp far a number", "bin", "bits 16\njmp far 5\n"),
    ("call far a number", "elf32", "call far 0x1234\n"),
    ("jmp far a label", "bin", "bits 16\njmp far x\nx:\n"),
    ("call far a label", "bin", "bits 32\ncall far foo\nfoo: nop\n"),
    ("jmp far a label elf", "elf32", "jmp far x\nx:\n"),
    ("jmp far an extern", "elf32", "extern e\njmp far e\n"),
    ("jmp far in 64-bit mode", "elf64", "jmp far 5\n"),
    ("jmp far in win64", "win64", "jmp far x\nx:\n"),
    ("seg a number", "bin", "dw seg 5\n"),
    ("seg a label", "bin", "x: dw seg x\n"),
    ("seg a label later", "bin", "dw seg x\nx:\n"),
    ("seg in an expression", "bin", "x: dw (seg x)+1\n"),
    ("seg an equ", "bin", "x equ 5\ndw seg x\n"),
    ("seg elf", "elf64", "x: dq seg x\n"),
    ("seg an extern", "elf32", "extern e\nmov ax, seg e\n"),
    ("seg alone", "bin", "dw seg\n"),
    ("address size against the registers", "bin", "bits 64\na32 mov eax,[rbx]\n"),
    ("a16 against 32-bit registers", "bin", "bits 32\nmov eax,[a16 ebx]\n"),
    ("a32 against 64-bit registers in brackets", "elf64", "nop\nmov eax,[a32 rbx]\n"),
]
REJECT_CASES += [
    ("six operands", "elf64", "vcmppd k5,zmm30,zmm29,{sae},0xab,1\n"),
]
# a section declared again keeps the largest alignment asked for
ELF_PROBES.update({
    "elf_redeclared_align": "section .text align=64\nnop\nsection .data align=64\ndb 1\nsection .text align=32\nnop\n"
                            "section .data\ndb 2\nsection .bss\nresb 1\nsection .bss align=16\nsection .bss align=8\nresb 1\n",
})
# "$ - $$" and label differences the preprocessor reads, over jumps that
# shorten: the distance as laid out (NASM's last pass), %error / %fatal
# only where it holds; the smaller layout when two would hold
BIN_PROBES.update({
    "pp_dollar_after_jumps": "bits 64\nn0: jmp n1\nn1: jmp n2\nn2: jz n3\nn3: nop\n%if ($-$$) > 7\n%error \"too big\"\n%endif\n"
                             "%if ($-$$) > 7\n%fatal \"too big\"\n%endif\n%assign sz $-$$\ndb sz\n",
    "pp_dollar_optimistic": "bits 64\na: jmp b\n%if ($-a) > 2\ntimes 200 nop\n%endif\nb: nop\n",
    "pp_dollar_rep": "bits 64\n%rep 3\njmp e\n%assign s $-$$\ndb s\n%endrep\ne: nop\n%assign t e - $$\ndw t\n",
    "pp_dollar_bootsector": "bits 16\norg 0x7c00\nstart: jmp main\nmsg: db \"hi\", 0\nmain: mov si, msg\njz done\n"
                            "times 100 nop\njmp start\ndone: hlt\n%if ($-$$) > 510\n%error \"too big\"\n%endif\n"
                            "times 510-($-$$) db 0\ndw 0xaa55\n",
    "pp_dollar_macro": "bits 64\n%macro chk 1\n%if ($-$$) > %1\n%warning over %1\n%endif\n%endmacro\njmp q\nchk 2\n"
                       "times 3 nop\nq: chk 5\njmp q\nchk 100\n",
})
# "absolute label+n" after jumps that shorten: the label as laid out; NASM's
# own directive macros for %ifmacro (org in -f bin)
BIN_PROBES.update({
    "absolute_after_jumps": "bits 16\norg 100h\nstart: jmp main\nmsg: db \"hello$\"\nmain: mov dx, msg\nmov [buf], dl\n"
                            "jz quit\nmov ah, 9\nint 21h\nquit: ret\nend_code:\nabsolute end_code + 7\nbuf: resb 16\ncnt: resw 1\n"
                            "section .text\nmov [cnt], ax\n",
    "ifmacro_builtin": "bits 64\n%ifmacro org\ndb 1\n%endif\n%ifmacro ORG 1\ndb 2\n%endif\n%ifmacro section 2\ndb 3\n%endif\n"
                       "%ifmacro struc 3\ndb 4\n%endif\n%ifmacro osabi\ndb 5\n%endif\n%ifmacro use64 0\ndb 6\n%endif\n"
                       "%ifnmacro iend 1\ndb 7\n%endif\n%ifmacro nosuch\ndb 8\n%endif\n",
})
ELF_PROBES.update({
    "elf_ifmacro_builtin": "%ifmacro org\ndb 1\n%endif\n%ifmacro osabi 1\ndb 2\n%endif\n%ifmacro global 3\ndb 3\n%endif\n",
})
# movnti takes no 66 for a 32-bit register in bits 16 (66 0F C3 is not
# movnti); adcx / adox / movbe / crc32 / popcnt / bswap as NASM in each mode
BIN_PROBES.update({
    "movnti_modes": "bits 16\nmovnti [si], eax\nmovnti [ebx], eax\nadcx eax, ebx\nadox eax, [ebx]\nmovbe eax, [ebx]\n"
                    "popcnt eax, ebx\nbswap eax\nbits 32\nmovnti [esi], eax\nmovnti [si], eax\n"
                    "bits 64\nmovnti [rsi], eax\nmovnti [rsi], rax\nmovnti [r9d], r10\n",
})
# branches to a number (an absolute target: E9 / E8 / 0F 8x, not FF /4
# through a garbage address); sizes written ("near", "strict") kept when
# code before them shrinks; MPX's MIB addresses (bndmk / bndldx / bndstx:
# a register with a scale written is the index, ICC's third operand the
# index, REX for r8-r15)
BIN_PROBES.update({
    "branch_to_number_16": "bits 16\norg 0x7c00\njmp 0x7c00\njmp 0\njz 0x7c10\ncall 0x8000\njmp near 5\n"
                           "call near 0x7c00\njmp short $+2\n",
    "branch_to_number_64": "bits 64\norg 0x400000\njmp 0x401000\ncall 0x402000\njnz 0x400000\njb 0x400020\n",
    "jump_size_kept": "bits 64\nfoo: nop\njz bar\nbar: jmp near foo\njmp strict near foo\njz near foo\n"
                      "jz baz\nbaz: jmp foo\n",
    "mpx_mib_64": "bits 64\nbndstx [r12+0x399], bnd3\nbndstx [rax+3], bnd0, rbx\nbndstx [rax+3], rbx, bnd0\n"
                  "bndstx [0], rcx, bnd2\nbndstx [rcx*1], bnd2\nbndstx [3,1*r12], bnd2\nbndstx [1*r12+3], bnd2\n"
                  "bndldx bnd2, [1*rbx+3]\nbndldx bnd1, [r11+0x1234]\nbndldx bnd2, [3], rbx\nbndmk bnd1, [3,1*r12]\n"
                  "bndmk bnd1, [r11]\nbndmk bnd1, [rcx*1]\nbndmov bnd1, [rcx*1]\n",
    "mpx_mib_32": "bits 32\nbndstx [eax+3], bnd0, ebx\nbndstx [0], ecx, bnd2\nbndstx [ecx*1], bnd2\n"
                  "bndldx bnd2, [3], ebx\nbndldx bnd2, [1*ebx+3]\nbndmk bnd1, [ecx*1]\nbndmov bnd1, [ecx*1]\n",
})
ELF_PROBES.update({
    "elf_branch_to_number": "section .text\njmp 0x1000\ncall 0x2000\njz 0x1000\n",
})
# a size written on a branch ("jmp word x" in bits 32: 66 E9 rel16, kept
# near); 32-bit PIC (wrt ..gotpc / ..got / ..gotoff / ..plt, the
# "_GLOBAL_OFFSET_TABLE_ + $$ - .getgot" idiom); ELF64's GOT forms by the
# field (GOTPCREL RIP-relative, GOT64 for a qword) and ..gotoff qword only
BIN_PROBES.update({
    "branch_sizes_32": "bits 32\nstart: jmp word start\njmp dword start\ncall word start\njz fwd\n"
                       "jmp word fwd\njmp dword fwd\ncall dword fwd\nfwd: nop\njmp strict word start\n",
    "branch_sizes_16": "bits 16\ns: jmp dword s\ncall dword s\njmp word s\njmp dword f\ncall word f\nf: nop\n",
})
ELF32_CASES.update({
    "pic_gotpc": "extern _GLOBAL_OFFSET_TABLE_, printf\nglobal greet:function\nsection .text\ngreet: push ebx\n"
                 "call .getgot\n.getgot: pop ebx\nadd ebx, _GLOBAL_OFFSET_TABLE_ + $$ - .getgot wrt ..gotpc\n"
                 "mov eax, [ebx + integer wrt ..got]\nmov [ebx + localint wrt ..gotoff], eax\n"
                 "lea eax, [ebx + msg wrt ..gotoff]\ncall printf wrt ..plt\npop ebx\nret\n"
                 "section .data\nglobal integer:data 4\ninteger: dd 1\nlocalint: dd 2\nmsg: db \"hi\", 0\n"
                 "dd _GLOBAL_OFFSET_TABLE_ wrt ..gotpc\ndd localint wrt ..gotoff\n",
})
ELF_PROBES.update({
    "elf_got_forms": "extern foo\nsection .text\nmov r15, [rel foo wrt ..got]\nlea r12, [rel foo wrt ..got]\n"
                     "mov rax, [qword foo wrt ..got]\nmov rax, [qword foo wrt ..gotoff]\nmov rax, [abs foo wrt ..got]\n"
                     "section .data\ndq foo wrt ..gotoff\n",
})
REJECT_CASES += [
    ("gotoff not qword", "elf64", "extern foo\nlea rax, [foo wrt ..gotoff]\n"),
    ("gotoff dd", "elf64", "extern x\nsection .data\ndd x wrt ..gotoff\n"),
]
# a RIP-relative wrt reference with an immediate after it: the addend
# counts the immediate (GOTPCREL "- 5"), as for a plain one
ELF_PROBES.update({
    "elf_got_trailing_imm": "default rel\nextern x\nsection .text\ncmp qword [x wrt ..got], 5\n"
                            "mov dword [x wrt ..got], 0x12345678\nadd qword [x wrt ..got], 9\n",
})
# utasm's own: after an error the assembly goes on, so every error is
# reported (NASM stops after its first pass's): (name, format, source, the
# lines with an error, the exit status - 4 the parser's first, 5 the
# encoder's). No output is written.
RECOVERY_CASES = [
    ("each kind", "elf64", "bits 64\nmov eax, ebx\nmov al, bx\nfoo bar\nadd rax, [rbx+rcx*3+rdx]\nnop\n"
                           "movq xmm0, cr0\ndb 1, 2, )\nret\n", [3, 4, 5, 7, 8], 5),
    ("every line", "elf64", "x y\nmov al, bx\nz w\n", [1, 2, 3], 4),
    ("labels after one", "bin", "bits 64\na: mov al, bx\nb: jmp a\nmov eax, b\nc: mov bl, cx\njmp c\n", [2, 5], 5),
    ("across sections", "elf64", "section .data\ndd )\nsection .text\nmov al, bx\nsection .data\ndb 1\n", [2, 4], 4),
    ("macro calls", "elf64", "%macro m 0\n  mov al, bx\n%endmacro\nm\nnop\nm\n", None, 5),
    ("after a missing include", "elf64", "%include \"nosuch.inc\"\nmov al, bx\n", [1, 2], 4),
    ("stops at 100", "elf64", "mov al, bx\n" * 120, list(range(1, 101)), 5),
]
# thread-local storage (GNU as's models; NASM has ..tlsie only): (name,
# format, source, the relocations as readelf -r shows them, GNU as's for the
# same code: (type, symbol, addend)), and the symbols that must be STT_TLS
_TLS64 = ("global x\nextern ext:tls\nsection .tbss\nx: resd 1\nz: resd 1\nsection .text\ndb 0x66\n"
          "lea rdi, [rel x wrt ..tlsgd]\nlea rdi, [rel x wrt ..tlsld]\nmov eax, [rax + x wrt ..dtpoff]\n"
          "mov eax, [fs:x wrt ..tpoff]\nmov rax, [rel x wrt ..gottpoff]\nmov eax, [fs:z wrt ..tpoff]\n"
          "mov rax, [rel ext wrt ..tlsie]\ncmp qword [rel x wrt ..gottpoff], 3\n"
          "section .debug_info\ndq x wrt ..dtpoff\ndd x wrt ..dtpoff\ndq x wrt ..tpoff\n")
TLS_CASES = [
    ("elf64 models", "elf64", _TLS64,
     [("R_X86_64_TLSGD", "x", -4), ("R_X86_64_TLSLD", "x", -4), ("R_X86_64_DTPOFF32", "x", 0),
      ("R_X86_64_TPOFF32", "x", 0), ("R_X86_64_GOTTPOFF", "x", -4), ("R_X86_64_TPOFF32", "z", 0),
      ("R_X86_64_GOTTPOFF", "ext", -4), ("R_X86_64_GOTTPOFF", "x", -5),
      ("R_X86_64_DTPOFF64", "x", 0), ("R_X86_64_DTPOFF32", "x", 0), ("R_X86_64_TPOFF64", "x", 0)],
     ["x", "z", "ext"]),
    ("elf32 models", "elf32", "global x\nsection .tbss\nx: resd 1\nsection .text\n"
     "lea eax, [ebx*1 + x wrt ..tlsgd]\nlea eax, [ebx + x wrt ..tlsld]\nmov eax, [eax + x wrt ..dtpoff]\n"
     "mov eax, [gs:x wrt ..tpoff]\nmov eax, [x wrt ..tlsie]\n",
     [("R_386_TLS_GD", "x", None), ("R_386_TLS_LDM", "x", None), ("R_386_TLS_LDO_32", "x", None),
      ("R_386_TLS_LE", "x", None), ("R_386_TLS_IE", "x", None)], ["x"]),
]
REJECT_CASES += [
    ("tlsie not RIP-relative", "elf64", "extern x\nsection .text\nmov rax, [x wrt ..tlsie]\n"),
]
# batch 49 (scripts/compat/encfuzz.py's findings): EVEX's disp8*N in 16-bit
# addressing, 3DNow!, the legacy forms the hand encoders had wrong, CMPccXADD,
# gathers in bits 32, immediates out of range (cut, as NASM, with its warning)
BIN_PROBES.update({
    "evex_disp8n_a16": "bits 16\nvpmovsdb qword [di-2], ymm4\nvpcmpeqb k1, zmm5, zword [di-2]\n"
                       "vmovdqu32 yword [bx+64], ymm5\nvmovdqu32 yword [bx+si+32], ymm5\nvpaddd zmm1, zmm2, [bp]\n"
                       "vpaddd zmm1, zmm2, [bx+0x1000]\nvpaddd zmm1, zmm2, [bp+di-128]\nvpaddd zmm1, zmm2, [si+128]\n",
    "amd_3dnow": "bits 64\nfemms\npfadd mm1, mm2\npfrsqrt mm7, [rax+rsi*4]\npi2fd mm1, [r9+8]\npfcmpeq mm4, mm5\n"
                 "pfmax mm0, [rcx]\npfmin mm1, mm1\npfrcp mm2, mm3\npfsub mm1, mm2\npswapd mm3, [r9+8]\n",
    "legacy_fixed_64": "bits 64\nlfs eax, [r15]\nlss r12d, [r14-8]\nlgs rcx, [r15]\nlfs dx, [rax]\nsenduipi r15\n"
                       "tpause r10d\nincsspq r10\nincsspd r15d\nrdsspq r12\nclrssbsy [rax+128]\nscasq\n"
                       "cmpsd xmm11, [r12-8], 7\nmovsd xmm1, [rax]\ncmpsd\nmovsd\nmovdir64b esi, [r10]\n"
                       "enqcmd ecx, [rcx]\nmovdir64b rsi, [r10]\nenqcmds edx, [rdx+0x12345]\n",
    "legacy_fixed_16_32": "bits 32\nlgs si, [eax+eax*1-128]\nlss ebp, [edx]\nbits 16\nlss bx, [si+1]\nlfs ebx, [4096]\n"
                          "prefetchwt1 byte [bp+1]\nprefetchwt1 [si+1]\n",
    "cmpccxadd": "bits 64\ncmpoxadd [rax], ecx, edx\ncmpnlexadd [r9], rcx, r8\ncmpbexadd [rsp+8], r11d, r12d\n"
                 "cmpzxadd [rdx], rax, rbx\ncmpnpxadd [r15+rax*4], ecx, eax\n",
    "gathers_32": "bits 32\nvgatherdps ymm6, [ecx+ymm4*4], ymm1\nvpgatherdd xmm0{k1}, [eax+xmm2*8-128]\n"
                  "vgatherdps xmm4{k4}, [xmm0*1-128]\nvpscatterdd [edi+zmm7*2+127]{k3}, zmm7\n",
    "imm_cut": "bits 64\npsllw mm7, 300\nshld eax, ebx, 300\nret 0x12345\nint 300\npshufd xmm1, xmm2, 300\n"
               "xabort 300\nenter 0x12345, 300\nvpermq ymm1, ymm2, 256\n",
})
# utasm's own: what objdump reads utasm's bytes as, where NASM's table is
# wrong (its AVX512-FP16 forms: VFMADD132PH is Intel's VFNMADD132PH, sources
# missing, roles swapped, the wrong widths) - (line, objdump's text), or
# (line, None, the error)
READBACK_CASES = [
    ("vfmadd132ph zmm1, zmm2, zmm3", "vfmadd132ph zmm1,zmm2,zmm3"),
    ("vfnmadd132ph zmm1, zmm2, zmm3", "vfnmadd132ph zmm1,zmm2,zmm3"),
    ("vfmsub231ph ymm1, ymm2, [rax]", "vfmsub231ph ymm1,ymm2,YMMWORD PTR [rax]"),
    ("vfmadd132sh xmm1, xmm2, xmm3", "vfmadd132sh xmm1,xmm2,xmm3"),
    ("vpmadd132sh xmm1, xmm2, xmm3", "vfmadd132sh xmm1,xmm2,xmm3"),
    ("vfnmsub213sh xmm1, xmm2, [rax]", "vfnmsub213sh xmm1,xmm2,WORD PTR [rax]"),
    ("vfmulcph zmm1, zmm2, zmm3", "vfmulcph zmm1,zmm2,zmm3"),
    ("vfcmulcph xmm1, xmm2, xmm3", "vfcmulcph xmm1,xmm2,xmm3"),
    ("vmaxph zmm1, zmm2, zmm3", "vmaxph zmm1,zmm2,zmm3"),
    ("vminsh xmm1, xmm2, xmm3", "vminsh xmm1,xmm2,xmm3"),
    ("vrndscaleph zmm1, zmm2, 4", "vrndscaleph zmm1,zmm2,0x4"),
    ("vrndscalesh xmm1, xmm2, xmm3, 4", "vrndscalesh xmm1,xmm2,xmm3,0x4"),
    ("vcvtqq2ph xmm1, zmm2", "vcvtqq2ph xmm1,zmm2"),
    ("vcvtuqq2ph xmm1, ymm2", "vcvtuqq2ph xmm1,ymm2"),
    ("vcvtdq2ph xmm1, ymm2", "vcvtdq2ph xmm1,ymm2"),
    ("vcvtdq2ph ymm1, zmm2", "vcvtdq2ph ymm1,zmm2"),
    ("vcvtpd2ph xmm1, zmm2", "vcvtpd2ph xmm1,zmm2"),
    ("vcvtps2phx xmm1, ymm2", "vcvtps2phx xmm1,ymm2"),
    ("vcvtneps2bf16 xmm3, xmm15", "vcvtneps2bf16 xmm3,xmm15"),
    ("vcvtneps2bf16 ymm3{k1}, zmm15", "vcvtneps2bf16 ymm3{k1},zmm15"),
    ("vp2intersectd k2, zmm3, zmm30", "vp2intersectd k2,zmm3,zmm30"),
    ("vp2intersectq k4, ymm1, [rax]", "vp2intersectq k4,ymm1,YMMWORD PTR [rax]"),
    ("vrcpph xmm6, xmm31", "vrcpph xmm6,xmm31"),
    ("vrsqrtsh xmm11{k6}{z}, xmm8, word [r9]", "vrsqrtsh xmm11{k6}{z},xmm8,WORD PTR [r9]"),
    ("vgetmantph xmm28{k3}, xmm19, 5", "vgetmantph xmm28{k3},xmm19,0x5"),
    ("vreducesh xmm5, xmm6, word [rcx+8], 7", "vreducesh xmm5,xmm6,WORD PTR [rcx+0x8],0x7"),
    ("vgetexpsh xmm1, xmm2, xmm3", "vgetexpsh xmm1,xmm2,xmm3"),
    ("vgetmantsh xmm1, xmm2, xmm3, 5", "vgetmantsh xmm1,xmm2,xmm3,0x5"),
    ("vpgatherdd xmm3{k1}, dword [r9+xmm30*1]", "vpgatherdd xmm3{k1},DWORD PTR [r9+xmm30*1]"),
    ("eadd", "mov eax,0x1 ; encls"),
    ("eenter", "mov eax,0x2 ; enclu"),
    ("vfcmaddcph xmm28, xmm28, xmm16", None, "#UD"),
    ("vfmulcsh xmm1, xmm2, xmm1", None, "#UD"),
    ("vfmaddcph zmm1, zmm2", None, "#UD"),
    ("vpgatherqd xmm15, dword [xmm24*8+128], xmm14", None, "invalid combination"),
    ("vfmadd132ps xmm1, xmm2", None, "invalid combination"),
]

# batch 50: GNU as's directives (frontend/parser/gas.s), the same source by
# GNU as (".intel_syntax noprefix" first) and by utasm - (name, source)
GAS_CASES = [
    ("data", ".data\nd1: .byte 1, 2, 3\n.short 0x1234\n.word 5\n.hword 6\n.value 7\n.2byte 8\n"
             ".long 0x11223344\n.int 9\n.4byte 10\n.quad -1\n.8byte 11\n.octa 1\n"),
    ("strings", r'''.section .rodata
.ascii "ab", "c"
.asciz "hi\n\t\x41\101\\\""
.string "x"
.ascii "\0\12\x7f\e\a\b\f\v\r"
'''),
    ("space", ".data\n.zero 3\n.skip 2, 0xAA\n.space 4, 1\n.fill 3, 2, 0x0102\n.fill 2, 8, -1\n.fill 2\n"
              ".bss\nb: .zero 8\n.skip 16\n"),
    ("leb128", ".data\n.uleb128 0, 127, 128, 624485\n.sleb128 0, -1, 63, 64, -64, -65, -123456\n"),
    ("align", ".text\nf: ret\n.p2align 4,,10\ng: nop\n.balign 8\nh: nop\n.align 32\nnop\n.p2align 2\nret\n"
              ".data\n.byte 1\n.balign 8\n.byte 2\n.p2align 4, 0xCC\n.byte 3\n.balign 4, 0x55, 3\n.byte 4\n"),
    ("sections", ".section .rodata.str1.1,\"aMS\",@progbits,1\n.asciz \"m\"\n"
                 ".section .tdata,\"awT\",@progbits\n.long 7\n.section .tbss,\"awT\",@nobits\n.zero 4\n"
                 ".section .init_array,\"aw\",@init_array\n.quad 0\n"
                 ".section .note.test,\"a\",@note\n.long 1\n.section .mytext,\"ax\",@progbits\nret\n"
                 ".section .rodata.cst8,\"aM\",@progbits,8\n.quad 1\n"),
    ("section stack", ".data\n.long 1\n.pushsection .rodata\n.long 2\n.pushsection .text\nnop\n.popsection\n"
                      ".long 3\n.popsection\n.long 4\n.text\nret\n.previous\n.long 5\n.previous\nret\n"),
    ("symbols", ".text\n.globl f\n.type f, @function\nf: ret\n.size f, .-f\n.global g\n.type g, function\n"
                "g: nop\nret\n.size g, .-g\n.data\n.globl o\n.type o, @object\no: .long 1, 2\n.size o, 8\n"
                ".weak w\nw: .long 0\n.hidden w\n.globl p\n.protected p\np: .byte 0\n"
                ".type t, @tls_object\n.section .tdata,\"awT\",@progbits\nt: .long 1\n"),
    ("constants", ".equ K, 3\n.set V, 1\n.set V, 2\n.equiv E, 4\n.data\n.byte K, V, E\nhere: .long . - here\n"
                  ".set V, 9\n.byte V\n"),
    ("common", ".comm cblk, 32, 8\n.comm c2, 4\n.lcomm lbuf, 16\n.data\n.long 1\n"),
    ("org", ".data\n.byte 1\n.org 8\n.byte 2\n.org 12, 0xEE\n.byte 3\n"),
    ("relocations", ".extern ext\n.text\n.globl _start\n_start: call ext\njmp ext\n.data\n.quad ext\n.long ext\n"
                    ".quad _start\n"),
    ("ignored", ".file \"x.c\"\n.ident \"cc\"\n.text\n.code64\nf: ret\n"),
    # GCC's: an offset before a RIP-relative name ("40+x(%rip)")
    ("rip offset", ".text\nmov rax, QWORD PTR x[rip+40]\nlea rcx, 8+x[rip]\nmov eax, DWORD PTR 40+x[rip]\n"
                   ".att_syntax\nmovq 40+x(%rip), %rax\n.data\nx: .zero 64\n"),
    ("base64", ".data\n.base64 \"aGVsbG8=\"\n.base64 \"AAEC\"\n.byte 9\n"),
    # .lcomm / .local+.comm: after the .bss data written, wherever they are
    ("local commons", ".data\n.long 1\n.bss\n.zero 2\n.lcomm lb, 16\n.local lc\n.comm lc, 4, 4\n"
                      ".bss\nafter: .zero 3\n"),
    # GNU as's relaxation: jumps grow from short, never back; a backward
    # one too; across an alignment the stretch stops
    ("gnu relaxation", ".text\nf: jmp 1f\n.p2align 4\n1: je f\njne 2f\n.fill 130,1,0x90\n2: jmp f\n"
                       ".L2: jmp .L2\nje 3f\n.balign 8\n3: ret\n.p2align 4,,10\n.p2align 3\ng: jne f\n"),
    # padding after data starts with a plain nop
    ("nops after data", ".text\nret\n.byte 1\n.p2align 3\nnop\n.p2align 4\nret\n"),
    # a jmp / jcc to a global of the section: resolved; a call, a weak
    # one, @PLT: the linker's
    ("jumps to globals", ".text\n.globl f\n.type f,@function\nf: ret\n.weak w\nw: ret\ng: jmp f\njne f\n"
                         "jmp w\ncall f\njmp h\n.att_syntax\njmp f@PLT\n.globl h\nh: ret\n"),
    # GCC's ".set f.localalias, f": moves with f, its type and size
    ("set alias", ".text\n.globl f\n.type f,@function\ng: jmp 1f\nnop\n1: ret\n.p2align 4\nf: jne g\nret\n"
                  ".size f, .-f\n.set f.la, f\n.set g2, g+1\ncall f.la\njmp f.la\n"),
    # a segment the address uses anyway is left out; a string
    # instruction's es:[rdi] never takes one
    ("default segments", ".text\nmovzx eax, BYTE PTR ds:0\nmov eax, ss:[rbp]\nmov eax, ds:[rbp]\n"
                         "mov eax, ss:[rsp+4]\nmov eax, ss:[r13]\nmov eax, ds:[rip+5]\n"
                         "movsb es:[rdi], fs:[rsi]\ncmpsb [rsi], es:[rdi]\nstosb es:[rdi]\nmov eax, es:[rdi]\n"),
    # GCC's indirect call: "[QWORD PTR 80[rax]]"
    ("bracketed ptr", ".text\ncall [QWORD PTR 80[rax]]\njmp [QWORD PTR 8[rsp]]\nmov [DWORD PTR 4[rbx]], 7\n"
                      "call [QWORD PTR f[rip]]\nf: ret\n"),
]
# (line, the error)
GAS_ERRORS = [
    (".data\n.byte 1, 2\n.org 1", "backwards"),
    (".section .rodata.cst8,\"aM\",@progbits", "SHF_MERGE"),
    (".type f, @nonsense\nf:", "unrecognized symbol type `nonsense'"),
    (".popsection", ".popsection without"),
    (".equiv E, 1\n.equiv E, 2", "inconsistently redefined"),
    (".p2align 40", "alignment"),
    (".balign 3", "alignment"),
    (".data\n.base64 \"aGV$sbG8=\"", "invalid character found inside .base64 string"),
]
# batch 51: GNU as's macros, repetitions and conditionals
# (frontend/parser/gas_macro.s), and its rip addressing
GAS_CASES += [
    ("macros", r'''.text
.macro push2 a, b
    push \a
    push \b
.endm
.macro sum from=0, to=5
    .long \from
    .if \to-\from
    sum "(\from+1)",\to
    .endif
.endm
.macro lbl name
\name\()_x: .byte 1
.endm
.macro req a:req, b=7
    .byte \a, \b
.endm
.macro va first, rest:vararg
    .byte \first
    .byte \rest
.endm
.macro cnt
    .byte \@
.endm
.macro Mixed Case
    .byte \Case
.endm
f:
    push2 rax, rbx
    push2 rcx rdx
.data
    sum 0, 3
    lbl foo
    req 1
    req b=2, a=3
    va 1, 2, 3, 4
    cnt
    cnt
    MIXED 4
    mixed 5
.macro early n
  .if \n == 2
    .exitm
  .endif
  .byte \n
.endm
    early 1
    early 2
    early 3
.purgem early
'''),
    ("repetitions", r'''.data
.rept 3
    .byte 0xAA
.endr
.rept 0
    .byte 0xBB
.endr
.irp r, 1, 2, 3
    .byte \r * 2
.endr
.irp r 4 5
    .byte \r
.endr
.irpc c, 123
    .byte \c
.endr
.irp x
    .byte 9
.endr
.irp a, 1, 2
  .irp b, 3, 4
    .byte \a\b
  .endr
.endr
.rept 2
  .rept 2
    .byte 0x55
  .endr
.endr
'''),
    ("conditionals", r'''.data
.if 0
    .byte 0x10
.elseif 1
    .byte 0x11
.else
    .byte 0x12
.endif
.ifeq 0
    .byte 0x13
.endif
.ifgt 1
    .byte 0x14
.endif
.iflt -1
    .byte 0x15
.endif
.ifge 0
    .byte 0x16
.endif
.ifle 1
    .byte 0x17
.endif
here:
.ifdef here
    .byte 0x20
.endif
.ifndef nope
    .byte 0x21
.endif
.ifb
    .byte 0x22
.endif
.ifnb x
    .byte 0x23
.endif
.ifc a,a
    .byte 0x24
.endif
.ifnc a,b
    .byte 0x25
.endif
.ifc 'a','a'
    .byte 0x28
.endif
.ifc 'a', a
    .byte 0x29
.endif
.ifc a b,a b
    .byte 0x2A
.endif
.extern ext
.ifdef ext
    .byte 0x2B
.endif
.ifeqs "x", "x"
    .byte 0x26
.endif
.ifnes "x", "y"
    .byte 0x27
.endif
.if 1
  .if 0
    .byte 0x30
  .else
    .byte 0x31
  .endif
.else
    .byte 0x32
.endif
.if 0
  .if 1
    .byte 0x40
  .endif
  .byte 0x41
.endif
'''),
    ("nested macros", r'''.macro outer n
  .rept \n
    .byte \n
  .endr
  .irp v, 7, 8
    .rept 2
      .byte \v
    .endr
  .endr
  .macro inner_\n
    .byte 0x\n\n
  .endm
  inner_\n
.endm
.data
outer 2
outer 3
inner_2
'''),
    ("rip addressing", r'''.text
.globl f
f:
    mov edi, OFFSET FLAT:x
    mov rax, QWORD PTR x[rip]
    lea rsi, .LC0[rip]
    mov eax, DWORD PTR [rip+x+4]
    lea rax, [rip + x]
    lea rax, [rip]
    lea rax, [rip - 16]
    mov eax, DWORD PTR 8[rbp]
    movss xmm0, DWORD PTR .LC1[rip]
    ret
.section .rodata
.LC0: .string "hi"
.LC1: .long 1065353216
.data
x: .quad 0, 0
'''),
]
GAS_ERRORS += [
    (".macro m\n.byte 1", "unexpected end of file in macro `m' definition"),
    (".endm", "`.endm' with nothing open"),
    (".endr", "`.endr' with nothing open"),
    (".endif", "`.endif' with nothing open"),
    (".else", "`.else' with nothing open"),
    (".exitm", "`.exitm' with nothing open"),
    (".data\n.if 1\n.byte 1", "end of file in conditional"),
    (".macro m a:req\n.endm\nm", "missing value for required parameter `a'"),
    (".macro m a\n.endm\nm 1, 2", "too many positional arguments"),
    (".macro m a\n.endm\nm z=1", "no macro parameter named `z'"),
    (".purgem nope", "macro `nope' not defined"),
    (".rept 2\n.byte 1", "`.rept' without .endr"),
    (".macro m a:bogus\n.endm", "bad .macro parameter list"),
    (".macro r\nr\n.endm\nr", "macros nested too deeply"),
    ("%macro nm 0\n.rept 2\nnop\n.endr\n%endmacro\nnm", "inside a NASM macro or %rep"),
    ("mov eax, [rip + rax]", "invalid effective address"),
]

# batch 52: GNU's comments (a "#" first on a line, /* */), and -X json
GAS_CASES += [
    # (";" stays NASM's comment: GNU as on x86 takes it between statements)
    ("comments", r"""# 1 "a.c"
  # a comment line
.data
.byte 1 /* a comment */
/* a block
   comment */
.byte 2
// to the end of the line
.byte 3
"""),
]
# (name, source): -X json's objects are the text messages, field by field
JSON_CASES = [
    ("errors", "section .text\nmovv eax, 1\nmov [rip + rax], eax\ndb 1 # 2\n"),
    ("warnings", "orphan\nmov eax, [qword 5]\n"),
    ("macro note", "%macro m 0\n  movv eax, 1\n%endmacro\nm\n"),
    ("lexer", "db 1\nmov eax, \x01\n"),
    ("no place", "%fatal stop\n"),
    ("quotes", "%error \"a\" \\ b\n"),
]

# batch 53: map files, as NASM's bin format writes them - (name, source);
# the map file is m.map
MAP_CASES = [
    ("all", """[map all m.map]
bits 16
org 0x7c00
section .text
start: jmp main
msg: db "hi", 0
main: mov ax, msg
section .data align=16
val: dw 1
section .bss
buf: resb 64
K equ 5
"""),
    ("symbols", """[map all m.map]
bits 16
section .data
b: db 1
a: db 2
.loc: db 3
%macro mm 0
%%x: db 4
%endmacro
mm
struc st
.f: resb 1
endstruc
section .bss
z: resb 4
"""),
    ("options", """[map brief m.map]
[map symbols other.map]
bits 32
nop
x: ret
"""),
    ("brief", """[map brief m.map]
bits 64
section .text
nop
section .data
dd 1
"""),
    ("sections", """[map sections m.map]
bits 64
section .text
nop
section .two follows=.text
db 1, 2, 3
section .three vstart=0x1000
dq 0
"""),
    ("vstart", """[map all m.map]
bits 16
org 0x100
section .text
call far_fn
ret
section .far vstart=0x2000 align=16
far_fn: retf
section .bss
stack: resw 32
top:
"""),
]

# batch 53: FASM's virtual / load / store / defined and "NAME = EXPR"
# (frontend/parser/fasm.s) - (name, source, the flat binary's bytes in hex),
# or (name, source, None, the error)
FASM_CASES = [
    ("virtual load", "bits 64\nvirtual at 0\nmov eax, ebx\nlen = $\nload op byte from 0\n"
                     "load op2 byte from 1\nend virtual\ndb len, op, op2\n", "0289d8"),
    ("load store", "bits 64\ndata: db 1, 2, 3, 4\nload w word from data + 1\ndw w\n"
                   "store byte 0xAA at data\nstore word 0x1234 at data + 2\n", "aa0234120203"),
    ("store dword qword", "bits 64\nd: dq 0\nstore qword 0x1122334455667788 at d\n"
                          "load x dword from d + 4\ndd x\n", "887766554433221144332211"),
    ("virtual nested", "bits 64\nvirtual at 0x100\na: dq 0\nb: dd 0\nvirtual at 0\nc: db 0\n"
                       "end virtual\nd:\nend virtual\ndw a, b, c, d\n", "000108010000" + "0c01"),
    ("virtual here", "bits 64\nnop\nvirtual\nv1: db 0, 0\nv2:\nend virtual\ndb v2 - v1\nnop\n", "900290"),
    ("defined", "bits 64\ndata: db 1\ndb defined data, defined nope, defined(data), defined later\n"
                "later: db defined later\n", "010100010001"),
    ("assign", "x = 1\nx = x + 1\nx = x * 3\ndb x\ny = x == 6\ndb y\n", "0601"),
    ("checksum", "bits 64\nmsg: db 'hello'\nsum = 0\n%assign i 0\n%rep 5\nload b byte from msg + i\n"
                 "sum = sum + b\n%assign i i+1\n%endrep\ndb sum & 0xFF\n", "68656c6c6f14"),
    ("names kept", "load equ 5\nstore: db load\nvirtual: db 1\n", "0501"),
    ("load past the end", "d: db 1\nload x word from d\n", None, "outside the bytes assembled"),
    ("load later", "load x byte from later\nlater: db 1\n", None, "not final yet"),
    ("load a jump", "j: jmp far_away\nload x byte from j+1\ntimes 300 nop\nfar_away:\n", None, "not final yet"),
    ("end virtual alone", "end virtual\n", None, "`end virtual' with nothing open"),
    ("virtual open", "virtual at 0\ndb 1\n", None, "`virtual' with no `end virtual'"),
    ("assign a label", "label: nop\nlabel = 5\n", None, "inconsistently redefined"),
]

# batch 54: MASM's PROC / LOCAL / INVOKE / .IF & co (frontend/parser/masm.s)
# - a program that uses all of them, its exit status their sum; then each
# error
MASM_PROGRAM = (r"""bits 64
%use masm
global _start
section .text

; sum of 1..n, with a LOCAL and .WHILE
sumto PROC uses rbx, n:QWORD
    LOCAL acc:QWORD, i:DWORD
    mov acc, 0
    mov i, 1
    mov edx, dword ptr n
    .WHILE i <= edx
        mov eax, i
        add acc, rax
        inc i
    .ENDW
    mov rax, acc
    ret
sumto ENDP

; max of two signed ints, .IF/.ELSE
maxs PROC a:DWORD, b:DWORD
    mov eax, a
    .IF sdword ptr eax < b
        mov eax, b
    .ENDIF
    ret
maxs ENDP

; classify: .IF/.ELSEIF chains with && and ||
klass PROC x:QWORD
    mov rax, x
    .IF rax == 0
        mov eax, 10
    .ELSEIF (rax > 5 && rax < 10) || rax == 42
        mov eax, 20
    .ELSE
        mov eax, 30
    .ENDIF
    ret
klass ENDP

; seven arguments: the seventh on the stack
seven PROC a:QWORD, b:QWORD, c:QWORD, d:QWORD, e:QWORD, f:QWORD, g:QWORD
    mov rax, a
    add rax, g
    ret
seven ENDP

_start:
    invoke sumto, 10            ; 55
    mov r12, rax
    invoke maxs, -5, 3          ; 3
    add r12, rax
    invoke klass, 0             ; 10
    add r12, rax
    invoke klass, 7             ; 20
    add r12, rax
    invoke klass, 42            ; 20
    add r12, rax
    invoke klass, 9999          ; 30
    add r12, rax
    invoke seven, 1, 2, 3, 4, 5, 6, 100   ; 101
    add r12, rax
    mov ecx, 3
    xor ebx, ebx
    .REPEAT
        inc ebx
    .UNTILCXZ
    add r12, rbx                ; 3
    xor ebx, ebx
    .REPEAT
        inc ebx
        .BREAK .IF ebx == 4
    .UNTIL ebx > 100
    add r12, rbx                ; 4
    ; 55+3+10+20+20+30+101+3+4 = 246
    mov rdi, r12
    mov eax, 60
    syscall
""", 246)
MASM_ERRORS = [
    ("extern f\ninvoke f, rsi, rdi\n", "reads a register an earlier argument was loaded into"),
    ("f PROC\ng PROC\nret\ng ENDP\n", "PROC inside a PROC"),
    ("f PROC\nret\ng ENDP\n", "ENDP's name is not the PROC's"),
    (".ENDIF\n", "`.endif' with nothing open"),
    (".IF eax == 1\nnop\n", ".IF / .WHILE / .REPEAT with no end"),
    ("g ENDP\n", "ENDP with no PROC open"),
    (".BREAK\n", "`.break' with nothing open"),
    ("f PROC\nret\n", "PROC `f' with no ENDP"),
    ("f PROC\nnop\nLOCAL x:DWORD\nret\nf ENDP\n", "LOCAL needs the PROC's frame"),
]
# (name, bits, format, source, objdump's text of it): 32-bit and Win64
MASM_CODE = [
    ("stdcall 32", "elf32", """bits 32
%use masm
section .text
f PROC STDCALL a:DWORD, b:DWORD
mov eax, a
add eax, b
ret
f ENDP
main:
invoke f, 1, 2
""", ["push ebp", "mov ebp,esp", "sub esp,0x0", "mov eax,DWORD PTR [ebp+0x8]", "add eax,DWORD PTR [ebp+0xc]",
      "leave", "ret 0x8", "push 0x2", "push 0x1", "call 0 <f>"]),
    ("win64", "win64", """bits 64
%use masm
section .text
f PROC a:QWORD, b:QWORD, c:QWORD, d:QWORD, e:QWORD
mov rax, a
add rax, e
ret
f ENDP
main:
invoke f, 1, 2, 3, 4, 5
""", ["mov QWORD PTR [rbp+0x10],rcx", "mov QWORD PTR [rbp+0x28],r9", "add rax,QWORD PTR [rbp+0x30]",
      "sub rsp,0x8", "push 0x5", "mov ecx,0x1", "mov r9d,0x4", "sub rsp,0x20", "add rsp,0x30"]),
    ("signed and flags", "elf64", """bits 64
%use masm
section .text
.IF sdword ptr eax < ebx
nop
.ENDIF
.IF CARRY? || !ZERO?
int3
.ENDIF
.IF eax & 4
hlt
.ENDIF
""", ["cmp eax,ebx", "jge", "jb", "je", "test eax,0x4", "je"]),
]

# batch 55: MASM's typed data and STRUCT (frontend/parser/masm.s) - a
# program reading them (its exit status), each error, and the text made
MASM_DATA_PROGRAM = (r"""bits 64
%use masm
global _start

POINT STRUCT
    x   DWORD ?
    y   DWORD 7
    tag BYTE "ab"
    pad BYTE 3 DUP (?)
POINT ENDS

.data
count   DWORD 10
big     QWORD 1000
arr     DWORD 1, 2, 3, 4
buf     BYTE 16 DUP (0)
msg     BYTE "hi", 0
pt      POINT <5, , >
pt2     POINT {}
.data?
scratch QWORD 4 DUP (?)
.code
_start:
    mov eax, count              ; 10 (memory, typed)
    add eax, pt.x               ; +5
    add eax, pt.y               ; +7 (the default)
    add eax, pt2.y              ; +7
    lea rbx, pt
    add eax, [rbx].POINT.y      ; +7
    add eax, SIZEOF POINT       ; +13 (4+4+2+3)
    add eax, LENGTHOF arr       ; +4
    add eax, SIZEOF arr         ; +16
    add eax, TYPE big           ; +8
    add eax, LENGTHOF buf       ; +16
    movzx ecx, byte ptr pt.tag  ; 'a' = 97
    add eax, ecx
    mov rdx, OFFSET arr
    add eax, [rdx + 8]          ; +3
    mov scratch, rax            ; (bss, typed)
    add eax, dword ptr big      ; +1000
    ; 10+5+7+7+7+13+4+16+8+16+97+3+1000 = 1193 -> & 255 = 169
    mov edi, eax
    and edi, 255
    mov eax, 60
    syscall
""", 169)
MASM_ERRORS += [
    ("mov eax, sizeof nope\n", "SIZEOF / LENGTHOF / TYPE of `nope'"),
    ("P STRUCT\nx DWORD ?\nP ENDS\nlea rbx, [rel x]\nmov eax, [rbx].P.nope\n", "no structure field `P.nope'"),
    ("A STRUCT\nx DWORD ?\nB ENDS\n", "ENDS's name is not the STRUCT's"),
    ("A STRUCT\nx DWORD ?\n", "STRUCT `A' with no ENDS"),
]
MASM_CODE += [
    ("data", "elf64", """bits 64
%use masm
section .data
v DWORD 5
w WORD 1, 2
section .text
mov eax, v
mov ax, w
mov rbx, OFFSET v
add v, 3
lea rcx, v
""", ["mov eax,DWORD PTR [rip+0x0]", "mov ax,WORD PTR [rip+0x0]", "movabs rbx,0x0", "add DWORD PTR [rip+0x0],0x3",
      "lea rcx,[rip+0x0]"]),
]

# batch 57: FASM's format / entry / segment - an executable written from
# the source alone (its output and exit status), and the errors
FASM_EXECUTABLE = (r"""format ELF64 executable 3
entry start

segment readable executable
start:
    mov eax, 1
    mov edi, 1
    lea rsi, [rel msg]
    mov edx, msg_len
    syscall
    mov eax, 60
    mov edi, [rel code]
    syscall

segment readable writeable
code dd 7

segment readable
msg db "hello, fasm", 10
msg_len = $ - msg
""", b"hello, fasm\n", 7)
FASM_CASES += [
    ("format other", "format PE64 console\nnop\n", None, "format `PE64': not the output format"),
    ("format binary", "format binary\nbits 64\nnop\n", "90"),
    ("nasm segment", "bits 64\nsegment .data\ndb 1\nsection .text\nnop\n", "90" + "00" * 3 + "01"),
]

# batch 57: Cyrix's rsdc / svdc (a segment register and an 80-bit
# operand: the mode check took segment registers for mov / push / pop only)
BIN_PROBES.update({
    "cyrix_smm": "bits 32\nrsdc es, [ebx]\nrsdc ds, [bx]\nsvdc [eax], es\nsvdc tword [ebx], ss\n"
                 "bits 16\nrsdc cs, [di+4]\nsvdc [bx], ds\n",
})

# batch 59: NASM's optimistic sizing - a sign-extended imm8 for a value not
# worked out yet in pass 1, kept when it fits (and grown when not); Cyrix's
# smint / rdm / bb0_reset (0f 38 / 0f 3a alone); push byte of a label
BIN_PROBES.update({
    "optimistic_add": "bits 32\ns1:\nadd eax, s2 - s1\ntimes 124 nop\ns2:\n",
    "optimistic_reg": "bits 32\ns1:\nadd ecx, s2 - s1\ntimes 124 nop\ns2:\n",
    "optimistic_push": "bits 32\ns1:\npush s2 - s1\ntimes 125 nop\ns2:\n",
    "optimistic_imul": "bits 32\ns1:\nimul ecx, edx, s2 - s1\ntimes 124 nop\ns2:\n",
    "optimistic_grows": "bits 32\nc1:\npush c2 - c1\ntimes 125 nop\nc2:\npush c3 - c2\n"
                        "times 200 nop\nc3:\nadd eax, c4 - c3\ntimes 126 nop\nc4:\n",
    "optimistic_expr": "bits 64\ns1:\nsub rsp, (s2 - s1) / 2\ntimes 200 nop\ns2:\n",
    "optimistic_strict": "bits 32\ns1:\nadd eax, strict dword s2 - s1\ntimes 124 nop\ns2:\n",
    "cyrix_smint": "bits 32\nsmint\nrdm\nbb0_reset\nbits 16\nsmint\n",
})
ELF_PROBES.update({
    "push_byte_label": "bits 32\nextern ext\npush byte ext\npush ext\n",
})
REJECT_CASES += [
    ("smint in 64-bit", "bin", "bits 64\nsmint\n"),
    ("rdshr in 64-bit", "bin", "bits 64\nrdshr eax\n"),
    ("svdc in 64-bit", "bin", "bits 64\nsvdc [rax], ds\n"),
    ("cpu_read in 64-bit", "bin", "bits 64\ncpu_read\n"),
]

# AT&T syntax (frontend/parser/att.s, --att): each line assembled by GNU as and
# by utasm --att - the same .text bytes and relocation types (suites.att)
ATT_LINES_64 = r'''
fsub %st, %st(1)
fsub %st(1), %st
fsubr %st, %st(1)
fsubp %st, %st(1)
fsubp
fsubrp
fdiv %st, %st(2)
fdivp
fdivrp %st, %st(3)
fadd %st, %st(1)
faddp
fsubs (%rax)
fsubl (%rax)
fisubs (%rax)
fisubl (%rax)
fildll (%rax)
fildq (%rax)
fistpll (%rax)
fldt (%rax)
fstpt (%rax)
flds 4(%rsp)
fnstsw %ax
fcmovb %st(1), %st
rep
lock
rep; movsb
repz ret
lock incl (%rax)
lock cmpxchgq %rcx, 8(%rdi)
rep stosq
rep movsl %ds:(%rsi), %es:(%rdi)
rep stos %rax, %es:(%rdi)
movsb %fs:(%rsi), %es:(%rdi)
lods %ds:(%rsi), %eax
cmps %es:(%rdi), %ds:(%rsi)
xlat %fs:(%rbx)
movsl
cmpsb (%rdi), (%rsi)
stosl %eax, %es:(%rdi)
shll %eax
shll (%rax)
sarw $3, %ax
shrq %cl, %rdx
shldl %cl, %eax, %ebx
shld $3, %eax, %ebx
movq %rax, %rbx
movq %xmm0, %rax
movq (%rax), %xmm1
movq $5, %rax
movq $-1, %rax
movq $0x100000000, %rax
movq $foo, %rax
movabsq $5, %rax
movabs 0x1234, %eax
movabs foo, %rax
movl $foo, %eax
movl foo, %eax
movl %fs:0x28, %eax
movq %fs:0, %rax
inb (%dx), %al
outw %ax, (%dx)
inl $0x60, %eax
enter $16, $0
lcall *8(%rbx)
jmp *%rax
call *(%rax,%rcx,8)
jmpq *8(%rax)
call *foo(,%rax,8)
lret
lretq
lret $8
retq
cltq
cqto
cwtl
cltd
movslq %eax, %rbx
movzbl (%rax), %ecx
movsbw %al, %cx
movzwq %ax, %rbx
movswl -2(%rbp), %eax
pushq $5
pushw $5
pushq (%rax)
push 8(%rip)
popw (%rax)
nopw 0x0(%rax,%rax,1)
nopl (%rax)
leaq foo(%rip), %rax
leaq 8(%rip), %rax
leaq -16(%rbp,%rcx,8), %rdi
leaq (,%rcx,4), %rdx
movl foo@GOTPCREL(%rip), %eax
movq foo@GOTPCREL(%rip), %rax
call foo@PLT
jmp foo@PLT
movq %fs:foo@TPOFF, %rax
leaq foo@TLSGD(%rip), %rdi
imul $5, %eax, %ebx
imulq $1000, (%rax), %rcx
cvtsi2sdl (%rax), %xmm0
cvtsi2sdq %rax, %xmm0
cvttsd2siq (%rax), %rbx
vcvtpd2psx (%rax), %xmm0
vcvtpd2psy (%rax), %xmm0
vaddps {rn-sae}, %zmm2, %zmm1, %zmm0
vaddps (%rax){1to16}, %zmm1, %zmm0{%k1}{z}
vmovdqu64 %zmm1, -64(%rsp){%k2}
vpaddd %ymm1, %ymm2, %ymm3
vfmadd231ps (%rdi,%rax,4), %ymm1, %ymm0
xchg %eax, %ebx
testb $1, (%rax)
bt $3, %eax
btl $3, (%rax)
setl %al
cmovll %eax, %ebx
iretq
sysretq
swapgs
movl $017, %eax
movl $0x1f, %eax
movl $0b101, %eax
addl $(3 << 4) | 1, %eax
movl -4(%rbp), %eax # comment
addq $8, %rsp ; addq $8, %rsp
movw %ds, %ax
movq %cr0, %rax
'''
ATT_LINES_32 = r'''
pushl $5
pushl (%eax)
movl 8(%ebp), %eax
leal (%eax,%ebx,2), %ecx
calll *%eax
ljmp $0x10, $0x1000
lcall $8, $foo
lcall *8(%ebx)
movzwl (%esi), %eax
movsbl %al, %edx
fildll (%esp)
pushfl
popal
inb $0x60, %al
call foo@PLT
movl foo@GOT(%ebx), %eax
leal foo@GOTOFF(%ebx), %eax
movl %gs:foo@NTPOFF, %eax
'''
# whole sources, compared section by section (suites.gas's gas_view)
ATT_FILES = [
    ("function", r'''	.file	"f.c"
	.text
	.p2align 4
	.globl	f
	.type	f, @function
f:
.LFB0:
	.cfi_startproc
	testl	%edi, %edi
	jle	.L4
	pushq	%rbx
	.cfi_def_cfa_offset 16
	.cfi_offset 3, -16
	movl	%edi, %ebx
	call	g@PLT
	addl	%ebx, %eax
	popq	%rbx
	.cfi_def_cfa_offset 8
	ret
	.p2align 4,,10
	.p2align 3
.L4:
	xorl	%eax, %eax
	ret
	.cfi_endproc
.LFE0:
	.size	f, .-f
	.section	.note.GNU-stack,"",@progbits
'''),
    ("data and locals", r'''	.text
	.globl	main
	.type	main, @function
main:
	leaq	.LC0(%rip), %rdi
	leaq	jb(%rip), %rsi
	movsd	.LC1(%rip), %xmm0
	call	puts@PLT
	call	main
	xorl	%eax, %eax
	ret
	.size	main, .-main
	.section	.rodata.str1.1,"aMS",@progbits,1
.LC0:
	.string	"hello"
	.section	.rodata.cst8,"aM",@progbits,8
	.align 8
.LC1:
	.long	0
	.long	1073741824
	.local	jb
	.comm	jb,200,32
	.comm	shared,8,8
'''),
    ("jump table", r'''	.text
	.globl	sw
	.type	sw, @function
sw:
	cmpl	$3, %edi
	ja	.L1
	leaq	.L3(%rip), %rdx
	movslq	(%rdx,%rdi,4), %rax
	addq	%rdx, %rax
	jmp	*%rax
	.section	.rodata
	.align 4
.L3:
	.long	.L6-.L3
	.long	.L5-.L3
	.long	.L4-.L3
	.long	.L2-.L3
	.text
.L6:	movl $1, %eax
	ret
.L5:	movl $2, %eax
	ret
.L4:	movl $3, %eax
	ret
.L2:	movl $4, %eax
	ret
.L1:	xorl %eax, %eax
	ret
	.size	sw, .-sw
'''),
    ("numeric labels", "f:\n1: decl %eax\njnz 1b\njmp 2f\nnop\n2: ret\n"),
    ("tls", "\t.text\n\tmovl %fs:x@tpoff, %eax\n\tmovq x@gottpoff(%rip), %rax\n\t.section .tbss,\"awT\",@nobits\n\t.globl x\nx:\t.zero 4\n"),
]
# a C program, compiled by GCC to AT&T assembly (when gcc is there)
ATT_C = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
#include <stdarg.h>
__thread int tls_counter = 3;
static jmp_buf jb;
int dispatch(int op, int a, int b) {
    switch (op) {
    case 0: return a + b; case 1: return a - b; case 2: return a * b; case 3: return b ? a / b : 0;
    case 4: return a & b; case 5: return a | b; case 6: return a ^ b; case 7: return a << (b & 31);
    case 8: return a >> (b & 31); case 9: return a % (b ? b : 1); default: return -1;
    }
}
long double ldsum(int n, ...) { va_list ap; va_start(ap, n); long double s = 0; for (int i = 0; i < n; i++) s += va_arg(ap, double); va_end(ap); return s; }
void vec_add(float *restrict a, const float *restrict b, int n) { for (int i = 0; i < n; i++) a[i] += b[i] * 2.5f; }
static void jumper(int x) { if (x > 2) longjmp(jb, x); }
static int cmp(const void *a, const void *b) { return *(const int*)a - *(const int*)b; }
int main(int argc, char **argv) {
    int acc = 0, v[16];
    for (int i = 0; i < 40; i++) acc += dispatch(i % 11, i + 7, i % 5 + 1);
    for (int i = 0; i < 16; i++) v[i] = (i * 7919) % 101;
    qsort(v, 16, sizeof v[0], cmp);
    float a[37], b[37]; for (int i = 0; i < 37; i++) { a[i] = i; b[i] = 37 - i; }
    vec_add(a, b, 37);
    double fs = 0; for (int i = 0; i < 37; i++) fs += a[i];
    int r = setjmp(jb); if (r == 0) jumper(argc + 4);
    tls_counter += r;
    printf("%d %.1f %d %d %d %Lf\n", acc, fs, r, tls_counter, v[3], ldsum(3, 1.5, 2.25, 3.0));
    return 0;
}
'''
ATT_C_OPTIONS = [["-O0"], ["-O2"], ["-O3"], ["-Os"], ["-O2", "-fPIC"], ["-O3", "-march=x86-64-v3"],
                 # batch 64: GCC's -g - .file / .loc, the line table, views
                 ["-O0", "-g"], ["-O2", "-g"], ["-O3", "-g"], ["-Os", "-g"], ["-O2", "-g", "-fPIC"],
                 ["-O2", "-gdwarf-4"], ["-O3", "-g", "-march=x86-64-v3"]]
ATT_ERRORS = [
    ("movl %eax %ebx", "AT&T syntax"),
    ("movl $5, %eax)", "AT&T syntax"),
]

# batch 61: NASM's cpu levels (the mnemonic's lowest form's)
BIN_PROBES.update({
    "cpu_levels_ok": "bits 32\ncpu 586\ncpuid\ncpu p6\ncmovz eax, ebx\ncpu katmai\nmovaps xmm0, xmm1\n"
                     "cpu x86-64\nsyscall\ncpu ia64\nhaddps xmm0, xmm1\ncpu default\nvaddps ymm0, ymm1, ymm2\n",
})
REJECT_CASES += [
    ("cpu 386 cpuid", "bin", "bits 32\ncpu 386\ncpuid\n"),
    ("cpu 8086 bswap", "bin", "bits 32\ncpu 8086\nbswap eax\n"),
    ("cpu 486 cmovz", "bin", "bits 32\ncpu 486\ncmovz eax, ebx\n"),
    ("cpu p6 movaps", "bin", "bits 32\ncpu p6\nmovaps xmm0, xmm1\n"),
    ("cpu ia64 popcnt", "bin", "bits 32\ncpu ia64\npopcnt eax, ebx\n"),
    ("cpu unknown", "bin", "cpu sparcv9\nnop\n"),
]

# batch 62: the levels of an instruction's forms (encoder.s amd64_cpu_forms)
BIN_PROBES.update({
    "cpu_forms_ok": "bits 16\ncpu 8086\nmov ax, 1\nshl ax, 1\npush ax\nmov al, [bx]\nfld dword [bx]\n"
                    "push word [eax]\njmp far word [bx]\ncpu 186\npush 5\nimul ax, bx, 3\nshl ax, 4\n"
                    "cpu default\nbits 32\ncpu 286\nmov ax, 1\npush word [eax]\nfld qword [ebx]\ninc word [bx]\n",
})
REJECT_CASES += [
    ("cpu 286 eax", "bin", "bits 32\ncpu 286\nmov eax, 1\n"),
    ("cpu 286 o32 in bits 16", "bin", "bits 16\ncpu 286\nmov eax, 1\n"),
    ("cpu 286 dword memory", "bin", "bits 32\ncpu 286\ninc dword [bx]\n"),
    ("cpu 286 push imm 32", "bin", "bits 32\ncpu 286\npush 5\n"),
    ("cpu 286 far 16:32", "bin", "bits 32\ncpu 286\njmp far [bx]\n"),
    ("cpu 8086 push imm", "bin", "bits 16\ncpu 8086\npush 5\n"),
    ("cpu 8086 shift by 4", "bin", "bits 16\ncpu 8086\nshl ax, 4\n"),
    ("cpu 8086 imul imm", "bin", "bits 16\ncpu 8086\nimul ax, bx, 3\n"),
    ("bits 32 under cpu 286", "bin", "cpu 286\nbits 32\nnop\n"),
    ("use32 under cpu 286", "bin", "cpu 286\nuse32\nnop\n"),
    ("bits 64 under cpu p6", "bin", "cpu p6\nbits 64\nnop\n"),
]

# batch 63: -E writes what NASM's -E writes ("ppt": the text itself, byte
# for byte): %line markers, the source's blanks, [bits ...] for NASM's
# directive macros, [pragma ...]; %require (NASM 3)
CLI_FILES.update({
    "lines.s": "nop\n%define A 1\nnop\n%macro m 0\nnop\n%endmacro\nnop\n\n\nm\nnop\n%if 0\nhlt\n%endif\n"
               "nop\n%rep 2\nint3\n%endrep\nnop\n%assign b 3\n  db  b ,  1\n  ; a comment\n\t\n",
    "paste.s": "\t%define foo xyzzy\n%define bar 1e+10\n%define xyzzy1e 15\n%macro dx 2\n%assign\txx %1%2\n"
               "\tdw xx\n%endmacro\n\tdx foo, bar\n%macro df 2\n\tdd %1e+%2\n%endmacro\n\tdf 1, 36\n"
               "%define N 1e%++%+ 5\n\tdd N, 1e+5\n",
    "strs.s": "%define what(&x,i,n)\t%str(i+1),\"/\",%str(n),\"=\", x, `\\n`\n"
              "\tdb %map(what:(%mapi,%mapn),foo,bar)\n\tdb \"a'b\", 'x\"y', `t\\t`\n",
    "dirs.s": "\tbits 64\nsection .text\nglobal a, b\nextern c,d\nuse32\nuserel\ncpu 686\n",
    "nolist.s": "%macro m 1.nolist\n db %1\n db %1+1\n%endmacro\nm 3\nm 4\n%macro n 1\n%rep 2\n db %1\n"
                "%endrep\n%endmacro\nn 5\n%define D db\nD 6\n",
    "prag.s": "nop\n%pragma output gprefix _\n%pragma preproc sane_empty_expansion\n%pragma asm foo bar\n"
              "%pragma\nnop\n",
    "noeol.s": "db 1\n  ",
    "noeol2.s": "db 1",
    "pi.inc": "db 7\n",
    "req.s": "%require \"pi.inc\"\n%require \"pi.inc\"\n%include \"pi.inc\"\ndb 1\n",
    # another name for a file read: not again (NASM's -E reads it again, its
    # assembly does not)
    "reqdot.s": "%require \"pi.inc\"\n%require \"./pi.inc\"\ndb 1\n",
    "reqself.s": "%require 'reqself.s'\ndb 1\n",
})
CLI_CASES += [
    ("-E markers", ["lines.s"], "ppt"),
    ("-E pasting", ["paste.s"], "ppt"),
    ("-E strings", ["strs.s"], "ppt"),
    ("-E directive macros", ["dirs.s"], "ppt"),
    ("-E .nolist lines", ["nolist.s"], "ppt"),
    ("-E %pragma", ["prag.s"], "ppt"),
    ("-E no newline at the end", ["noeol.s"], "ppt"),
    ("-E no newline at the end 2", ["noeol2.s"], "ppt"),
    ("-E %require", ["req.s"], "ppt"),
    ("%require", ["-f", "bin", "req.s"], "bin"),
    ("%require under another name", ["-f", "bin", "reqdot.s"], "bin"),
    ("%require of the source", ["-f", "bin", "reqself.s"], "bin"),
    ("-E %require of the source", ["reqself.s"], "ppt"),
    ("-E again: %require", ["-f", "bin", "req.s"], "pp"),
    ("-E again: directive macros", ["-f", "bin", "nolist.s"], "pp"),
]
ELF_PROBES.update({
    "bracket_pragma": "[pragma output gprefix _]\n[pragma elf lprefix L.]\nglobal f\nf: ret\nloc: nop\n",
})

# batch 64: GNU's .file N / .loc - the line table GNU as makes of them
# (debug/line.s), byte for byte: DWARF 5 (.file 0) and 3, every .loc
# option, views (.LVUn, 0, -0), several code sections, a .loc in data
# used by the next instruction, long steps; a .debug_info of the source's
# (GNU as makes its own without one: not done)
ATT_FILES += [
    ("loc dwarf 5", r"""	.text
	.file 0 "/build" "src/m.c" md5 0x0123456789abcdef0123456789abcdef
	.file 1 "src/m.c" md5 0x0123456789abcdef0123456789abcdef
	.file 2 "/usr/include/x.h"
	.globl	f
	.type	f, @function
f:
	.loc 1 3 1 view -0
	.loc 1 4 5 prologue_end view .LVU1
	pushq	%rbp
	.loc 2 10 2 is_stmt 0 discriminator 3 view .LVU2
	movl	%edi, %eax
	.loc 2 11 1 isa 1 basic_block
	addl	$1, %eax
	testl	%eax, %eax
	jle	.L2
	.loc 1 300 7 is_stmt 1
	.space	300, 0x90
	.loc 1 20 1 epilogue_begin view .LVU3
	popq	%rbp
	.loc 1 2000 1
.L2:
	ret
	.p2align 4
	.loc 1 21 1 view -0
	nop
	.section	.text.cold,"ax",@progbits
	.loc 1 7 1 view .LVU4
	ud2
	.section	.rodata
	.loc 1 8 1
	.text
	nop
	.section	.debug_info,"",@progbits
	.long	.Ldebug_line0
	.byte	.LVU1, .LVU2, .LVU3
	.uleb128 .LVU4
	.section	.debug_line,"",@progbits
.Ldebug_line0:
"""),
    ("loc dwarf 3", r"""	.text
	.file 1 "a.c"
	.file 2 "inc/b.h"
	.file 3 "/abs/dir/c.h"
f:
	.loc 1 1 0
	nop
	.loc 2 5 3
	.loc 3 6 3
	nop
	jmp	f
	.loc 1 9
	ret
	.section	.debug_info,"",@progbits
	.long	0
"""),
    ("loc no rows", r"""	.text
	.file 0 "/b" "e.c"
	.file 1 "e.c"
	.data
	.long	1
	.section	.debug_info,"",@progbits
	.long	.Ldebug_line0
	.section	.debug_line,"",@progbits
.Ldebug_line0:
"""),
]
ATT_ERRORS += [
    (".loc 3 1", "unassigned file number 3"),
    ('.file 1 "a.c"\n.loc 1 1 bogus', "unknown .loc sub-directive `bogus'"),
    ('.file 1 "a.c"\n.loc 1 1 is_stmt 2', "is_stmt value not 0 or 1"),
    ('.file 1 "a.c"\n.file 1 "b.c"', "file table slot 1 is already occupied"),
    ('.file 1 "a.c"\n.loc 1 1 view 5', "numeric view can only be asserted to zero"),
    ('.file 1 "a.c"\n.loc 1 1 view .LVU1\n.loc 1 2 view 0\nnop', "view number mismatch"),
    ('.file 1 "a.c"\n.loc 1 1\nnop\n.section .debug_line\n.byte 1', "duplicate .debug_line sections"),
]

# batch 64: a view only padding decides (worked out in the second pass,
# core/known.s), a row and a label just before padding that grows (they
# stay before it), a jump shortened under them
ATT_FILES += [
    ("loc view after padding", r"""	.text
	.file 0 "/b" "v.c"
	.file 1 "v.c"
f:
	.loc 1 2 1 view -0
	testl	%edi, %edi
	jle	.L9
	.loc 1 3 1 view .LVU1
	addl	$1, %eax
	addl	$1, %eax
	addl	$1, %eax
	addl	$1, %eax
	addl	$1, %eax
.L9:
	.loc 1 4 1 view .LVU2
	ret
.LVL8:
	.loc 1 4 1 view .LVU3
	.p2align 4
	.p2align 4,,10
	.p2align 3
.L7:
	.loc 1 5 9 is_stmt 1 view .LVU4
	.loc 1 5 14 is_stmt 0 view .LVU5
	movq	16(%rax), %rax
	jmp	.L9
	.section	.debug_info,"",@progbits
	.long	.Ldebug_line0
	.byte	.LVU3, .LVU4, .LVU5
	.uleb128 .LVU4
	.uleb128 .LVU5
	.uleb128 .LVL8-f
	.quad	.LVL8-f
	.section	.debug_line,"",@progbits
.Ldebug_line0:
"""),
]

# batch 66: NASM 3's operand shapes, prefix order and jump sizes
BIN_PROBES.update({
    "shape_movx_nasm3": "bits 64\nmovzx bx, r9w\nmovzx bx, r9d\nmovzx bx, dword [rbx]\nmovzx rbx, r9d\n"
                        "movzx rbx, dword [rbx]\nmovzx ax, dx\nmovsx bx, r9w\nmovsx bx, r9d\nmovsx ebx, r9d\n"
                        "movsx ebx, dword [rbx]\nmovsxd bx, r9d\nmovsxd ebx, [rbx]\nmovsxd dx, eax\n"
                        "movzx eax, bl\nmovsx rax, word [rbx]\n",
    "shape_misc_nasm3": "bits 64\nlar rbx, r9\nlsl rbx, [rbx]\nstr rcx\nsldt rcx\nsmsw rcx\n"
                        "crc32 ebx, r9\ncrc32 rbx, r9d\ncrc32 rbx, word [rbx]\ncrc32 rbx, [rbx]\ncrc32 rax, cl\n"
                        "xchg al, cl\nxchg rbx, r9\nxchg eax, ecx\nxchg [rbx], r9\n"
                        "andn ebx, r9d\nbzhi ebx, r9d\nmulx rbx, r9\npdep ebx, [rbx]\n"
                        "kmov k1, eax\nkmov eax, k1\nkmov byte k1, eax\npextrw rax, xmm0, 1\n",
    "acc_extend_ox": "bits 64\nmovsx eax, ax\nmovsx rax, eax\nmovsx ax, al\nmovsxd rax, eax\nmovsx rax, ax\n"
                     "movsx ax, ah\nbits 16\nmovsx ax, al\nmovsx eax, ax\n",
    "mov_r64_dword": "bits 64\nmov rax, dword 5\nmov rax, dword -1\nmov rax, strict dword 5\nmov rax, 5\n",
    "prefix_order_nasm3": "bits 64\nlock add [fs:eax], ebx\nrep fs movsb\na32 fs rep movsb\nrep movsw\n"
                          "lock add [eax], bx\no16 a32 rep stosw\nxacquire lock add [rax], ebx\n"
                          "xrelease lock add word [rax], bx\nlock fs add word [eax], 1\no16 bnd jmp ax\n"
                          "bits 16\na32 rep movsd\nbits 32\nlock add [bx], ax\na16 rep movsw\n",
    "jump_near_nasm3": "bits 64\nl0: jmp near l0\njz near l0\njz near f1\njmp near f1\nf1: jmp strict near l0\n"
                       "bits 32\ns: jmp word s\njz word s\njz dword s\njmp word f2\nf2: nop\n",
})
MODE_LINES += ["l: a32 jrcxz l", "l: a32 loop l, rcx"]
# GNU as's prefix order and its own forms
GAS_CASES += [
    ("prefix order", ".text\nlock add [eax], bx\nrep movsw\nrep movsb [rdi], fs:[rsi]\nxacquire lock add [rax], ebx\n"
                     ".att_syntax\nrep addr32 movsb\nlock cmpxchgw %cx, (%rdx)\nlock addw $1, %fs:(%eax)\n"
                     "rex64 call *%rax\n"),
    ("gnu immediates", ".text\nmov rax, 5\nmov rax, 0x80000000\nmov rax, 0xffffffff\nmov rax, -1\n"
                       "pextrw rax, xmm0, 1\npmovmskb rax, xmm0\nlar rbx, r9\nstr rcx\nsmsw rcx\n"
                       "crc32 rbx, r9b\nxchg al, cl\n"),
    ("intel then at&t", ".text\nnop\n.att_syntax\nrep addr32 movsb\naddr32 rep movsb\n"),
]

# batch 67: APX's r16-r31 with REX2 (D5)
BIN_PROBES.update({
    "apx_egpr_rex2": "bits 64\nmov rax, r16\nmov r16, rax\nmov r31, r17\nmov r16d, 5\nmov r16, 0x123456789\n"
                     "mov r16b, 1\nmov r16w, ax\nmov spl, r16b\nadd r16, r17\nadd r16, 3\ntest r20, 1\n"
                     "push r16\npop r31\ninc r16\nbswap r16\nbswap r25d\nxchg r16, rax\nxchg r17, r16\n"
                     "imul r16, [r17], 300\nshld r16, r17, 3\ncmpxchg [r16], r17b\nmovzx r16, r17w\n"
                     "movsx r16, byte [r17]\nsetnz r21b\nnop r16\njmp [r16+r17*8]\ncall r31\n",
    "apx_egpr_memory": "bits 64\nmov eax, [r16]\nmov eax, [rax+r17*4]\nmov r20, [r21+r22*8+0x10]\n"
                       "mov eax, [r20*2]\nmov eax, [r21]\nmov eax, [r13+r21]\nmov eax, [r16+rsp]\n"
                       "mov eax, [r16d]\nlea r16, [r17+r18*2+3]\nmov byte [r28], r19b\nmov [r29-8], r16\n",
    "apx_egpr_0f_map": "bits 64\nmovdqa xmm0, [r16]\nmovaps [r20+0x50], xmm0\ncvtsi2sd xmm0, r16\n"
                       "cvttsd2si r16d, xmm0\nmovd xmm0, r16d\nmov r16, cr0\nmov cr0, r16\nmov ds, r16w\n"
                       "mov r16w, ds\nlgdt [r19+8]\nclflush [r16]\nlock cmpxchg16b [r23+0x10]\nbsf r16, r17\n"
                       "popcnt r16, r17\nlzcnt r17d, r18d\nfld qword [r16]\n",
})
MODE_LINES += ["mov eax, r16d", "push r17"]
GAS_CASES += [
    ("apx registers", ".text\nmov r16, rax\nmov eax, DWORD PTR [r16+r17*4+8]\nxchg r17, r16\nxchg al, r16b\n"
                      ".att_syntax\nmovq %r16, %rax\naddl %r17d, (%r18,%r19,4)\npushq %r20\npopq %r31\n"
                      "movw %ds, %r17w\nmovw %r16w, %ds\nleaq 8(%r21), %r22\nmovdqa (%r16), %xmm0\n"
                      "cmpxchgq %r17, (%r23)\nbswapq %r16\nshlq $3, %r25\nimulq $5, %r17, %r16\n"),
]

# a near indirect jmp of a word in 64-bit code takes its 66
BIN_PROBES.update({
    "indirect_word_64": "bits 64\njmp ax\njmp word [rax]\no16 jmp ax\no16 bnd jmp ax\njmp r16\ncall r9\n",
})
MODE_LINES += ["call ax", "jmp eax", "call eax", "call word [rbx]", "jmp dword [ebx]"]
# batch 68: r16-r31 in EVEX, VEX forms promoted to EVEX (APX)
BIN_PROBES.update({
    "apx_egpr_evex": "bits 64\nvpaddd xmm0, xmm1, [r16]\nvpaddd xmm16, xmm1, [r17+r18*2]\nvpextrq r16, xmm0, 1\n"
                     "vmovd xmm0, r16d\nvcvtsi2sd xmm0, xmm1, r16\nvpbroadcastd xmm0, r16d\n"
                     "vmovdqu64 zmm0, [r16+r17]\nvaesenc xmm0, xmm1, [r16]\n",
    "apx_vex_promoted": "bits 64\nkmovq k1, r16\nkmovd r17d, k2\nkmovw k1, [r16+8]\nkmovb [r20], k3\n"
                        "ldtilecfg [r16]\ntileloadd tmm0, [r16+r17]\ntilestored [r16+r17], tmm1\n"
                        "andn r16, rbx, rcx\nrorx r16, rax, 3\nshlx r16, rax, rbx\nmulx r16, rax, rbx\n"
                        "pdep r16, rax, rbx\nbzhi r16d, r19d, r17d\nblsr r16d, r17d\n",
    "rdrand_rdseed": "bits 64\nrdrand rax\nrdseed ecx\nrdrand r9w\n",
})
MODE_LINES += ["rcl rax", "vmovdqu xmm0, [r16]"]
# batch 69: APX's EVEX forms - NDD, {nf}, {zu}, {evex}, ccmp / ctest, cfcmov,
# push2 / pop2, pushp / popp, jmpabs, the 0F 38 ones with r16-r31
BIN_PROBES.update({
    "apx_ndd_alu": "bits 64\nadd rax, rbx, rcx\nadd r16, rbx, rcx\nadd rax, [rbx], rcx\nadd rax, rcx, [rbx]\n"
                   "add rax, rbx, 5\nadd rax, rbx, 500\nsub eax, ebx, ecx\nxor ax, bx, cx\nand al, bl, cl\n"
                   "or r31, r17, [r18+r19*4+8]\nadc rax, rbx, rcx\nsbb rax, [rbx], 7\n",
    "apx_nf": "bits 64\n{nf} add rax, rbx\n{nf} add rax, 5\n{nf} add [rax], rbx\n{nf} add rax, rbx, rcx\n"
              "{nf} inc rax\n{nf} neg ax\n{nf} shl rax, 1\n{nf} sar rax, 3\n{nf} imul rax, rbx\n"
              "{nf} imul rax, rbx, 500\n{nf} mul rbx\n{nf} idiv rax\n{nf} popcnt rax, rbx\n{nf} lzcnt eax, r9d\n"
              "{nf} tzcnt rax, [rbx]\n{nf} andn rax, rbx, rcx\n{nf} bextr rax, rbx, rcx\n{nf} blsr rax, rbx\n"
              "{nf} not rax\n{evex} add rax, rbx\n{evex} inc rax\n",
    "apx_ndd_more": "bits 64\ninc rax, rbx\nneg rax, rbx\nnot rax, rbx\nshl rax, rbx, 3\nshl rax, rbx, 1\n"
                    "shl rax, rbx, cl\nrcl rax, rbx, 1\nshld rax, rbx, rcx, 3\nshrd rax, rbx, rcx, cl\n"
                    "imul rax, rbx, rcx\ncmovz rax, rbx, rcx\nadcx rax, rbx, rcx\nadox r16, r17, [r18]\n"
                    "{zu} imul ax, bx, 5\n{zu} setz al\n{evex} setz bl\n",
    "apx_ccmp_cfcmov": "bits 64\nccmpz {dfv=of,zf} rax, rbx\nccmpnz {dfv=cf} rbx, 5\nccmpt {dfv=sf} qword [r16+8], r16\n"
                       "ccmpf {dfv=} eax, [rbx]\nctestz {dfv=cf} rax, rbx\nctestnz {dfv=of,sf,zf,cf} ebx, 7\n"
                       "cfcmovz rax, rbx\ncfcmovz rax, rbx, rcx\ncfcmovz [rax], rbx\ncfcmovz rax, [rbx]\n",
    "apx_new": "bits 64\npush2 rax, rbx\npop2 rax, rbx\npush2p rbx, r16\npop2p rbx, r16\npushp rax\npopp r16\n"
               "jmpabs 0x123456789\nmovbe rax, [r16]\nmovbe [r17], r16\n{evex} movbe rax, [rbx]\n"
               "crc32 rbx, r16\ncrc32 eax, byte [r16]\n{evex} crc32 eax, ecx\ninvpcid r16, [r17]\n"
               "movdir64b rax, [r16]\nmovdiri [r16], rax\nenqcmd rbx, [r17]\nwrssq [r16], rax\n",
})
MODE_LINES += ["cmovz rbx, r9, 3", "adcx rbx, r9, 3", "{nf} cmp rax, rbx", "{zu} add rax, rbx"]
GAS_CASES += [
    ("apx evex", ".att_syntax\n{nf} addq %rbx, %rax\naddq %rcx, %rbx, %rax\naddq $5, %rbx, %rax\n"
                 "addq (%rbx), %rcx, %rax\n{nf} incq %rax\nincq %rbx, %rax\nshlq $3, %rbx, %rax\n"
                 "shldq $3, %rcx, %rbx, %rax\nimulq %rcx, %rbx, %rax\ncmovzq %rcx, %rbx, %rax\n"
                 "cfcmovzq %rbx, %rax\ncfcmovzq (%rbx), %rax\nadcxq %rcx, %rbx, %rax\n"
                 "movbeq (%r16), %rax\ncrc32q %r16, %rbx\nccmpz {dfv=of,zf} %rbx, %rax\nccmpzq $5, %rax\n"
                 "ctestnz {dfv=cf} $5, %ecx\npush2 %rbx, %rax\npop2 %rbx, %rax\npushp %rax\npopp %rbx\n"
                 "{nf} andn %rcx, %rbx, %rax\n{evex} addq %rbx, %rax\n"),
]
# the disassembler on APX (suites.disasm): the APX probes, but for what it
# leaves to objdump - mov to / from cr and a segment register (none of
# its own), AMX, and xchg r16-r31, rax (objdump: "{rex2 0x18} nop")
DISASM_APX = "bits 64\n" + "".join(
    l + "\n" for k in ("apx_egpr_rex2", "apx_egpr_memory", "apx_egpr_0f_map", "apx_egpr_evex", "apx_vex_promoted",
                       "apx_ndd_alu", "apx_nf", "apx_ndd_more", "apx_ccmp_cfcmov", "apx_new")
    for l in BIN_PROBES[k].splitlines()
    if l and not l.startswith("bits") and "cr0" not in l and "tile" not in l and not l.startswith("xchg r16, rax")
    and "ds," not in l and ", ds" not in l)
# utasm's procedures (middle/semantic/proc.s): name, source, options,
# {line: (warning | error, text)}, lines with nothing, the exit code (0 / non-0)
PROC_CASES = [
    ("balanced", "bits 64\nproc f uses rbx, r12\npush rbx\npush r12\nmov rbx, rdi\nmov r12, rsi\npop r12\n"
                 "pop rbx\nret\nendproc\n", [], {}, [3, 4, 5, 6, 7, 8, 9, 10], 0),
    ("still pushed", "bits 64\nproc f uses rbx\npush rbx\nmov rbx, 1\nret\nendproc\n", [],
     {5: ("error", "stack not balanced at ret: 8 bytes still pushed")}, [3, 4], 1),
    ("popped more", "bits 64\nproc f\npop rax\nret\nendproc\n", [],
     {4: ("error", "8 bytes more popped than pushed")}, [3], 1),
    ("not restored", "bits 64\nproc f uses rbx\npush rbx\npop rcx\nret\nendproc\n", [],
     {5: ("error", "rbx is not restored at this ret")}, [3], 1),
    ("written before saved", "bits 64\nproc f uses r12\nmov r12, 1\npush r12\npop r12\nret\nendproc\n", [],
     {3: ("error", "r12 is written before it is saved")}, [4, 5, 6], 1),
    ("never saved", "bits 64\nproc f uses rbx, r14\npush rbx\npop rbx\nret\nendproc\n", [],
     {6: ("error", "r14 is in uses but never saved")}, [3, 4, 5], 1),
    ("clobber", "bits 64\nproc f\nmov r13, 5\nmov rbx, 1\nxor eax, eax\nret\nendproc\n", [],
     {3: ("warning", "r13 is written but not in uses"), 4: ("warning", "rbx is written but not in uses")},
     [5, 6], 0),
    ("saved without uses", "bits 64\nproc f\npush rbx\nmov rbx, 1\npop rbx\nret\nendproc\n", [], {}, [3, 4, 5, 6], 0),
    ("cpuid writes rbx", "bits 64\nproc f\ncpuid\nret\nendproc\n", [], {3: ("warning", "rbx is written")}, [], 0),
    ("unreachable", "bits 64\nproc f\nret\nnop\nnop\n.next:\nret\nendproc\n", [],
     {4: ("warning", "unreachable code")}, [5, 7], 0),
    ("fallthrough", "bits 64\nproc f\nnop\nendproc\n", [], {4: ("warning", "control reaches endproc")}, [3], 0),
    ("frame", "bits 64\nproc f uses rbp, rbx\npush rbp\nmov rbp, rsp\npush rbx\nsub rsp, 40\nand rsp, -16\n"
              "lea rsp, [rbp - 8]\npop rbx\npop rbp\nret\nendproc\n", [], {}, list(range(3, 13)), 0),
    ("enter / leave", "bits 64\nproc f uses rbp\nenter 32, 0\nleave\nret\nendproc\n", [], {}, [3, 4, 5], 0),
    ("paths meet", "bits 64\nproc f\npush rbx\ntest rdi, rdi\njz .out\npush rcx\n.out:\npop rbx\nret\nendproc\n", [],
     {7: ("error", "stack depth differs where paths meet: 16 bytes here, 8 by a jump to it")}, [9], 1),
    ("backward jump", "bits 64\nproc f uses rbx\npush rbx\n.again:\npush rax\ndec rdi\njnz .again\npop rbx\nret\n"
                      "endproc\n", [], {7: ("error", "stack depth differs where paths meet")}, [9], 1),
    ("branches", "bits 64\nproc f\npush rax\ntest rdi, rdi\njz .zero\npop rax\nret\n.zero:\npop rax\nret\nendproc\n",
     [], {}, list(range(3, 12)), 0),
    ("macro push", "bits 64\n%macro SAVE 1\npush %1\n%endmacro\nproc f uses rbx\nSAVE rbx\npop rbx\nret\nendproc\n",
     [], {}, [6, 7, 8, 9], 0),
    ("switched off", "bits 64\nproc f\nmov r13, 5\nret\nnop\nendproc\n", ["-w-proc-clobber", "-w-proc-unreachable"],
     {}, [3, 5], 0),
    ("clobber as an error", "bits 64\nproc f\nmov r13, 5\nret\nendproc\n", ["-w+error=proc-clobber"],
     {3: ("error", "r13 is written")}, [], 1),
    ("stack check off", "bits 64\nproc f\npush rax\nret\nendproc\n", ["-w-proc-stack"], {}, [4], 0),
    ("a label named proc", "bits 64\nproc:\nret\njmp proc\n", [], {}, [2, 3, 4], 0),
    ("nested", "bits 64\nproc f\nproc g\nret\nendproc\n", [], {3: ("error", "proc inside a proc")}, [], 1),
    ("endproc alone", "bits 64\nendproc\n", [], {2: ("error", "endproc with no proc")}, [], 1),
    ("never closed", "bits 64\nproc f\nret\n", [], {0: ("error", "proc has no endproc")}, [], 1),
]
# utasm's typed struc access, "[reg:TYPE].field" (frontend/parser/parser.s
# parser_typed_field): name, the lines after PACKET's definition, the bytes
# (-f bin), or None and the error the line must give
TYPED_STRUC = ("bits 64\nstruc PACKET\n.len: resd 1\n.flags: resw 1\n.kind: resb 1\n.ptr: resq 1\n"
               ".arr: resb 6\nendstruc\n")
TYPED_STRUC_CASES = [
    ("field offset", "mov eax, [rbx:PACKET].len\nmov ax, [rbx:PACKET].flags\n", "8b03668b4304", None),
    ("the field sizes the operand", "mov [rbx:PACKET].len, 5\ninc word [rdi:PACKET].flags\n",
     "c7030500000066ff4704", None),
    ("an array field: its element", "mov al, [rbx:PACKET].arr\n", "8a430f", None),
    ("a full address", "mov rdx, [rbx + rcx*8:PACKET].ptr\nmov ax, [rbx + 8 : PACKET].flags\n",
     "488b54cb07668b430c", None),
    ("an APX register", "mov cl, [r16:PACKET].kind\n", "d5108a4806", None),
    ("a segment", "mov eax, [fs:rbx:PACKET].len\n", "648b03", None),
    ("lea", "lea rsi, [rbx:PACKET].ptr\n", "488d7307", None),
    ("no field: the start", "mov eax, [rbx:PACKET]\n", "8b03", None),
    ("the plain form still", "mov eax, [rbx + PACKET.len]\n", "8b03", None),
    ("register too wide", "mov eax, [rbx:PACKET].flags\n", None, "a 16-bit memory operand"),
    ("size written not the field's", "mov eax, dword [rbx:PACKET].flags\n", None,
     "the size written is not that of the field `PACKET.flags'"),
    ("no such field", "mov eax, [rbx:PACKET].nope\n", None, "no structure field `PACKET.nope'"),
    ("not a struc", "mov eax, [rbx:NOPE].len\n", None, "`NOPE' is not a structure"),
    ("a number for the type", "mov eax, [rbx:5].len\n", None, "unexpected token"),
    ("no term before it", "mov eax, [rbx + :PACKET].len\n", None, "expression syntax error"),
]
# utasm's namespaces and modules (middle/semantic/namespace.s): name, the
# files ({name: text}, t.s assembled), the bytes (-f bin), or None and the
# error it must give
NS_NET = ("module net\nexport send, MTU\nMTU equ 1500\nsend:\n    call helper\n    call later\n    ret\n"
          "helper: ret\n")
NS_CASES = [
    ("names inside, outside", {"t.s": "bits 64\nlog: ret\nnamespace net\nsend: call ::log\ncall helper\n"
                                      "helper: ret\nendnamespace\ncall net::send\n"},
     "c3e8faffffffe800000000c3e8f0ffffff", None),
    ("innermost first, then out", {"t.s": "bits 64\nnamespace a\nf: ret\nnamespace b\ng: call f\nendnamespace\n"
                                          "endnamespace\ncall a::b::g\n"}, "c3e8faffffffe8f6ffffff", None),
    ("used before defined", {"t.s": "bits 64\nnamespace a\nv: dq w\nw: dd 7\nendnamespace\ndq a::v\n"},
     "080000000000000007000000" + "00" * 8, None),
    ("falls back outside", {"t.s": "bits 64\nnamespace a\ncall x\nendnamespace\nx: ret\n"}, "e800000000c3", None),
    ("equ", {"t.s": "bits 64\nX equ 1\nnamespace a\nX equ 2\nmov eax, X\nendnamespace\nmov ecx, X\n"
                    "mov edx, a::X\n"}, "b802000000b901000000ba02000000", None),
    ("locals", {"t.s": "bits 64\nnamespace a\nf:\n.l: jmp .l\nendnamespace\njmp a::f.l\n"}, "ebfeebfc", None),
    ("proc", {"t.s": "bits 64\nnamespace a\nproc f\nret\nendproc\nendnamespace\ncall a::f\n"}, "c3e8faffffff", None),
    ("struc", {"t.s": "bits 64\nnamespace n\nstruc P\n.a: resd 1\n.b: resw 1\nendstruc\nmov ax, [rbx:P].b\n"
                      "mov ecx, P_size\nendnamespace\nmov ax, [rdi:n::P].b\nmov ecx, n::P_size\n"},
     "668b4304b906000000668b4704b906000000", None),
    ("modules", {"net.s": NS_NET, "fs.s": "module fs\nexport read\nread: call net::send\nret\n",
                 "t.s": "bits 64\n%include \"net.s\"\n%include \"fs.s\"\ncall fs::read\nmov eax, net::MTU\n"
                        "later: ret\n"},
     "e806000000e812000000c3c3e8efffffffc3e8f5ffffffb8dc050000c3", None),
    ("a module in the main file", {"t.s": "bits 64\nmodule m\nexport f\nf: call g\ng: ret\n"}, "e800000000c3", None),
    ("private in a namespace, inside", {"t.s": "bits 64\nnamespace a\nprivate p\np: ret\nnamespace b\ncall p\n"
                                               "endnamespace\nendnamespace\n"}, "c3e8faffffff", None),
    ("a label named namespace", {"t.s": "bits 64\nnamespace:\nret\njmp namespace\n"}, "c3ebfd", None),
    ("private from outside", {"t.s": "bits 64\nnamespace a\nprivate p\np: ret\nendnamespace\ncall a::p\n"},
     None, "t.s:6: error: `a::p' is private"),
    ("not exported", {"net.s": NS_NET, "t.s": "bits 64\n%include \"net.s\"\ncall net::helper\nlater: ret\n"},
     None, "t.s:3: error: `net::helper' is private"),
    ("taken from outside, then defined", {"t.s": "bits 64\nlog: ret\nnamespace a\ncall log\nlog: ret\n"
                                                 "endnamespace\n"},
     None, "t.s:4: error: `log' was taken from an outer namespace, then this one defined it"),
    ("undefined", {"t.s": "bits 64\nnamespace a\ncall nope\nendnamespace\n"}, None, "symbol `nope' not defined"),
    ("endnamespace alone", {"t.s": "bits 64\nendnamespace\n"}, None, "endnamespace with no namespace"),
    ("endnamespace in a module", {"t.s": "bits 64\nmodule m\nendnamespace\n"}, None,
     "endnamespace in a module"),
    ("never closed", {"t.s": "bits 64\nnamespace a\nnop\n"}, None, "namespace has no endnamespace"),
    ("export outside", {"t.s": "bits 64\nexport foo\nfoo: ret\n"}, None,
     "export / private outside a namespace or module"),
]
# utasm's instructions newer than NASM 3.01 and the GNU as the other suites
# check against (2.43): the line, GNU as 2.47's bytes, objdump 2.47's text
# (scratchpad isa_ref.py made them) - utasm must write those bytes, and its
# --disasm read them back as that text
ISA_CASES = []
ISA_CASES += [  # MSR_IMM, USER_MSR (GNU as / objdump 2.47)
    ('rdmsr rax, 0x12345678', 'c4e77bf6c078563412', 'rdmsr rax,0x12345678'),
    ('rdmsr r9, 0x1234', 'c4c77bf6c134120000', 'rdmsr r9,0x1234'),
    ('rdmsr r20, 0x1234', '62ff7f08f6c434120000', 'rdmsr r20,0x1234'),
    ('wrmsrns 0x12345678, rax', 'c4e77af6c078563412', 'wrmsrns 0x12345678,rax'),
    ('wrmsrns 0x1234, r9', 'c4c77af6c134120000', 'wrmsrns 0x1234,r9'),
    ('wrmsrns 0x1234, r20', '62ff7e08f6c434120000', 'wrmsrns 0x1234,r20'),
    ('urdmsr rax, rbx', 'f20f38f8d8', 'urdmsr rax,rbx'),
    ('urdmsr r9, r10', 'f2450f38f8d1', 'urdmsr r9,r10'),
    ('urdmsr r20, r21', '62ec7f08f8ec', 'urdmsr r20,r21'),
    ('urdmsr rax, 0x1234', 'c4e77bf8c034120000', 'urdmsr rax,0x1234'),
    ('urdmsr r20, 0x1234', '62ff7f08f8c434120000', 'urdmsr r20,0x1234'),
    ('uwrmsr rax, rbx', 'f30f38f8c3', 'uwrmsr rax,rbx'),
    ('uwrmsr r20, r21', '62ec7e08f8e5', 'uwrmsr r20,r21'),
    ('uwrmsr 0x1234, rax', 'c4e77af8c034120000', 'uwrmsr 0x1234,rax'),
    ('uwrmsr 0x1234, r20', '62ff7e08f8c434120000', 'uwrmsr 0x1234,r20'),
    ('uwrmsr r9, r10', 'f3450f38f8ca', 'uwrmsr r9,r10'),
    ('urdmsr r31, 0xffffffff', '62df7f08f8c7ffffffff', 'urdmsr r31,0xffffffff'),
    ('rdmsr r15, 0', 'c4c77bf6c700000000', 'rdmsr r15,0x0'),
]
# the forms of those no assembler takes: the line, the error
ISA_ERRORS = [
    ("rdmsr eax, 1", "invalid combination of opcode and operands"),
    ("rdmsr rax, rbx", "invalid combination of opcode and operands"),
    ("wrmsrns rax, 5", "invalid combination of opcode and operands"),
    ("urdmsr rax, [rbx]", "invalid combination of opcode and operands"),
    ("rdmsr rax, 0x100000000", "invalid combination of opcode and operands"),
    ("uwrmsr eax, ebx", "invalid combination of opcode and operands"),
    ("urdmsr rax, -1", "invalid combination of opcode and operands"),
]
# instructions that take no operands, given some: NASM's error (utasm wrote
# the opcode and dropped them - backend/encoder/tables/noops.s)
REJECT_CASES += [
    ("cpuid with an operand", "bin", "bits 64\ncpuid eax\n"),
    ("hlt with an operand", "bin", "bits 64\nhlt 5\n"),
    ("rdtsc with an operand", "bin", "bits 64\nrdtsc rax\n"),
    ("syscall with an operand", "bin", "bits 64\nsyscall rax\n"),
    ("wrmsr with an operand", "bin", "bits 64\nwrmsr rcx\n"),
    ("int3 with an operand", "bin", "bits 64\nint3 1\n"),
    ("cld with an operand", "bin", "bits 64\ncld al\n"),
    ("xtest with an operand", "bin", "bits 64\nxtest eax\n"),
    ("vzeroupper with an operand", "bin", "bits 64\nvzeroupper ymm0\n"),
    ("swapgs with an operand", "bin", "bits 64\nswapgs rax\n"),
]
# (no text where utasm's --disasm reads them otherwise than objdump 2.47:
# its {evex} and memory-operand nuances, prefetchrst2, pbndkb ...)
ISA_CASES += [  # AVX10.2, AVX-VNNI-INT16, AMX-FP8 / AVX512 / MOVRS / COMPLEX / FP16, MOVRS (GNU as / objdump 2.47)
    ('vbcstnebf162ps xmm8, word [rax-8]', 'c4627ab140f8', 'vbcstnebf162ps xmm8,WORD PTR [rax-0x8]'),
    ('{vex} vpdpwsud xmm10, xmm6, oword [rsi+r12*2+128]', 'c4224ad2946680000000', 'vpdpwsud xmm10,xmm6,XMMWORD PTR [rsi+r12*2+0x80]'),
    ('{vex} vpdpwsuds xmm12, xmm0, xmm5', 'c4627ad3e5', 'vpdpwsuds xmm12,xmm0,xmm5'),
    ('{vex} vpdpwusd xmm4, xmm9, oword [rcx+r10*8]', 'c4a231d224d1', 'vpdpwusd xmm4,xmm9,XMMWORD PTR [rcx+r10*8]'),
    ('{vex} vpdpwusds xmm12, xmm5, oword [r10+r8*4-128]', 'c40251d3648280', 'vpdpwusds xmm12,xmm5,XMMWORD PTR [r10+r8*4-0x80]'),
    ('{vex} vpdpwuud xmm5, xmm6, oword [4096]', 'c4e248d22c2500100000', 'vpdpwuud xmm5,xmm6,XMMWORD PTR ds:0x1000'),
    ('{vex} vpdpwuuds xmm7, xmm11, xmm12', 'c4c220d3fc', 'vpdpwuuds xmm7,xmm11,xmm12'),
    ('pbndkb', '0f01c7', None),
    ('prefetchrst2 byte [r12-8]', '410f186424f8', None),
    ('tdpfp16ps tmm4, tmm7, tmm5', 'c4e2535ce7', 'tdpfp16ps tmm4,tmm7,tmm5'),
    ('tcmmimfp16ps tmm2, tmm7, tmm0', 'c4e2796cd7', 'tcmmimfp16ps tmm2,tmm7,tmm0'),
    ('tcmmrlfp16ps tmm6, tmm0, tmm7', 'c4e2406cf0', 'tcmmrlfp16ps tmm6,tmm0,tmm7'),
    ('tileloaddrs tmm4, [r9+r10*8]', 'c4827b4a24d1', 'tileloaddrs tmm4,[r9+r10*8]'),
    ('tileloaddrst1 tmm0, [r14]', 'c4c2794a0426', 'tileloaddrst1 tmm0,[r14+riz*1]'),
    ('tcvtrowd2ps zmm4, tmm4, eax', '62f27e484ae4', 'tcvtrowd2ps zmm4,tmm4,eax'),
    ('tcvtrowps2bf16h zmm14, tmm4, edx', '62726f486df4', 'tcvtrowps2bf16h zmm14,tmm4,edx'),
    ('tcvtrowps2bf16l zmm28, tmm2, ebp', '626256486de2', 'tcvtrowps2bf16l zmm28,tmm2,ebp'),
    ('tcvtrowps2phh zmm8, tmm0, r13d', '627214486dc0', 'tcvtrowps2phh zmm8,tmm0,r13d'),
    ('tcvtrowps2phl zmm4, tmm3, r8d', '62f23d486de3', 'tcvtrowps2phl zmm4,tmm3,r8d'),
    ('tdpbf8ps tmm7, tmm3, tmm6', 'c4e548fdfb', 'tdpbf8ps tmm7,tmm3,tmm6'),
    ('tdpbhf8ps tmm0, tmm2, tmm6', 'c4e54bfdc2', 'tdpbhf8ps tmm0,tmm2,tmm6'),
    ('tdphbf8ps tmm6, tmm5, tmm3', 'c4e562fdf5', 'tdphbf8ps tmm6,tmm5,tmm3'),
    ('tdphf8ps tmm5, tmm4, tmm6', 'c4e549fdec', 'tdphf8ps tmm5,tmm4,tmm6'),
    ('tilemovrow zmm6, tmm0, 0', '62f37d4807f000', 'tilemovrow zmm6,tmm0,0x0'),
    ('vaddbf16 xmm6{k6}{z}, xmm23, oword [127]', '62f545865834257f000000', 'vaddbf16 xmm6{k6}{z},xmm23,XMMWORD PTR ds:0x7f'),
    ('vcmpbf16 k6{k6}, xmm3, oword [rax+r12*8-8], 1', '62b3670ec2b4e0f8ffffff01', 'vcmpbflt16 k6{k6},xmm3,XMMWORD PTR [rax+r12*8-0x8]'),
    ('vcomisbf16 xmm2, xmm1', '62f57d082fd1', 'vcomisbf16 xmm2,xmm1'),
    ('vdivbf16 xmm1{k4}{z}, xmm12, xmm0', '62f51d8c5ec8', 'vdivbf16 xmm1{k4}{z},xmm12,xmm0'),
    ('vfmadd132bf16 xmm5, xmm24, oword [rbp]', '62f63c00986d00', 'vfmadd132bf16 xmm5,xmm24,XMMWORD PTR [rbp+0x0]'),
    ('vfmadd213bf16 xmm4, xmm26, xmm27', '62962c00a8e3', 'vfmadd213bf16 xmm4,xmm26,xmm27'),
    ('vfmadd231bf16 xmm29, xmm5, xmm29', '62065408b8ed', 'vfmadd231bf16 xmm29,xmm5,xmm29'),
    ('vfmsub132bf16 xmm2{k4}, xmm26, oword [r13+128]', '62d62c049a5508', 'vfmsub132bf16 xmm2{k4},xmm26,XMMWORD PTR [r13+0x80]'),
    ('vfmsub213bf16 xmm26{k6}, xmm19, xmm15', '62466406aad7', 'vfmsub213bf16 xmm26{k6},xmm19,xmm15'),
    ('vfmsub231bf16 xmm2{k4}{z}, xmm28, oword [rbx]', '62f61c84ba13', 'vfmsub231bf16 xmm2{k4}{z},xmm28,XMMWORD PTR [rbx]'),
    ('vfnmadd132bf16 xmm16{k7}{z}, xmm6, xmm18', '62a64c8f9cc2', 'vfnmadd132bf16 xmm16{k7}{z},xmm6,xmm18'),
    ('vfnmadd213bf16 xmm29, xmm6, xmm14', '62464c08acee', 'vfnmadd213bf16 xmm29,xmm6,xmm14'),
    ('vfnmadd231bf16 xmm25, xmm24, xmm14', '62463c00bcce', 'vfnmadd231bf16 xmm25,xmm24,xmm14'),
    ('vfnmsub132bf16 xmm26, xmm17, xmm12', '624674009ed4', 'vfnmsub132bf16 xmm26,xmm17,xmm12'),
    ('vfnmsub213bf16 xmm19, xmm7, oword [4096]', '62e64408ae1c2500100000', 'vfnmsub213bf16 xmm19,xmm7,XMMWORD PTR ds:0x1000'),
    ('vfnmsub231bf16 xmm2, xmm3, xmm5', '62f66408bed5', 'vfnmsub231bf16 xmm2,xmm3,xmm5'),
    ('vfpclassbf16 k1, xmm21, 5', '62b37f0866cd05', 'vfpclassbf16 k1,xmm21,0x5'),
    ('vgetexpbf16 xmm2, xmm9', '62d67c0842d1', 'vgetexpbf16 xmm2,xmm9'),
    ('vgetmantbf16 xmm1, xmm1, 1', '62f37f0826c901', 'vgetmantbf16 xmm1,xmm1,0x1'),
    ('vmaxbf16 xmm20, xmm14, oword [r14]', '62c50d085f26', 'vmaxbf16 xmm20,xmm14,XMMWORD PTR [r14]'),
    ('vminbf16 xmm6{k7}{z}, xmm14, xmm11', '62d50d8f5df3', 'vminbf16 xmm6{k7}{z},xmm14,xmm11'),
    ('vmulbf16 xmm16{k1}, xmm18, oword [r14+8]', '62c56d01598608000000', 'vmulbf16 xmm16{k1},xmm18,XMMWORD PTR [r14+0x8]'),
    ('vrcpbf16 xmm6, oword [r15]', '62d67c084c37', 'vrcpbf16 xmm6,XMMWORD PTR [r15]'),
    ('vreducebf16 xmm20{k2}, oword [r15+r10*8+74565], 5', '62837f0a56a4d74523010005', 'vreducebf16 xmm20{k2},XMMWORD PTR [r15+r10*8+0x12345],0x5'),
    ('vrndscalebf16 xmm8, xmm17, 1', '62337f0808c101', 'vrndscalebf16 xmm8,xmm17,0x1'),
    ('vrsqrtbf16 xmm30, oword [rdi]', '62667c084e37', 'vrsqrtbf16 xmm30,XMMWORD PTR [rdi]'),
    ('vscalefbf16 xmm3{k6}, xmm18, oword [rbx]', '62f66c062c1b', 'vscalefbf16 xmm3{k6},xmm18,XMMWORD PTR [rbx]'),
    ('vsqrtbf16 xmm8, oword [r8+127]', '62557d0851807f000000', 'vsqrtbf16 xmm8,XMMWORD PTR [r8+0x7f]'),
    ('vsubbf16 xmm15, xmm11, oword [rbp+r8*8-8]', '623525085cbcc5f8ffffff', 'vsubbf16 xmm15,xmm11,XMMWORD PTR [rbp+r8*8-0x8]'),
    ('vcomxsd xmm19, xmm30', '6281ff082fde', 'vcomxsd xmm19,xmm30'),
    ('vcomxsh xmm14, xmm31', '62157e082ff7', 'vcomxsh xmm14,xmm31'),
    ('vcomxss xmm20, dword [rsi]', '62e17e082f26', 'vcomxss xmm20,DWORD PTR [rsi]'),
    ('vucomxsd xmm24, qword [4096]', '6261ff082e042500100000', 'vucomxsd xmm24,QWORD PTR ds:0x1000'),
    ('vucomxsh xmm21, word [rax+rbp*8+8]', '62e57e082e6ce804', 'vucomxsh xmm21,WORD PTR [rax+rbp*8+0x8]'),
    ('vucomxss xmm21, xmm27', '62817e082eeb', 'vucomxss xmm21,xmm27'),
    ('vcvt2ph2bf8 xmm1{k1}{z}, xmm2, xmm27', '62926f8974cb', 'vcvt2ph2bf8 xmm1{k1}{z},xmm2,xmm27'),
    ('vcvt2ph2bf8s xmm3, xmm17, xmm3', '62f5770074db', 'vcvt2ph2bf8s xmm3,xmm17,xmm3'),
    ('vcvt2ph2hf8 xmm15, xmm21, oword [rdx]', '62755700183a', 'vcvt2ph2hf8 xmm15,xmm21,XMMWORD PTR [rdx]'),
    ('vcvt2ph2hf8s xmm31, xmm23, xmm8', '624547001bf8', 'vcvt2ph2hf8s xmm31,xmm23,xmm8'),
    ('vcvtph2bf8 xmm29{k5}{z}, xmm1', '62627e8d74e9', 'vcvtph2bf8 xmm29{k5}{z},xmm1'),
    ('vcvtph2bf8s xmm8, xmm23', '62357e0874c7', 'vcvtph2bf8s xmm8,xmm23'),
    ('vcvtph2hf8 xmm8, ymm2', '62757e2818c2', 'vcvtph2hf8 xmm8,ymm2'),
    ('vcvtph2hf8s ymm30{k3}, zmm1', '62657e4b1bf1', 'vcvtph2hf8s ymm30{k3},zmm1'),
    ('vcvt2ps2phx xmm14{k1}{z}, xmm1, oword [r9+r12*1-8]', '6212758967b421f8ffffff', 'vcvt2ps2phx xmm14{k1}{z},xmm1,XMMWORD PTR [r9+r12*1-0x8]'),
    ('vcvtbiasph2bf8 xmm6{k6}, xmm14, xmm7', '62f20c0e74f7', 'vcvtbiasph2bf8 xmm6{k6},xmm14,xmm7'),
    ('vcvtbiasph2bf8s xmm9, xmm12, oword [r9]', '62551c087409', 'vcvtbiasph2bf8s xmm9,xmm12,XMMWORD PTR [r9]'),
    ('vcvtbiasph2hf8 xmm1, xmm8, xmm21', '62b53c0818cd', 'vcvtbiasph2hf8 xmm1,xmm8,xmm21'),
    ('vcvtbiasph2hf8s xmm27{k7}, xmm5, xmm15', '6245540f1bdf', 'vcvtbiasph2hf8s xmm27{k7},xmm5,xmm15'),
    ('vcvthf82ph xmm17{k3}, qword [r14]', '62c57f0b1e0e', 'vcvthf82ph xmm17{k3},QWORD PTR [r14]'),
    ('vdpphps xmm27, xmm16, xmm1', '62627c0052d9', 'vdpphps xmm27,xmm16,xmm1'),
    ('vminmaxbf16 xmm12{k7}, xmm28, xmm6, 1', '62731f0752e601', 'vminmaxbf16 xmm12{k7},xmm28,xmm6,0x1'),
    ('vminmaxpd xmm4{k7}, xmm10, oword [rsi], 128', '62f3ad0f522680', 'vminmaxpd xmm4{k7},xmm10,XMMWORD PTR [rsi],0x80'),
    ('vminmaxph xmm12{k6}, xmm20, xmm28, 5', '62135c0652e405', 'vminmaxph xmm12{k6},xmm20,xmm28,0x5'),
    ('vminmaxps xmm2{k2}{z}, xmm11, xmm6, 128', '62f3258a52d680', 'vminmaxps xmm2{k2}{z},xmm11,xmm6,0x80'),
    ('vminmaxsd xmm26{k6}, xmm19, xmm1, 1', '6263e50653d101', 'vminmaxsd xmm26{k6},xmm19,xmm1,0x1'),
    ('vminmaxsh xmm29{k4}{z}, xmm19, xmm2, 1', '6263648453ea01', 'vminmaxsh xmm29{k4}{z},xmm19,xmm2,0x1'),
    ('vminmaxss xmm29, xmm19, xmm9, 0', '6243650053e900', 'vminmaxss xmm29,xmm19,xmm9,0x0'),
    ('vcvtbf162ibs xmm8, oword [rcx+r12*1+74565]', '62357f0869842145230100', 'vcvtbf162ibs xmm8,XMMWORD PTR [rcx+r12*1+0x12345]'),
    ('vcvtbf162iubs xmm5, oword [rsi+rbx*4+127]', '62f57f086bac9e7f000000', 'vcvtbf162iubs xmm5,XMMWORD PTR [rsi+rbx*4+0x7f]'),
    ('vcvttbf162ibs xmm1, xmm3', '62f57f0868cb', 'vcvttbf162ibs xmm1,xmm3'),
    ('vcvttbf162iubs xmm21{k3}, oword [rax+r14*2+128]', '62a57f0b6a6c7008', 'vcvttbf162iubs xmm21{k3},XMMWORD PTR [rax+r14*2+0x80]'),
    ('vcvttpd2dqs xmm15, xmm18', '6235fc086dfa', 'vcvttpd2dqs xmm15,xmm18'),
    ('vcvttpd2qqs xmm3{k4}{z}, oword [-8]', '62f5fd8c6d1c25f8ffffff', 'vcvttpd2qqs xmm3{k4}{z},XMMWORD PTR ds:0xfffffffffffffff8'),
    ('vcvttpd2udqs xmm31, ymm9', '6245fc286cf9', 'vcvttpd2udqs xmm31,ymm9'),
    ('vcvttpd2uqqs xmm12{k7}, oword [r15+127]', '6255fd0f6ca77f000000', 'vcvttpd2uqqs xmm12{k7},XMMWORD PTR [r15+0x7f]'),
    ('vcvtph2ibs xmm8, xmm15', '62557c0869c7', 'vcvtph2ibs xmm8,xmm15'),
    ('vcvtph2iubs xmm20{k4}{z}, oword [r10+r8*8]', '62857c8c6b24c2', 'vcvtph2iubs xmm20{k4}{z},XMMWORD PTR [r10+r8*8]'),
    ('vcvttph2ibs xmm22{k3}{z}, xmm13', '62c57c8b68f5', 'vcvttph2ibs xmm22{k3}{z},xmm13'),
    ('vcvttph2iubs xmm17{k1}{z}, oword [rsp+8]', '62e57c896a8c2408000000', 'vcvttph2iubs xmm17{k1}{z},XMMWORD PTR [rsp+0x8]'),
    ('vcvttps2dqs xmm3{k5}{z}, oword [127]', '62f57c8d6d1c257f000000', 'vcvttps2dqs xmm3{k5}{z},XMMWORD PTR ds:0x7f'),
    ('vcvtps2ibs xmm7, xmm3', '62f57d0869fb', 'vcvtps2ibs xmm7,xmm3'),
    ('vcvtps2iubs xmm13, xmm23', '62357d086bef', 'vcvtps2iubs xmm13,xmm23'),
    ('vcvttps2ibs xmm23{k4}{z}, oword [r9+rdx*1]', '62c57d8c683c11', 'vcvttps2ibs xmm23{k4}{z},XMMWORD PTR [r9+rdx*1]'),
    ('vcvttps2iubs xmm31{k5}{z}, oword [r13+128]', '62457d8d6a7d08', 'vcvttps2iubs xmm31{k5}{z},XMMWORD PTR [r13+0x80]'),
    ('vcvttps2qqs xmm30{k6}{z}, qword [r15]', '62457d8e6d37', 'vcvttps2qqs xmm30{k6}{z},QWORD PTR [r15]'),
    ('vcvttps2udqs xmm28{k3}, xmm1', '62657c0b6ce1', 'vcvttps2udqs xmm28{k3},xmm1'),
    ('vcvttps2uqqs xmm21, qword [r8]', '62c57d086c28', 'vcvttps2uqqs xmm21,QWORD PTR [r8]'),
    ('movrs r13b, byte [rax+rdx*4-8]', '440f388a6c90f8', None),
    ('vcvttsd2sis edi, qword [r14]', '62d57f086d3e', 'vcvttsd2sis edi,QWORD PTR [r14]'),
    ('vcvttsd2usis r11d, xmm11', '62557f086cdb', 'vcvttsd2usis r11d,xmm11'),
    ('vcvttss2sis eax, dword [rax+rdx*1+127]', '62f57e086d84107f000000', 'vcvttss2sis eax,DWORD PTR [rax+rdx*1+0x7f]'),
    ('vcvttss2usis ecx, xmm26', '62957e086cca', 'vcvttss2usis ecx,xmm26'),
    ('vmovrsb xmm28, oword [rsp]', '62657f086f2424', 'vmovrsb xmm28,XMMWORD PTR [rsp]'),
    ('vmovrsw xmm6, oword [rax+r14*2]', '62b5ff086f3470', 'vmovrsw xmm6,XMMWORD PTR [rax+r14*2]'),
    ('vmovrsd xmm24, oword [r9-128]', '62457e086f41f8', 'vmovrsd xmm24,XMMWORD PTR [r9-0x80]'),
    ('vmovrsq xmm21, oword [128]', '62e5fe086f2c2580000000', 'vmovrsq xmm21,XMMWORD PTR ds:0x80'),
]
ISA_ERRORS += [
    # AMX's dot products: three different tile registers (#UD; GNU's as too,
    # NASM takes them)
    ("tdpbf16ps tmm1, tmm1, tmm2", "the three tile registers must all differ"),
    ("tdpbssd tmm1, tmm2, tmm2", "the three tile registers must all differ"),
    ("tdpfp16ps tmm4, tmm7, tmm4", "the three tile registers must all differ"),
    ("tdpbf8ps tmm3, tmm3, tmm3", "the three tile registers must all differ"),
]
ISA_CASES += [  # AMD privileged / SEV-SNP, TDX, notrack, branch hints, APX setzu / imulzu, udb, xstorerng (GNU as / objdump 2.47)
    ('invlpgb', '0f01fe', None),
    ('tlbsync', '0f01ff', None),
    ('rdpru', '0f01fd', None),
    ('mcommit', 'f30f01fa', None),
    ('psmash', 'f30f01ff', None),
    ('rmpupdate', 'f20f01fe', None),
    ('rmpquery', 'f30f01fd', None),
    ('rmpadjust', 'f30f01fe', None),
    ('pvalidate', 'f20f01ff', None),
    ('tdcall', '660f01cc', None),
    ('seamcall', '660f01cf', None),
    ('seamret', '660f01cd', None),
    ('seamops', '660f01ce', None),
    ('notrack jmp rax', '3effe0', 'notrack jmp rax'),
    ('notrack call qword [rax]', '3eff10', 'notrack call QWORD PTR [rax]'),
    ('setzue al', '62f47f1844c0', 'setzue al'),
    ('setzune r20b', '62fc7f1845c4', 'setzune r20b'),
    ('imulzu ax, bx, 5', '62f47d186bc305', 'imulzu ax,bx,0x5'),
    ('udb', 'd6', None),
    ('xstorerng', '0fa7c0', None),
    ('invlpgb rax, ecx, edx', '0f01fe', None),
    ('invlpgb eax, ecx, edx', '670f01fe', None),
    ('psmash eax', '67f30f01ff', None),
    ('psmash rax', 'f30f01ff', None),
    ('hnt jne $+2', '2e75ff', None),
    ('setzunle r31b', '62dc7f184fc7', 'setzug r31b'),
    ('imulzu r20w, r21w, 0x1234', '62ec7d1869e53412', 'imulzu r20w,r21w,0x1234'),
]
ISA_CASES += [  # NASM 3.01's spellings and forms (its bytes): setCCzu, and
    # setcc with a 32- / 64-bit register - setzucc, not setcc of the low byte
    ("setezu al", "62f47f1844c0", None),
    ("setnlezu r31b", "62dc7f184fc7", None),
    ("sete eax", "62f47f1844c0", None),
    ("sete rax", "62f47f1844c0", None),
    ("setne r20d", "62fc7f1845c4", None),
    ("{zu} sete al", "62f47f1844c0", None),
    ("sete al", "0f94c0", None),
    ("sete byte [rax]", "0f9400", None),
]
ISA_ERRORS += [
    ("sete ax", "invalid combination of opcode and operands"),
    ("sete r9w", "invalid combination of opcode and operands"),
    ("tdcall rax", "invalid combination of opcode and operands"),
    ("invlpgb rax, edx, ecx", "invalid combination of opcode and operands"),
]
REJECT_CASES += [
    ("udb outside 64-bit mode", "bin", "bits 32\nudb\n"),
]
# vaddph / vcmpph: NASM 2.16's memory 16 bits (zword refused, broadcasts
# refused), vcmpph / vcmpsh's predicate pseudo-ops
ISA_CASES += [  # vaddph / vcmpph (GNU as / objdump 2.47)
    ('vaddph zmm1, zmm2, [rax]{1to32}', '62f56c585808', 'vaddph zmm1,zmm2,WORD BCST [rax]'),
    ('vaddph zmm1, zmm2, zword [rax]', '62f56c485808', 'vaddph zmm1,zmm2,ZMMWORD PTR [rax]'),
    ('vaddph xmm1{k1}{z}, xmm2, [rax+64]{1to8}', '62f56c99584820', 'vaddph xmm1{k1}{z},xmm2,WORD BCST [rax+0x40]'),
    ('vaddph zmm1, zmm2, zmm3, {rn-sae}', '62f56c1858cb', 'vaddph zmm1,zmm2,zmm3{rn-sae}'),
    ('vcmpph k1, xmm2, [rax]{1to8}, 5', '62f36c18c20805', 'vcmpnltph k1,xmm2,WORD BCST [rax]'),
    ('vcmpph k1{k2}, zmm2, zword [rax+128], 1', '62f36c4ac2480201', 'vcmpltph k1{k2},zmm2,ZMMWORD PTR [rax+0x80]'),
    ('vcmpeqph k1, xmm2, xmm3', '62f36c08c2cb00', 'vcmpeqph k1,xmm2,xmm3'),
    ('vcmpnlt_uqph k1, zmm2, [rax]{1to32}', '62f36c58c20815', 'vcmpnlt_uqph k1,zmm2,WORD BCST [rax]'),
    ('vcmpltsh k1, xmm2, word [rax]', '62f36e08c20801', 'vcmpltsh k1,xmm2,WORD PTR [rax]'),
    ('vcmpunordsh k1{k3}, xmm2, xmm3', '62f36e0bc2cb03', 'vcmpunordsh k1{k3},xmm2,xmm3'),
]
# found by encfuzz's broadcasts and GNU as 2.47: REX.W off an address-sized register,
# retw imm's 66, rstorssp's REX.B, the AVX10.2 / AVX-VNNI forms; 0F 01 read back
ISA_CASES += [  # encoder fixes found by broadcast fuzzing; the 0F 01 system instructions read back (GNU as / objdump 2.47)
    ('enqcmd rsi, [r11+127]', 'f2410f38f8737f', 'enqcmd rsi,[r11+0x7f]'),
    ('enqcmds r10, [rdi-128]', 'f3440f38f85780', 'enqcmds r10,[rdi-0x80]'),
    ('invpcid r11, [rax]', '66440f388218', 'invpcid r11,[rax]'),
    ('retw 128', '66c28000', 'retw 0x80'),
    ('rstorssp qword [r12+8]', 'f3410f016c2408', 'rstorssp QWORD PTR [r12+0x8]'),
    ('rdsspq r11', 'f3490f1ecb', 'rdsspq r11'),
    ('vpdpbssds ymm13, ymm12, ymm0', 'c4621f51e8', 'vpdpbssds ymm13,ymm12,ymm0'),
    ('vpdpbssd xmm1{k1}, xmm2, xmm3', '62f26f0950cb', 'vpdpbssd xmm1{k1},xmm2,xmm3'),
    ('{vex} vpdpbssd xmm1, xmm2, xmm3', 'c4e26b50cb', 'vpdpbssd xmm1,xmm2,xmm3'),
    ('vcvtneeph2ps xmm15, oword [rsi]', 'c46279b03e', 'vcvtneeph2ps xmm15,XMMWORD PTR [rsi]'),
    ('{vex} vpdpbusd xmm1, xmm2, xmm3', 'c4e26950cb', '{vex} vpdpbusd xmm1,xmm2,xmm3'),
    ('vsm4key4 zmm1, zmm2, [rax+64]', '62f26e48da4801', 'vsm4key4 zmm1,zmm2,ZMMWORD PTR [rax+0x40]'),
    ('vmpsadbw zmm1, zmm2, zmm3, 1', '62f36e4842cb01', 'vmpsadbw zmm1,zmm2,zmm3,0x1'),
    ('vminbf16 ymm0{k3}{z}, ymm5, [rax+128]{1to16}', '62f555bb5d4040', 'vminbf16 ymm0{k3}{z},ymm5,WORD BCST [rax+0x80]'),
    ('vmcall', '0f01c1', 'vmcall'),
    ('erets', 'f20f01ca', 'erets'),
    ('uiret', 'f30f01ec', 'uiret'),
    ('wrmsrlist', 'f30f01c6', 'wrmsrlist'),
    ('serialize', '0f01e8', 'serialize'),
]
ISA_CASES += [  # vbcstnebf16ps: NASM 2.16 / utasm spelling (GNU: vbcstnebf162ps)
    ("vbcstnebf16ps ymm0, word [rax]", "c4e27eb100", "vbcstnebf162ps ymm0,WORD PTR [rax]"),
]
ISA_CASES += [  # xbegin as a branch (a number / $ too), aor (RAO-INT), 3DNow!'s pmulhrw (GNU as / objdump 2.47)
    ("xbegin $+6", "c7f800000000", None),
    ("xbegin $", "c7f8faffffff", None),
    ("aor [rax], eax", "f20f38fc00", "aor DWORD PTR [rax],eax"),
    ("aor [r9+8], r10", "f24d0f38fc5108", "aor QWORD PTR [r9+0x8],r10"),
    ("pmulhrw mm0, [rax]", "0f0f00b7", "pmulhrw mm0,QWORD PTR [rax]"),
    ("vpgatherdd xmm0, [rax+xmm1*4], xmm2", "c4e269900488", "vpgatherdd xmm0,DWORD PTR [rax+xmm1*4],xmm2"),
    ("vpscatterdd [rax+zmm0*4]{k1}, zmm0", "62f27d49a00480", "vpscatterdd DWORD PTR [rax+zmm0*4]{k1},zmm0"),
]
ISA_ERRORS += [
    # a gather's destination, index and mask: all different (#UD; GNU's
    # as warns, NASM takes them)
    ("vpgatherdd xmm0, [rax+xmm0*4], xmm1", "a gather's destination, index and mask registers must all differ"),
    ("vpgatherdd xmm0, [rax+xmm1*4], xmm0", "a gather's destination, index and mask registers must all differ"),
    ("vpgatherqd xmm1, [rax+ymm2*4], xmm2", "a gather's destination, index and mask registers must all differ"),
    ("vgatherdps zmm30{k1}, [rax+zmm30*4]", "a gather's destination, index and mask registers must all differ"),
    ("xbegin rax", "invalid operand"),
    # EVEX gathers / scatters / AVX512PF prefetches: a write mask, not k0
    # (#UD; GNU's as refuses, NASM takes them)
    ("vgatherdpd xmm12, [rsi+xmm25*1-0x80]", "a gather / scatter needs a write mask"),
    ("vpscatterdd [rax+zmm1*4], zmm0", "a gather / scatter needs a write mask"),
    ("vgatherpf0dps [rax+zmm0*4]", "a gather / scatter needs a write mask"),
]
ISA_CASES += [  # utasm --disasm read as objdump 2.47 writes them: unused prefixes, string operands, hint nops, KNM
    ("db 0x66, 0x0f, 0xae, 0xf8", "660faef8", "data16 sfence"),
    ("db 0x49, 0x8c, 0x6b, 0x80", "498c6b80", "rex.WB mov WORD PTR [r11-0x80],gs"),
    ("db 0x4c, 0x90", "4c90", "rex.WR nop"),
    ("db 0x64, 0x40, 0x9c", "64409c", "fs rex pushf"),
    ("db 0x66, 0x4c, 0x0f, 0x3a, 0x17, 0xc4, 0xff", "664c0f3a17c4ff", "rex.WR extractps esp,xmm8,0xff"),
    ("db 0x67, 0x0f, 0x01, 0xdf", "670f01df", "addr32 invlpga"),
    ("db 0x64, 0xa4", "64a4", "movs BYTE PTR [rdi],BYTE PTR fs:[rsi]"),
    ("db 0x67, 0xac", "67ac", "lods al,BYTE PTR [esi]"),
    ("db 0x2e, 0xac", "2eac", "cs lods al,BYTE PTR [rsi]"),
    ("db 0x65, 0xd7", "65d7", "xlat BYTE PTR gs:[rbx]"),
    ("db 0x0f, 0x1a, 0xc4", "0f1ac4", "nop esp"),
    ("db 0xf3, 0x0f, 0x1b, 0xc0", "f30f1bc0", "repz nop eax"),
    ("db 0x66, 0x0f, 0x1c, 0x00", "660f1c00", "nop WORD PTR [rax]"),
    ("db 0xd6", "d6", "udb"),
    ("db 0x9b, 0x41, 0xdd, 0x33", "9b41dd33", "fsave [r11]"),
    ("db 0xdb, 0xe4", "dbe4", "fnsetpm(287 only)"),
    ("db 0x66, 0xf2, 0x45, 0x0f, 0x38, 0xf1, 0xeb", "66f2450f38f1eb", "crc32 r13d,r11w"),
    ("db 0x62, 0xf1, 0x1d, 0x08, 0x72, 0xa3, 0x7f, 0, 0, 0, 5", "62f11d0872a37f00000005", "vpsrad xmm12,XMMWORD PTR [rbx+0x7f],0x5"),
    ("v4fnmaddps zmm20{k4}, zmm21, [rbx-0x80]", "62e25744aa63f8", "v4fnmaddps zmm20{k4},zmm21,XMMWORD PTR [rbx-0x80]"),
    ("movrs bpl, byte [r12]", "410f388a2c24", "movrs bpl,BYTE PTR [r12]"),
]
ISA_CASES += [  # vmovw: Intel's / GNU's r32 (NASM's r16 too)
    ("vmovw xmm1, eax", "62f57d086ec8", "vmovw xmm1,eax"),
    ("vmovw eax, xmm1", "62f57d087ec8", "vmovw eax,xmm1"),
    ("vmovw xmm1, ax", "62f57d086ec8", "vmovw xmm1,eax"),
]
ISA_ERRORS += [
    # a mask / {z} where the instruction takes none (#UD; NASM refuses them
    # too): vmovw, vmovd, vcomiss, vpextrd; {z} on a store or into a mask
    ("vmovw xmm1{k1}, [rax]", "takes no write mask"),
    ("vmovd xmm17{k1}, eax", "takes no write mask"),
    ("vcomiss xmm17{k1}, xmm2", "takes no write mask"),
    ("vpextrd eax{k1}, xmm17, 1", "takes no write mask"),
    ("vcmpps k1{k2}{z}, zmm2, zmm3, 1", "takes no write mask"),
    ("vmovaps [rax]{k1}{z}, zmm1", "takes no write mask"),
]
