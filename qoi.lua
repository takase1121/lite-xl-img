--[[============================================================
--=
--=  SloppyQOI - QOI image format encoder/decoder for LÖVE (now for Lua 5.4)
--=  - Written by Marcus 'ReFreezed' Thunström
--=  - Modified by takase1121
--=  - MIT License (See the bottom of this file)
--=
--=  Following QOI v1.0 spec: https://qoiformat.org/
--=
--=  Encoder ported from Dominic Szablewski's C/C++ library
--=  - https://github.com/phoboslab/qoi
--=  - MIT License - Copyright © 2021 Dominic Szablewski
--=
--==============================================================

	local qoi = require("qoi")

	imageData, channels, colorSpace = qoi.decode( dataString )
	Decode QOI data.
	Returns nil and a message on error.

	dataString = qoi.encode( imageData [, channels=4, colorSpace="linear" ] )
	channels   = 3 | 4
	colorSpace = "linear" | "srgb"
	Encode an image to QOI data.
	The PixelFormat for imageData must currently be "rgba8".
	Returns nil and a message on error.

	imageData, channels, colorSpace = qoi.read( path )
	Read a QOI file (using love.filesystem).
	Returns nil and a message on error.

	success, error = qoi.write( imageData, path [, channels=4, colorSpace="linear" ] )
	channels       = 3 | 4
	colorSpace     = "linear" | "srgb"
	Write an image to a QOI file (using love.filesystem).
	The PixelFormat for imageData must currently be "rgba8".

	image = qoi.load( path )
	Load a QOI file as an image (like love.graphics.newImage).

	qoi._VERSION
	The current version of the library, e.g. "1.8.2".

--============================================================]]

local qoi = {
	_VERSION = "1.1.0",
}

function qoi.decode_iterator(self)
	local getByte = string.byte
	local s = self.s
	local pos = self.pos
	local seen = self.seen

	local prevR = self.prevR
	local prevG = self.prevG
	local prevB = self.prevB

	local r = self.r
	local g = self.g
	local b = self.b
	local a = self.a

	if self.pixel >= self.size then
		if self.run > 0 then
			return error "Corrupt data."
		end

		if s:sub(pos, pos+7) ~= "\0\0\0\0\0\0\0\1" then
			return error "Missing data end marker."
		end
		pos = pos + 8

		if pos <= #s then
			return error "Junk after data."
		end

		return nil
	end

	if self.run > 0 then
		self.run = self.run - 1

	else
		local byte1 = getByte(s, pos)
		if not byte1 then  return error "Unexpected end of data stream."  end
		pos = pos + 1

		-- QOI_OP_RGB 11111110
		if byte1 == 254--[[11111110]] then
			r, g, b = getByte(s, pos, pos+2)
			if not b then  return error "Unexpected end of data stream."  end
			pos = pos + 3

		-- QOI_OP_RGBA 11111111
		elseif byte1 == 255--[[11111111]] then
			r, g, b, a = getByte(s, pos, pos+3)
			if not a then  return error "Unexpected end of data stream."  end
			pos = pos + 4

		-- QOI_OP_INDEX 00xxxxxx
		elseif byte1 < 64--[[01000000]] then
			local hash4 = byte1 << 2

			r = seen[hash4+1]
			g = seen[hash4+2]
			b = seen[hash4+3]
			a = seen[hash4+4]

		-- QOI_OP_DIFF 01xxxxxx
		elseif byte1 < 128--[[10000000]] then
			byte1 = byte1 - 64--[[01000000]]

			r = prevR + ((byte1 & 48--[[00110000]]) >> 4) - 2
			g = prevG + ((byte1 & 12--[[00001100]]) >> 2) - 2
			b = prevB +  (byte1 & 3 --[[00000011]])       - 2

		-- QOI_OP_LUMA 10xxxxxx
		elseif byte1 < 192--[[11000000]] then
			local byte2 = getByte(s, pos)
			if not byte2 then  return error "Unexpected end of data stream."  end
			pos = pos + 1

			local diffG = byte1 + (-(128--[[10000000]]) - 32)

			g = prevG + diffG
			r = prevR + diffG + ((byte2 & 240--[[11110000]]) >> 4) - 8
			b = prevB + diffG +  (byte2 & 15 --[[00001111]])       - 8

		-- QOI_OP_RUN 11xxxxxx
		else
			self.run = byte1 - 192--[[11000000]]
		end

		prevR = r
		prevG = g
		prevB = b
	end

	local hash4   = (r*3+g*5+b*7+a*11 & 63--[[00111111]]) << 2
	seen[hash4+1] = r
	seen[hash4+2] = g
	seen[hash4+3] = b
	seen[hash4+4] = a

	-- save state
	self.pos = pos

	self.prevR = prevR
	self.prevG = prevG
	self.prevB = prevB

	self.r = r
	self.g = g
	self.b = b
	self.a = a

	self.pixel = self.pixel + 1

	return self, r, g, b, a
end


function qoi.copy(state)
	local s = {}

	s.s = state.s
	s.pos = state.pos
	s.channels = state.channels
	s.colorSpace = state.colorSpace
	s.w = state.w
	s.h = state.h
	s.size = state.size
	
	s.pixel = state.pixel

	s.prevR = state.prevR
	s.prevG = state.prevG
	s.prevB = state.prevB

	s.r = state.r
	s.g = state.g
	s.b = state.b
	s.a = state.a

	s.run = state.run

	s.seen = {}
	for i = 1, #state.seen do
		s.seen[i] = state.seen[i]
	end

	return s
end


-- imageData, channels, colorSpace = qoi.decode( dataString )
-- Returns nil and a message on error.
function qoi.decode(s)
	assert(type(s) == "string")

	local pos = 1

	--
	-- Header.
	--
	local getByte = string.byte

	if s:sub(pos, pos+3) ~= "qoif" then
		return error "Invalid signature."
	end
	pos = pos + 4

	if #s < 14 then -- Header is 14 bytes.
		return error "Missing part of header."
	end

	local w = 256^3*getByte(s, pos) + 256^2*getByte(s, pos+1) + 256*getByte(s, pos+2) + getByte(s, pos+3)
	if w == 0 then  return error "Invalid width (0)."  end
	pos = pos + 4

	local h = 256^3*getByte(s, pos) + 256^2*getByte(s, pos+1) + 256*getByte(s, pos+2) + getByte(s, pos+3)
	if h == 0 then  return error "Invalid height (0)."  end
	pos = pos + 4

	local channels = getByte(s, pos)
	if not (channels == 3 or channels == 4) then
		return error "Invalid channel count."
	end
	pos = pos + 1

	local colorSpace = getByte(s, pos)
	if colorSpace > 1 then
		return error "Invalid color space value."
	end
	colorSpace = (colorSpace == 0 and "srgb" or "linear")
	pos        = pos + 1


	local state = {}

	state.s = s
	state.pos = pos
	state.channels = channels
	state.colorSpace = colorSpace
	state.w = w
	state.h = h
	state.size = w * h

	state.pixel = 0

	state.seen = {
		-- 64 RGBA pixels.
		0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
		0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
		0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
		0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
	}

	state.prevR = 0 -- Note: All these color values are treated as signed bytes.
	state.prevG = 0
	state.prevB = 0

	state.r = 0
	state.g = 0
	state.b = 0
	state.a = 255

	state.run = 0

	return qoi.decode_iterator, state
end

return qoi

--==============================================================
--=
--=  MIT License
--=
--=  Copyright © 2022 Marcus 'ReFreezed' Thunström
--=
--=  Permission is hereby granted, free of charge, to any person obtaining a copy
--=  of this software and associated documentation files (the "Software"), to deal
--=  in the Software without restriction, including without limitation the rights
--=  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--=  copies of the Software, and to permit persons to whom the Software is
--=  furnished to do so, subject to the following conditions:
--=
--=  The above copyright notice and this permission notice shall be included in all
--=  copies or substantial portions of the Software.
--=
--=  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--=  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--=  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--=  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--=  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--=  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--=  SOFTWARE.
--=
--==============================================================
