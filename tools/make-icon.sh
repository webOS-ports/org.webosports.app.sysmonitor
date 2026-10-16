#!/bin/sh
# Renders images/icon.svg to icon.png and icon-256x256.png (256x256) with
# Qt's SVG renderer, as the app shows it.
#
#   tools/make-icon.sh <svgcheck>
#
# svgcheck is Sound Recorder's tools/vectorize renderer ("svgcheck render
# <svg> <scale> <png>").
set -e
cd "$(dirname "$0")/.."
SVGCHECK=${1:?usage: tools/make-icon.sh <svgcheck>}
"$SVGCHECK" render images/icon.svg 1.0 icon.png
cp icon.png icon-256x256.png
