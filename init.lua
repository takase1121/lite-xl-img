-- mod-version:3
local core = require "core"
local common = require "core.common"
local config = require "core.config"
local command = require "core.command"
local style = require "core.style"
local View = require "core.view"

local subprocess = require "process"

config.plugins.img = {
    bin_path = USERDIR .. "/plugins/img/img",
    max_pixels = 5000
}

local conf = config.plugins.img

local function open_img(filename)
    local proc = subprocess.start { conf.bin_path, filename }
    
    local buf = {}
    local size = 0
    while true do
        local data = proc:read_stdout()
        if not data then
            break
        end

        size = size + #buf
        if size % 10000 == 0 then
            core.redraw = true
            coroutine.yield(0, size)
        end
        buf[#buf+1] = data
    end

    if proc:returncode() == 0 then
        buf = table.concat(buf)
        local w, h, c, start = buf:match("^img;(%d+);(%d+);(%d+);()")
        return true, w, h, c, buf:sub(start)
    else
        buf = {}
        while true do
            local data = proc:read_stderr()
            if not data then
                break
            end
            buf[#buf+1] = data
        end
        return false, table.concat(buf)
    end
end

local function trampoline(f, cb, ...)
    local c = coroutine.create(f)
    local ret
    while true do
        ret = { coroutine.resume(c, ...) }
        if coroutine.status(c) == "dead" then
            break
        else
            pcall(cb, table.unpack(ret, 3))

            -- yield to core.add_thread
            coroutine.yield(ret[2])
        end
    end
    return table.unpack(ret, 2)
end


local ImgView = View:extend()

function ImgView:new()
    ImgView.super.new(self)

    self.error = "Not loaded"
    self.img = { x = 0, y = 0, c = 0 }
    self.last = 1

    self.rect = { x = 0, y = 0, w = 0, h = 0 }
    self.occluded_by = 1
end

function ImgView:load(filename)
    core.add_thread(function()
        local ok, w, h, c, buf = trampoline(open_img, function(current)
            self.error = string.format("Loading... (%s) bytes", current)
        end, filename)
        
        if ok then
            self.error = nil
            self.img.x, self.img.y, self.img.c = w, h, c
            self.img.buf = buf
            self.img.size = w * h
        else
            self.error = w
        end
    end, self)
end

function ImgView:unload()
    self.error = "Not loaded"
    self.img.x, self.img.y, self.img.c = 0, 0, 0
    self.img.buf = nil
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
        local target_rect = {x = x, y = y, w = w, h = h}
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

function ImgView:update()
    ImgView.super.update(self)

    if self.occluded_by == 1 then
        self.last = 1
    end

    self.rect.x, self.rect.y = self:get_content_offset()
    self.rect.w, self.rect.h = self.size.x, self.size.y

    if self.size.x > 0 and self.size.y > 0 and not self.hooked then
        self:hook()
    end
end


function ImgView:draw()
    local ox, oy = self:get_content_offset()
    local color = {}
    
    if self.error then
        self:draw_background(style.background)
        common.draw_text(style.big_font, style.text, self.error, "center", ox, oy, self.size.x, self.size.y)
    else
        if self.last == 1 then
            self:draw_background(style.background)
        end

        local max_screen = self.img.x * self.size.y
        local max_pixels = math.min(conf.max_pixels, self.img.size, self.img.size - self.last, max_screen - self.last)
        if max_pixels > 0 then
            core.redraw = true
        else
            return
        end

        local next_i = self.last + max_pixels
        for i = self.last, next_i do
            local x, y = ox + (i-1) % self.img.x, oy + math.floor((i-1) / self.img.x)
            local stride_i = i * 4
            color[1], color[2], color[3], color[4] = self.img.buf:byte(stride_i - 3, stride_i)
            renderer.draw_rect(x, y, 1, 1, color, self)
        end
        self.last = next_i
    end
end

command.add(ImgView, {
    ["img:load"] = function()
        local v = core.active_view
        v:load("test2.png")
    end
})

command.add(nil, {
    ["img:open"] = function()
        local node = core.root_view:get_active_node()
        node:add_view(ImgView())
        command.perform "img:load"
    end
})