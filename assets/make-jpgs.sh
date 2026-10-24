#!/bin/sh
rm -rf converted \
&& mkdir converted \
&& mkdir converted/0.9.0 \
&& for png in *.png 0.9.0/*.png
	do magick "$png" -quality 98 "converted/$png.jpg";
done
