;
; ============================================
; File     : lib/list.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

; ============================================================================
; LIST — DOUBLY LINKED LIST
; ============================================================================
; A doubly linked list of 64-bit values (integers or pointers). Nodes come
; from the arena; unlinked nodes are not reclaimed. Useful where a Vec is
; awkward: O(1) removal from the middle, stable node addresses (e.g. an
; include stack, a fixup queue, macro expansion chains).
;
; The List header (LIST_SIZE bytes) is caller-owned.
;
; Calling convention (AMD64):
;   args  : rdi, rsi, rdx
;   return: rax = EXIT_OK or error code, rdx = result
;   callee saved: rbx, r12-r15, rbp
;
; Errors:
;   EXIT_INTERNAL  - header is not a List (bad tag) / bad arguments
;   EXIT_OOM       - arena exhausted
;   EXIT_ERROR     - pop from an empty list

extern arena_alloc

[SECTION .text]

; ---- list_init --------------------------
;
; list_init
; Initializes an empty List header.
; Input    : rdi = pointer to List header (LIST_SIZE bytes)
;             rsi = pointer to Arena
; Output   : rax = EXIT_OK or EXIT_INTERNAL
;              rdx = pointer to List header
; Clobbers : none
;
global list_init
list_init:
    test    rdi, rdi
    jz      .bad_args
    test    rsi, rsi
    jz      .bad_args

    mov     byte  [rdi + LIST_tag], TAG_LIST
    mov     qword [rdi + LIST_head], 0
    mov     qword [rdi + LIST_tail], 0
    mov     qword [rdi + LIST_count], 0
    mov     [rdi + LIST_arena], rsi

    xor     eax, eax
    mov     rdx, rdi
    ret

.bad_args:
    mov     eax, EXIT_INTERNAL
    xor     edx, edx
    ret

; ---- list_new_node (internal) -----------
;
; Allocates a zeroed node holding a value.
; Input    : rbx = List, r12 = value
; Output   : rax = EXIT_OK / error, rdx = node
; Clobbers : rcx, rdi, rsi, r8
;
list_new_node:
    cmp     byte [rbx + LIST_tag], TAG_LIST
    jne     .bad_list
    mov     rdi, [rbx + LIST_arena]
    mov     esi, LISTNODE_SIZE
    call    arena_alloc                    ; node is zeroed: next = prev = 0
    test    rax, rax
    jnz     .done
    mov     [rdx + LISTNODE_value], r12
.done:
    ret
.bad_list:
    mov     eax, EXIT_INTERNAL
    xor     edx, edx
    ret

; ---- list_push_back ---------------------
;
; list_push_back
; Appends a value at the tail.
; Input    : rdi = pointer to List
;             rsi = value
; Output   : rax = EXIT_OK, EXIT_INTERNAL or EXIT_OOM
;              rdx = pointer to the new node
; Clobbers : rcx, rsi, rdi, r8
;
global list_push_back
list_push_back:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi

    call    list_new_node
    test    rax, rax
    jnz     .done

    mov     rcx, [rbx + LIST_tail]
    mov     [rdx + LISTNODE_prev], rcx
    test    rcx, rcx
    jz      .was_empty
    mov     [rcx + LISTNODE_next], rdx     ; old_tail.next = node
    jmp     .link_tail
.was_empty:
    mov     [rbx + LIST_head], rdx
.link_tail:
    mov     [rbx + LIST_tail], rdx
    inc     qword [rbx + LIST_count]
    xor     eax, eax

.done:
    pop     r12
    pop     rbx
    ret

; ---- list_push_front --------------------
;
; list_push_front
; Prepends a value at the head.
; Input    : rdi = pointer to List
;             rsi = value
; Output   : rax = EXIT_OK, EXIT_INTERNAL or EXIT_OOM
;              rdx = pointer to the new node
; Clobbers : rcx, rsi, rdi, r8
;
global list_push_front
list_push_front:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi

    call    list_new_node
    test    rax, rax
    jnz     .done

    mov     rcx, [rbx + LIST_head]
    mov     [rdx + LISTNODE_next], rcx
    test    rcx, rcx
    jz      .was_empty
    mov     [rcx + LISTNODE_prev], rdx     ; old_head.prev = node
    jmp     .link_head
.was_empty:
    mov     [rbx + LIST_tail], rdx
.link_head:
    mov     [rbx + LIST_head], rdx
    inc     qword [rbx + LIST_count]
    xor     eax, eax

.done:
    pop     r12
    pop     rbx
    ret

; ---- list_remove ------------------------
;
; list_remove
; Unlinks a node from the list. The node must belong to this list.
; The node's own next/prev are cleared; its value is left intact.
; Input    : rdi = pointer to List
;             rsi = pointer to node
; Output   : rax = EXIT_OK or EXIT_INTERNAL
;              rdx = node's value
; Clobbers : rcx, r8
;
global list_remove
list_remove:
    cmp     byte [rdi + LIST_tag], TAG_LIST
    jne     .bad_args
    test    rsi, rsi
    jz      .bad_args

    mov     rcx, [rsi + LISTNODE_prev]
    mov     r8,  [rsi + LISTNODE_next]

    ; prev.next = next   (or head = next)
    test    rcx, rcx
    jz      .removing_head
    mov     [rcx + LISTNODE_next], r8
    jmp     .fix_next
.removing_head:
    mov     [rdi + LIST_head], r8

.fix_next:
    ; next.prev = prev   (or tail = prev)
    test    r8, r8
    jz      .removing_tail
    mov     [r8 + LISTNODE_prev], rcx
    jmp     .unlinked
.removing_tail:
    mov     [rdi + LIST_tail], rcx

.unlinked:
    mov     qword [rsi + LISTNODE_next], 0
    mov     qword [rsi + LISTNODE_prev], 0
    dec     qword [rdi + LIST_count]
    xor     eax, eax
    mov     rdx, [rsi + LISTNODE_value]
    ret

.bad_args:
    mov     eax, EXIT_INTERNAL
    xor     edx, edx
    ret

; ---- list_pop_front ---------------------
;
; list_pop_front
; Removes the head node and returns its value.
; Input    : rdi = pointer to List
; Output   : rax = EXIT_OK, EXIT_ERROR (empty) or EXIT_INTERNAL
;              rdx = value
; Clobbers : rcx, rsi, r8
;
global list_pop_front
list_pop_front:
    cmp     byte [rdi + LIST_tag], TAG_LIST
    jne     .bad_list
    mov     rsi, [rdi + LIST_head]
    test    rsi, rsi
    jz      .empty
    jmp     list_remove

.empty:
    mov     eax, EXIT_ERROR
    xor     edx, edx
    ret
.bad_list:
    mov     eax, EXIT_INTERNAL
    xor     edx, edx
    ret

; ---- list_pop_back ----------------------
;
; list_pop_back
; Removes the tail node and returns its value.
; Input    : rdi = pointer to List
; Output   : rax = EXIT_OK, EXIT_ERROR (empty) or EXIT_INTERNAL
;              rdx = value
; Clobbers : rcx, rsi, r8
;
global list_pop_back
list_pop_back:
    cmp     byte [rdi + LIST_tag], TAG_LIST
    jne     .bad_list
    mov     rsi, [rdi + LIST_tail]
    test    rsi, rsi
    jz      .empty
    jmp     list_remove

.empty:
    mov     eax, EXIT_ERROR
    xor     edx, edx
    ret
.bad_list:
    mov     eax, EXIT_INTERNAL
    xor     edx, edx
    ret

; ---- list_find --------------------------
;
; list_find
; Finds the first node (from the head) holding a value.
; Input    : rdi = pointer to List
;             rsi = value to find
; Output   : rax = pointer to node, or 0 if not found
; Clobbers : none
;
global list_find
list_find:
    mov     rax, [rdi + LIST_head]
.loop:
    test    rax, rax
    jz      .done
    cmp     [rax + LISTNODE_value], rsi
    je      .done
    mov     rax, [rax + LISTNODE_next]
    jmp     .loop
.done:
    ret

; ---- list_len ---------------------------
;
; list_len
; Input    : rdi = pointer to List
; Output   : rax = number of nodes
; Clobbers : none
;
global list_len
list_len:
    mov     rax, [rdi + LIST_count]
    ret

; ---- list_foreach -----------------------
;
; list_foreach
; Calls a callback for each value, head to tail. The callback may remove
; the node it is given (the next pointer is read before the call).
; A non-zero return from the callback stops the walk early.
;   callback(rdi = value, rsi = ctx, rdx = node) -> rax
; Input    : rdi = pointer to List
;             rsi = callback function
;             rdx = opaque context passed to the callback
; Output   : rax = 0 if every node was visited, else the callback's
;              non-zero return value
; Clobbers : whatever the callback clobbers (caller-saved registers)
;
global list_foreach
list_foreach:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8                         ; keep rsp 16-byte aligned at call

    mov     rbx, [rdi + LIST_head]         ; rbx = current node
    mov     r12, rsi                       ; r12 = callback
    mov     r13, rdx                       ; r13 = ctx
    xor     eax, eax

.loop:
    test    rbx, rbx
    jz      .done
    mov     r14, [rbx + LISTNODE_next]     ; read next before callback
    mov     rdi, [rbx + LISTNODE_value]
    mov     rsi, r13
    mov     rdx, rbx
    call    r12
    test    rax, rax
    jnz     .done                          ; callback asked to stop
    mov     rbx, r14
    jmp     .loop

.done:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
