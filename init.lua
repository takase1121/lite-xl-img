-- mod-version:3
local core = require "core"
local common = require "core.common"
local config = require "core.config"
local command = require "core.command"
local style = require "core.style"
local View = require "core.view"

local subprocess = require "process"

local qoi = require "plugins.img.qoi"


config.plugins.img = {
  bin_path = USERDIR .. "/plugins/img/img",
  max_pixels = 5000
}

local C = config.plugins.img


local function poll_read(proc, r)
  local buf = {}
  while true do
    local data = proc:read(r)
    if not data then break end

    buf[#buf+1] = data
    coroutine.yield(0)
  end
  return table.concat(buf)
end

local function convert(img)
  local proc = subprocess.start { C.bin_path, img }

  local stdout = poll_read(proc, subprocess.STREAM_STDOUT)
  local success = proc:returncode() == 0

  return success, success and stdout or poll_read(proc, subprocess.STREAM_STDERR)
end


local ImgView = View:extend()

function ImgView:new()
  ImgView.super.new(self)

  self.loading = false
  self.error = "Not loaded"

  self.rect = { x = 0, y = 0, w = 0, h = 0 }
  self.occluded_by = 1
end

function ImgView:load(filename)
  self.img = nil
  self.error = nil

  local f, err = io.open(filename, "rb")
  if not f then
    self.error = err
    return
  end

  -- try to check if the file is QOI.
  -- the magic for QOI is "qoif"
  if f:read(4) == "qoif" then
    -- load qoi
    f:seek("set", 0)
    local buf = f:read("a")
    f:close()

    local ok, img = pcall(qoi.decode, buf)
    if ok then
      self.img = img
    end
  else
    -- call the converter
    core.add_thread(function()
      self.loading = true
      local ok, img = convert(filename)
      if ok then
        ok, img = pcall(qoi.decode, img)
      end

      if ok then
        self.img = img
      else
        self.error = img
      end

      self.loading = false
    end)
  end
end

function ImgView:unload()
  self.img = nil
  self.error = "Not loaded"
end

local function overlap(a, b)
  return math.floor(a.w) > 0 and math.floor(b.w) > 0 and math.floor(a.h) > 0 and math.floor(b.h) > 0
      and b.x + b.w >= a.x and b.x <= a.x + a.w
      and b.y + b.h >= a.y and b.y <= a.y + a.h
end

local function clip(a, b)
  local x1 = math.max(a.x, b.x);
  local y1 = math.max(a.y, b.y);
  local x2 = math.min(a.x + a.w, b.x + b.w);
  local y2 = math.min(a.y + a.h, b.y + b.h);

  a.x, a.y, a.w, a.h = x1, y1, math.max(0, x2 - x1), math.max(0, y2 - y1)
end

function ImgView:hook()
  self.original_draw_rect = renderer.draw_rect
  self.original_clip = renderer.set_clip_rect
  -- heres the crazy part.
  -- we'll hook renderer.draw_rect and check if our thing is occluded in this frame
  -- if it WAS occluded then we'll rerender
  -- if it WAS NOT occluded then we can skip
  -- this requires a lua side "rencache", but only 1 rectangle, for simplicity
  -- of course you can implement the grid

  function renderer.draw_rect(x, y, w, h, color, source)
    -- we actually need to consider the clip rect
    local target_rect = { x = x, y = y, w = w, h = h }
    clip(target_rect, self.rect)

    if overlap(target_rect, self.rect) then
      self.occluded_by = source == self and self or 1
    end
    self.original_draw_rect(x, y, w, h, color)
  end

  self.hooked = true
end

function ImgView:unhook()
  if not self.hooked then return end
  renderer.draw_rect = self.original_draw_rect
  renderer.set_clip_rect = self.original_clip
end

function ImgView:try_close(do_close)
  self:unload()
  self:unhook()
  ImgView.super.try_close(self, do_close)
end

function ImgView:update()
  ImgView.super.update(self)

  local ox, oy = self:get_content_offset()
  if self.img then
    if self.occluded_by == 1 then
      self.img:reset()
    end

    if ox ~= self.rect.x or oy ~= self.rect.y
      or self.size.x ~= self.rect.w or self.size.y ~= self.rect.h then
      self.img:reset()
    end
  end

  self.rect.x, self.rect.y = ox, oy
  self.rect.w, self.rect.h = self.size.x, self.size.y

  if self.size.x > 0 and self.size.y > 0 and not self.hooked then
    self:hook()
  end
end

function ImgView:draw()
  local ox, oy = self:get_content_offset()
  local color = {}

  if self.loading then
    self:draw_background(style.background)

    local lh = style.font:get_height()
    local max_square = style.big_font:get_height()
    local half_max_square = max_square / 2
    local square = math.sin((system.get_time() % 1) * math.pi) * max_square
    local half_square = square / 2

    local cx, cy = self.size.x / 2, self.size.y / 2
    local uty = oy + cy - half_max_square - (2 * style.padding.y) - lh
    local lty = oy + cy + half_max_square + (2 * style.padding.y)
    local px = ox + cx - half_square
    local py = oy + cy - half_square

    common.draw_text(style.font, style.text, "Converting image to qoi...", "center", ox, uty, self.size.x, lh)
    common.draw_text(style.font, style.text, "If the progress stops, move your mouse.", "center", ox, lty, self.size.x, lh)
    renderer.draw_rect(px, py, square, square, style.accent)

  elseif self.error then
    self:draw_background(style.background)
    common.draw_text(style.font, style.text, self.error, "center", ox, oy, self.size.x, self.size.y)

  elseif self.img then
    local current_i = self.img.pixel
    if current_i == 0 then
      -- resetted, redrawing background
      self:draw_background(style.background)
    end

    -- note that pixels that are clipped from the viewport needs to be accounted for
    -- thats why the width is the image width not the viewport width
    local max_viewport = self.img.w * self.size.y
    local max_img = self.img.size
    local max_pixels = math.min(C.max_pixels, max_img - current_i, max_viewport - current_i)
    if max_pixels <= 0 then
      -- finished drawing, do nothing
      return
    else
      -- prevent the editor from pausing
      core.redraw = true
    end

    ox, oy = ox + style.padding.y, oy + style.padding.y
    local next_i = current_i + max_pixels
    for i = current_i, next_i do
      local decoder, r, g, b, a = qoi.decode_iterator(self.img)
      if not decoder then break end

      local x, y = ox + i % self.img.w, oy + i // self.img.w
      color[1], color[2], color[3], color[4] = r, g, b, a
      renderer.draw_rect(x, y, 1, 1, color, self)
    end
  end
end

command.add(ImgView, {
  ["img:load"] = function()
    local v = core.active_view
    core.command_view:enter("QOI file", function(text)
      v:load(text)
    end, common.path_suggest)
  end
})

command.add(nil, {
  ["img:open"] = function()
    local node = core.root_view:get_active_node()
    node:add_view(ImgView())
    command.perform "img:load"
  end
})
