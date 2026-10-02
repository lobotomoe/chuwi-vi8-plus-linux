#!/bin/sh
# Total resident memory and process count for a browser, by matching the
# process's own exe path rather than a substring of every command line.
pattern="$1"
ps -eo rss=,args= | awk -v p="$pattern" '
    index($0, p) && !/awk/ { total += $1; count++ }
    END { printf "%s: %d MB over %d processes\n", p, total/1024, count }'
