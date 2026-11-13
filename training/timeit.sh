#!/usr/bin/env bash
# usage: timeit.sh <label> <command...>   (appends "<label> <seconds>" to work/timings.txt)
label="$1"; shift
mkdir -p work
start=$(date +%s)
"$@"
rc=$?
echo "$label $(( $(date +%s) - start ))" >> work/timings.txt
exit $rc
