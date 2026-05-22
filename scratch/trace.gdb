b preprocessor_next_token
commands 1
  silent
  finish
  if $rax != 0
    printf "preprocessor_next_token returned error: %d\n", $rax
    set $pr = $rbx
    set $lx = *(void**)($pr + 48)
    printf "File: %s, Line: %d, Col: %d\n", *(char**)($lx + 32), *(int*)($lx + 40), *(short*)($lx + 44)
    bt
    quit
  end
  continue
end

b prep_handle_directive
commands 2
  silent
  set $pr = $rdi
  set $lx = *(void**)($pr + 48)
  printf "prep_handle_directive called at %s:%d:%d\n", *(char**)($lx + 32), *(int*)($lx + 40), *(short*)($lx + 44)
  finish
  printf "prep_handle_directive returned %d\n", $rax
  continue
end

b lexer_next
commands 3
  silent
  finish
  if $rax != 0
    printf "lexer_next returned %d\n", $rax
  end
  continue
end

run
