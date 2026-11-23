# addressing

Compute kernels that reach memory through the pointer shapes AIR producers emit:

- `undeclared_struct`: a buffer whose `air.arg_type_name` names a struct the module doesn't declare,
  read at a byte offset;
- `loaded_pointer`: a device pointer loaded from a buffer, then indexed;
- `pointer_select`, `pointer_phi`, `pointer_integer`: device pointers chosen by a `select`, carried
  around a loop by a `phi`, and converted to and from integers and compared with null;
- `threadgroup_derived`, `private_derived`: a `getelementptr` on a pointer derived from a threadgroup
  or private array (`p = buf + id; p[1]`), and byte offsets into it;
- `threadgroup_bytes`: threadgroup memory declared as bytes, as Metal.jl declares it, read and
  written as ints through a base before the array and through byte offsets;
- `threadgroup_subword`: threads writing neighbouring bytes of threadgroup memory;
- `threadgroup_phi`: threadgroup pointers chosen by a `select`, carried by a `phi` and compared;
- `threadgroup_atomic`: an atomic at a byte offset into threadgroup memory;
- `threadgroup_punning`, `threadgroup_mixed_width`, `private_punning`: memory accessed as several
  types: floats and ints in one pool, longs, bytes and structs in one pool, two halves read as an int;
- `threadgroup_dead`: threadgroup memory that is written and copied but never read;
- `private_merged`, `threadgroup_merged`: a pointer that may point into either of two arrays.

`refused/escaped.ll` converts a threadgroup address to an integer, which has no translation, and
`refused/atomic_narrow.ll` writes single bytes of memory that an atomic updates as ints.

Each thread writes one int, and the host compares it with the value the kernel's comment defines.
`check.sh` (registered with ctest) translates the library with `mtl2spv`, validates it with
`spirv-val`, and checks that each library in `refused/` fails with the message its source names.

## Provenance of the .metallib files

No Metal compiler was used. `shadersrc/addressing.ll` and `refused/*.ll` are hand-written AIR, wrapped
in the MTLB container Iridium reads:

    llvm-as shadersrc/addressing.ll -o addressing.air
    ../air-ops/make-metallib.py addressing.air addressing.metallib kernel:undeclared_struct kernel:loaded_pointer \
        kernel:pointer_select kernel:pointer_phi kernel:pointer_integer kernel:threadgroup_derived \
        kernel:private_derived kernel:threadgroup_bytes kernel:threadgroup_subword kernel:threadgroup_phi \
        kernel:threadgroup_atomic kernel:threadgroup_punning kernel:threadgroup_mixed_width \
        kernel:private_punning kernel:threadgroup_dead kernel:private_merged kernel:threadgroup_merged

and each `refused/<name>.ll` the same way, with `kernel:<name>`.

Assemble with an LLVM no newer than the oldest Iridium supports (LLVM 19), since newer bitcode may
not be readable by an older one. These were assembled with LLVM 18.
