#!/bin/sh
# Usage: check.sh <mtl2spv> <scratch dir>
# Translates addressing.metallib and validates the module, and checks that each library in refused/
# fails translation with the message its .ll names in a "; refused: <text>" line.
set -u
mtl2spv=$1
out=$2
here=$(dirname "$0")
mkdir -p "$out"
failures=0

if "$mtl2spv" "$here/addressing.metallib" "$out/addressing.spv" >"$out/addressing.log" 2>&1 &&
	spirv-val --target-env vulkan1.3 "$out/addressing.spv" >>"$out/addressing.log" 2>&1; then
	echo "PASS addressing.metallib"
else
	echo "FAIL addressing.metallib: $(cat "$out/addressing.log")"
	failures=$((failures + 1))
fi

for lib in "$here"/refused/*.metallib; do
	[ -e "$lib" ] || continue
	name=$(basename "$lib" .metallib)
	want=$(sed -n 's/^; refused: //p' "$here/refused/$name.ll")
	if "$mtl2spv" "$lib" "$out/$name.spv" >"$out/$name.log" 2>&1; then
		echo "FAIL $name translated"
		failures=$((failures + 1))
	elif grep -qF "$want" "$out/$name.log"; then
		echo "PASS $name refused"
	else
		echo "FAIL $name: $(cat "$out/$name.log")"
		failures=$((failures + 1))
	fi
done

exit $((failures != 0))
