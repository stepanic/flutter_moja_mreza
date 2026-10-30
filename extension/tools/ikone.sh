#!/bin/sh
# Ikone ekstenzije iz znaka omm.domovina.ai (public/logo.svg, opcija B).
# Chrome Web Store za 128 traži crtež 96×96 s 16 px praznog ruba.
set -e
cd "$(dirname "$0")/../ikone"
for v in 16 32 48; do rsvg-convert -w $v -h $v ikona.svg -o ikona-$v.png; done
t=$(mktemp -d)
rsvg-convert -w 96 -h 96 ikona.svg -o "$t/96.png"
magick "$t/96.png" -background none -gravity center -extent 128x128 ikona-128.png
rm -r "$t"
