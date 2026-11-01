#!/bin/sh
# A feedback command that passes at baseline and can be made to fail on demand.
#   experiment/BREAK_LOUD   -> fails with an error line on stderr
#   experiment/BREAK_SILENT -> fails with no output at all
# Passing prints nothing, so it adds no signatures to the baseline.
cd "$(dirname "$0")"
if [ -e BREAK_LOUD ]; then echo "probe: FAIL (BREAK_LOUD present)" >&2; exit 1; fi
if [ -e BREAK_SILENT ]; then exit 1; fi
exit 0
