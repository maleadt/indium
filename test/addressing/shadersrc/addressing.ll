; Copyright (C) 2026 Darling Developers
;
; Hand-written AIR for the kernels in addressing.cpp, in the shapes Metal's compiler and LLVM's
; optimizer give pointer code. Every kernel takes the output buffer, an input buffer and the
; thread's position in the grid, and writes one int per thread. See README.md for how this becomes
; addressing.metallib.

source_filename = "addressing"
target datalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32"
target triple = "air64-apple-macosx10.15.0"

; struct Params { int scale; int offset; }, named only in air.arg_type_name, as when the module
; declares no struct types: out[id] = params.offset + id
define void @undeclared_struct(ptr addrspace(1) %out, ptr addrspace(1) %params, i32 %id) #0 {
  %offsetp = getelementptr inbounds i8, ptr addrspace(1) %params, i64 4
  %offset = load i32, ptr addrspace(1) %offsetp, align 4
  %v = add i32 %offset, %id
  %i = zext i32 %id to i64
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %v, ptr addrspace(1) %o, align 4
  ret void
}

; struct Array { device int* data; long length; }: out[id] = array.data[id] * 2, through a pointer
; loaded from device memory
define void @loaded_pointer(ptr addrspace(1) %out, ptr addrspace(1) %array, i32 %id) #0 {
  %data = load ptr addrspace(1), ptr addrspace(1) %array, align 8
  %i = zext i32 %id to i64
  %p = getelementptr inbounds i32, ptr addrspace(1) %data, i64 %i
  %x = load i32, ptr addrspace(1) %p, align 4
  %v = shl i32 %x, 1
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %v, ptr addrspace(1) %o, align 4
  ret void
}

attributes #0 = { nounwind }

!llvm.module.flags = !{!0}
!air.version = !{!1}
!air.language_version = !{!2}
!air.kernel = !{!10, !20}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 2, i32 2, i32 0}
!2 = !{!"Metal", i32 2, i32 2, i32 0}
!3 = !{}
!4 = !{i32 0, !"air.buffer", !"air.location_index", i32 0, i32 1, !"air.read_write", !"air.arg_type_size", i32 4, !"air.arg_type_align_size", i32 4, !"air.arg_type_name", !"int", !"air.arg_name", !"out"}
!5 = !{i32 2, !"air.thread_position_in_grid", !"air.arg_type_name", !"uint", !"air.arg_name", !"id"}
!6 = !{i32 1, !"air.buffer", !"air.location_index", i32 1, i32 1, !"air.read", !"air.arg_type_size", i32 4, !"air.arg_type_align_size", i32 4, !"air.arg_type_name", !"int", !"air.arg_name", !"in"}

!10 = !{ptr @undeclared_struct, !3, !11}
!11 = !{!4, !12, !5}
!12 = !{i32 1, !"air.buffer", !"air.location_index", i32 1, i32 1, !"air.read", !"air.arg_type_size", i32 8, !"air.arg_type_align_size", i32 4, !"air.arg_type_name", !"Params", !"air.arg_name", !"params"}

!20 = !{ptr @loaded_pointer, !3, !21}
!21 = !{!4, !22, !5}
!22 = !{i32 1, !"air.buffer", !"air.location_index", i32 1, i32 1, !"air.read", !"air.arg_type_size", i32 16, !"air.arg_type_align_size", i32 8, !"air.arg_type_name", !"Array", !"air.arg_name", !"array"}
