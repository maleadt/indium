; Copyright (C) 2026 Darling Developers
;
; Hand-written AIR: an atomic on threadgroup memory that is also written a byte at a time, which needs
; elements narrower than the atomic.
; refused: "pool" has atomics as well as accesses narrower than them
source_filename = "atomic_narrow"
target datalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32"
target triple = "air64-apple-macosx10.15.0"

@pool = internal addrspace(3) global [128 x i8] undef, align 4

define void @atomic_narrow(ptr addrspace(1) %out, i32 %id) #0 {
  %i = zext i32 %id to i64
  %b = getelementptr inbounds i8, ptr addrspace(3) @pool, i64 %i
  %t = trunc i32 %id to i8
  store i8 %t, ptr addrspace(3) %b, align 1
  %old = call i32 @air.atomic.local.add.s.i32(ptr addrspace(3) @pool, i32 1, i32 0, i32 1, i1 true)
  %o = getelementptr inbounds i64, ptr addrspace(1) %out, i64 %i
  %w = zext i32 %old to i64
  store i64 %w, ptr addrspace(1) %o, align 8
  ret void
}

declare i32 @air.atomic.local.add.s.i32(ptr addrspace(3), i32, i32, i32, i1)

attributes #0 = { nounwind }

!llvm.module.flags = !{!0}
!air.version = !{!1}
!air.language_version = !{!2}
!air.kernel = !{!3}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 2, i32 2, i32 0}
!2 = !{!"Metal", i32 2, i32 2, i32 0}
!3 = !{ptr @atomic_narrow, !4, !5}
!4 = !{}
!5 = !{!6, !7}
!6 = !{i32 0, !"air.buffer", !"air.location_index", i32 0, i32 1, !"air.read_write", !"air.arg_type_size", i32 8, !"air.arg_type_align_size", i32 8, !"air.arg_type_name", !"long", !"air.arg_name", !"out"}
!7 = !{i32 1, !"air.thread_position_in_grid", !"air.arg_type_name", !"uint", !"air.arg_name", !"id"}
