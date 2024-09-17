## What was I doing?

I was trying to convert the entire map of Super Metroid into SNES VRAM.  Got tired of the boring old automap.

This means reducing the rooms that are 256 pixels wide (16 pixels per blocks, 16 blocks per room), 
converting them down to 8x8 sprites, 
converting allll their collective colors down to 256 colors (4bpp) with no more than 16 colors (4pp) per 8x8 sprite,
and then converting the collection of allll unique tiles into a quantized number of tiles that can fit into a SNES tilemap.

## How far did I get?

![](results/map-tex-region-0-small-brighter-16tiles-16colors-dsqa.png)
![](results/map-tex-region-1-small-brighter-16tiles-16colors-dsqa.png)
![](results/map-tex-region-2-small-brighter-16tiles-16colors-dsqa.png)
![](results/map-tex-region-3-small-brighter-16tiles-16colors-dsqa.png)
![](results/map-tex-region-4-small-brighter-16tiles-16colors-dsqa.png)
![](results/map-tex-region-5-small-brighter-16tiles-16colors-dsqa.png)
![](results/map-tex-region-6-small-brighter-16tiles-16colors-dsqa.png)
![](results/map-tex-region-7-small-brighter-16tiles-16colors-dsqa.png)

## How does it get there?

I kind of forgot, here's my best attempt ...

I start with the original map.

![](results/map-tex-region-0.png)

I size it down from 256x256 to 8x8

![](results/map-tex-region-0-small.png)

I brighten this up a bit

![](results/map-tex-region-0-small-brighter.png)

I enumerate all unique 8x8 room sprites:

![](results/map-tex-region-0-small-brighter-quantized-tiles.png)
![](results/map-tex-region-1-small-brighter-quantized-tiles.png)
![](results/map-tex-region-2-small-brighter-quantized-tiles.png)
![](results/map-tex-region-3-small-brighter-quantized-tiles.png)
![](results/map-tex-region-4-small-brighter-quantized-tiles.png)
![](results/map-tex-region-5-small-brighter-quantized-tiles.png)
![](results/map-tex-region-6-small-brighter-quantized-tiles.png)
![](results/map-tex-region-7-small-brighter-quantized-tiles.png)

I quantize this.  Left is the resulting tile in the destination image, right is the collection of source image tiles that map to this result:

![](results/map-tex-region-0-small-brighter-quantize-tile-map.png)![](results/map-tex-region-1-small-brighter-quantize-tile-map.png)![](results/map-tex-region-2-small-brighter-quantize-tile-map.png)![](results/map-tex-region-3-small-brighter-quantize-tile-map.png)![](results/map-tex-region-4-small-brighter-quantize-tile-map.png)![](results/map-tex-region-5-small-brighter-quantize-tile-map.png)![](results/map-tex-region-6-small-brighter-quantize-tile-map.png)![](results/map-tex-region-7-small-brighter-quantize-tile-map.png)

... then rebuild tiles in map from this key

![](results/map-tex-region-0-small-brighter-16tiles-16colors-dsqa-quant-tiles-before.png)
![](results/map-tex-region-1-small-brighter-16tiles-16colors-dsqa-quant-tiles-before.png)
![](results/map-tex-region-2-small-brighter-16tiles-16colors-dsqa-quant-tiles-before.png)
![](results/map-tex-region-3-small-brighter-16tiles-16colors-dsqa-quant-tiles-before.png)
![](results/map-tex-region-4-small-brighter-16tiles-16colors-dsqa-quant-tiles-before.png)
![](results/map-tex-region-5-small-brighter-16tiles-16colors-dsqa-quant-tiles-before.png)
![](results/map-tex-region-6-small-brighter-16tiles-16colors-dsqa-quant-tiles-before.png)
![](results/map-tex-region-7-small-brighter-16tiles-16colors-dsqa-quant-tiles-before.png)

I downsample the image from 256x256 pixels per room to 8x8 pixels per room, and I enumerate all unique tiles:

![](results/map-tex-region-0-small-brighter-1pix-per-tile-before-downsample.png)
![](results/map-tex-region-1-small-brighter-1pix-per-tile-before-downsample.png)
![](results/map-tex-region-2-small-brighter-1pix-per-tile-before-downsample.png)
![](results/map-tex-region-3-small-brighter-1pix-per-tile-before-downsample.png)
![](results/map-tex-region-4-small-brighter-1pix-per-tile-before-downsample.png)
![](results/map-tex-region-5-small-brighter-1pix-per-tile-before-downsample.png)
![](results/map-tex-region-6-small-brighter-1pix-per-tile-before-downsample.png)
![](results/map-tex-region-7-small-brighter-1pix-per-tile-before-downsample.png)

Then I downsample further to 1x1 pixel per room:

![](results/map-tex-region-0-small-brighter-1pix-per-tile-after-downsample.png)
![](results/map-tex-region-1-small-brighter-1pix-per-tile-after-downsample.png)
![](results/map-tex-region-2-small-brighter-1pix-per-tile-after-downsample.png)
![](results/map-tex-region-3-small-brighter-1pix-per-tile-after-downsample.png)
![](results/map-tex-region-4-small-brighter-1pix-per-tile-after-downsample.png)
![](results/map-tex-region-5-small-brighter-1pix-per-tile-after-downsample.png)
![](results/map-tex-region-6-small-brighter-1pix-per-tile-after-downsample.png)
![](results/map-tex-region-7-small-brighter-1pix-per-tile-after-downsample.png)

Then I do something else, can't remember

![](results/map-tex-region-0-small-brighter-1pix-per-tile-after-color-adjust.png)
![](results/map-tex-region-1-small-brighter-1pix-per-tile-after-color-adjust.png)
![](results/map-tex-region-2-small-brighter-1pix-per-tile-after-color-adjust.png)
![](results/map-tex-region-3-small-brighter-1pix-per-tile-after-color-adjust.png)
![](results/map-tex-region-4-small-brighter-1pix-per-tile-after-color-adjust.png)
![](results/map-tex-region-5-small-brighter-1pix-per-tile-after-color-adjust.png)
![](results/map-tex-region-6-small-brighter-1pix-per-tile-after-color-adjust.png)
![](results/map-tex-region-7-small-brighter-1pix-per-tile-after-color-adjust.png)

Then I quantize it to 16 colors:

![](results/map-tex-region-0-small-brighter-1pix-per-tile-after-quant.png)
![](results/map-tex-region-1-small-brighter-1pix-per-tile-after-quant.png)
![](results/map-tex-region-2-small-brighter-1pix-per-tile-after-quant.png)
![](results/map-tex-region-3-small-brighter-1pix-per-tile-after-quant.png)
![](results/map-tex-region-4-small-brighter-1pix-per-tile-after-quant.png)
![](results/map-tex-region-5-small-brighter-1pix-per-tile-after-quant.png)
![](results/map-tex-region-6-small-brighter-1pix-per-tile-after-quant.png)
![](results/map-tex-region-7-small-brighter-1pix-per-tile-after-quant.png)

... this gives me the 16 unique palettes to be used for my 16 different high-nibbles.
From there I look at all the tiles associated with each of the 16 groups:

![](results/color%200%20tiles.png)
![](results/color%201%20tiles.png)
![](results/color%202%20tiles.png)
![](results/color%203%20tiles.png)
![](results/color%204%20tiles.png)
![](results/color%205%20tiles.png)
![](results/color%206%20tiles.png)
![](results/color%207%20tiles.png)
![](results/color%208%20tiles.png)
![](results/color%209%20tiles.png)
![](results/color%2010%20tiles.png)
![](results/color%2011%20tiles.png)
![](results/color%2012%20tiles.png)
![](results/color%2013%20tiles.png)
![](results/color%2014%20tiles.png)
![](results/color%2015%20tiles.png)

... and I quantize their colors ...

![](results/color%20quant15%200%20tiles.png)
![](results/color%20quant15%201%20tiles.png)
![](results/color%20quant15%202%20tiles.png)
![](results/color%20quant15%203%20tiles.png)
![](results/color%20quant15%204%20tiles.png)
![](results/color%20quant15%205%20tiles.png)
![](results/color%20quant15%206%20tiles.png)
![](results/color%20quant15%207%20tiles.png)
![](results/color%20quant15%208%20tiles.png)
![](results/color%20quant15%209%20tiles.png)
![](results/color%20quant15%2010%20tiles.png)
![](results/color%20quant15%2011%20tiles.png)
![](results/color%20quant15%2012%20tiles.png)
![](results/color%20quant15%2013%20tiles.png)
![](results/color%20quant15%2014%20tiles.png)
![](results/color%20quant15%2015%20tiles.png)

...then collect those 16 quantized 16 colors into 256-color palettes for each region:

<img src="results/map-tex-region-0-small-brighter-dsqa-palette.png" width="256" style="image-rendering:pixelated; width:256"/><br>
<img src="results/map-tex-region-1-small-brighter-dsqa-palette.png" width="256" style="image-rendering:pixelated; width:256"/><br>
<img src="results/map-tex-region-2-small-brighter-dsqa-palette.png" width="256" style="image-rendering:pixelated; width:256"/><br>
<img src="results/map-tex-region-3-small-brighter-dsqa-palette.png" width="256" style="image-rendering:pixelated; width:256"/><br>
<img src="results/map-tex-region-4-small-brighter-dsqa-palette.png" width="256" style="image-rendering:pixelated; width:256"/><br>
<img src="results/map-tex-region-5-small-brighter-dsqa-palette.png" width="256" style="image-rendering:pixelated; width:256"/><br>
<img src="results/map-tex-region-6-small-brighter-dsqa-palette.png" width="256" style="image-rendering:pixelated; width:256"/><br>
<img src="results/map-tex-region-7-small-brighter-dsqa-palette.png" width="256" style="image-rendering:pixelated; width:256"/><br>

... and that brings us to the end:

![](results/map-tex-region-0-small-brighter-16tiles-16colors-dsqa.png)
![](results/map-tex-region-1-small-brighter-16tiles-16colors-dsqa.png)
![](results/map-tex-region-2-small-brighter-16tiles-16colors-dsqa.png)
![](results/map-tex-region-3-small-brighter-16tiles-16colors-dsqa.png)
![](results/map-tex-region-4-small-brighter-16tiles-16colors-dsqa.png)
![](results/map-tex-region-5-small-brighter-16tiles-16colors-dsqa.png)
![](results/map-tex-region-6-small-brighter-16tiles-16colors-dsqa.png)
![](results/map-tex-region-7-small-brighter-16tiles-16colors-dsqa.png)

## How to use this tool:

0) copy images from [super-metroid-randomizer](https://github.com/thenumbernine/super-metroid-randomizer-lua) to here: map-tex.png or map-tex-region-\*.png
1) resize-images.lua to generate 1/32 scale images as map-tex-small.png, map-tex-region-\*-small.png
2) brighten-small-images.lua to generate map-tex-brighter.png, map-tex-region-\*-small-brighter.png
3) run.lua to generate all sorts of debug nonsense, hopefully eventually generate 
	- a 256-color palette, 
	- a 4bpp image of 8x8 graphics tiles (probably 16 tiles wide), no more than 768, or 256, or 80, or so
	- a tilemap indexing into the graphics tiles, specifying 
		- the tile, 
		- whether to flip it horz, or vert, 
		- and what 4bpp upper bits to use for this tile
