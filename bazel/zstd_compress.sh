#!/bin/bash
# Compressor for pkg_tar: reads tar stream on stdin, writes zstd-compressed
# stream on stdout. Matches the CI tarball compression flags:
#   --adapt=min=9  adaptive compression (minimum level 9)
#   -T0            use all available threads
exec zstd --adapt=min=9 -T0
