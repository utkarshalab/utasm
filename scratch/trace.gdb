b *0x404ea3
commands 1
  silent
  finish
  if $rax != 0
    printf "prep_internal_next returned error: %d\n", $rax
    set $pr = $rbx
    set $lx = *(void**)($pr + 48)
    printf "File: %s, Line: %d, Col: %d\n", *(char**)($lx + 32), *(int*)($lx + 40), *(short*)($lx + 44)
    bt
    quit
  end
  continue
end

b *0x40549a
commands 2
  silent
  set $pr = $rdi
  set $lx = *(void**)($pr + 48)
  printf "prep_handle_directive called at %s:%d:%d\n", *(char**)($lx + 32), *(int*)($lx + 40), *(short*)($lx + 44)
  finish
  printf "prep_handle_directive returned %d\n", $rax
  if $rax != 0
    printf "prep_handle_directive failed!\n"
    bt
    quit
  end
  continue
end

run
