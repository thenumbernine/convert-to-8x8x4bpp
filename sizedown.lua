#! /usr/bin/env luajit
local Image = require 'image'
local filename = ... or 'map-tex.png'
local img = Image(filename)

-- resize down from 16x16 = 256 pixels wide per room ... to 8 pixels wide per room

assert(img.width % 32 == 0)
assert(img.height % 32 == 0)

img:resize(img.width / 32, img.height / 32):save'map-tex-small.png'
