0) copy images from super-metroid-randomizer to here: map-tex.png or map-tex-region-\*.png
1) resize-images.lua to generate 1/32 scale images as map-tex-small.png, map-tex-region-\*-small.png
2) brighten-small-images.lua to generate map-tex-brighter.png, map-tex-region-\*-small-brighter.png
3) run.lua to generate all sorts of debug nonsense, hopefully eventually generate 
	- a 256-color palette, 
	- a 4bpp image of 8x8 graphics tiles (probably 16 tiles wide), no more than 768, or 256, or 80, or so
	- a tilemap indexing into the graphics tiles, specifying 
		- the tile, 
		- whether to flip it horz, or vert, 
		- and what 4bpp upper bits to use for this tile
