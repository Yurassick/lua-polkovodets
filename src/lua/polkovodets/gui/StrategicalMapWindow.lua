--[[

Copyright (C) 2016 Ivan Baidakou

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

]]--

local _ = require ("moses")
local inspect = require('inspect')

local SDL = require "SDL"
local Image = require 'polkovodets.utils.Image'
local Region = require 'polkovodets.utils.Region'

local StrategicalMapWindow = {}
StrategicalMapWindow.__index = StrategicalMapWindow

local FONT_SIZE = 12
local AVAILABLE_COLOR = 0xAAAAAA
local HILIGHT_COLOR = 0xFFFFFF

local SCROLL_TOLERANCE = 20
-- how many tiles are shifted on scroll
local SCROLL_DELTA = 2

function StrategicalMapWindow.create(engine)
  local theme = engine.gear:get("theme")
  local o = {
    engine           = engine,
    properties       = {
      floating = false,
    },
    drawing          = {
      fn       = nil,
      idle     = nil,
      position = {0, 0}
    },
    text = {
      font  = theme:get_font('default', FONT_SIZE),
    },
    frame = {
      -- in hex coordinates
      hex_box = {
        x = 1,
        y = 1,
        w = 0, -- be calculated later
        h = 0, -- be calculated later
      },
      prev_box = nil,
      -- in pixels
      dst = { -- be calculated later
        x = 0,
        y = 0,
        w = 0,
        h = 0
      },
      screen = {
        w = 0,
        h = 0,
      },
      texture = nil,
    },
  }
  setmetatable(o, StrategicalMapWindow)
  return o
end

function StrategicalMapWindow:_construct_gui()
  local engine = self.engine
  local map = engine.gear:get("map")
  local terrain = engine.gear:get("terrain")
  local hex_geometry = engine.gear:get("hex_geometry")

  local context = self.drawing.context
  local weather = engine:current_weather()

  local get_sclaled_width = function(scale)
    return map.width * hex_geometry.x_offset / scale
  end
  local get_sclaled_height = function(scale)
    return map.height * hex_geometry.height / scale
  end

  local scale = hex_geometry.max_scale
  local w, h = math.modf(get_sclaled_width(scale)), math.modf(get_sclaled_height(scale))

  local scaled_geometry = {
    width    = hex_geometry.width / scale,
    height   = hex_geometry.height / scale,
    x_offset = hex_geometry.x_offset / scale,
    y_offset = hex_geometry.y_offset / scale,
  }
  -- local screen_dx, screen_dy = table.unpack(context.screen.offset)
  local screen_dx, screen_dy = 0, 0

  -- We cannot use common math (virtual coordinates), because rounding errors lead to gaps between tiles,
  -- and they look terribly. Hence, we re-calculate tiels using int-math

  local tile_w, tile_h = math.modf(scaled_geometry.width), math.modf(scaled_geometry.height)
  local x_offset, y_offset = math.modf(scaled_geometry.x_offset), math.modf(scaled_geometry.y_offset)

  local layer = engine.state:get_active_layer()

  -- k: tile_id, value: description
  local tile_positions = {}
  for i = 1, map.width do
    for j = 1, map.height do
      local tile = map.tiles[i][j]
      local dst = {
        x = (i - 1) * x_offset,
        y = (j - 1) * tile_h + ( (i % 2 == 0) and y_offset or 0),
        w = tile_w,
        h = tile_h,
      }
      local image = terrain:get_hex_image(tile.data.terrain_type.id, weather, tile.data.image_idx)
      local flag_data

      local unit = tile:get_unit(layer)

      if (unit) then
        local flag = unit.definition.nation.unit_flag
        flag_data = {
          dst = {
            x = dst.x + (tile_w - x_offset),
            y = dst.y,
            w = tile_w - ((tile_w - x_offset) *2),
            h = tile_h,
          },
          image = flag,
        }
        -- print("flag data " .. inspect(flag_data))
        -- error("dst " .. inspect(dst))
      end

      tile_positions[tile.id] = {
        dst       = dst,
        image     = image,
        flag_data = flag_data,
      }
    end
  end

  local right_tile = map.tiles[map.width][map.height]
  local right_pos = tile_positions[right_tile.id]
  local bot_tile = map.tiles[1][map.height]
  local bot_pos = tile_positions[bot_tile.id]

  w = right_pos.dst.x + x_offset + tile_w
  h = bot_pos.dst.y + tile_h * 2 + y_offset

  local gui = {
    scale = scale,
    scaled_geometry = scaled_geometry,
    content_size = {w = w, h = h},
    tile_positions = tile_positions,
  }
  return gui
end

function StrategicalMapWindow:_map_size(x_min, y_min, x_max, y_max)
  local gui = self.drawing.gui
  local scaled_geometry = gui.scaled_geometry

  local dx = x_max - x_min
  local dy = y_max - y_min
  -- assert(dy >= 2)

  local content_w = scaled_geometry.x_offset * (dx - 1) + scaled_geometry.width
  local content_h =  scaled_geometry.height * dy + scaled_geometry.y_offset

  -- print(string.format("map size for (%d, %d, %d, %d) -> (%d, %d)", x_min, y_min, x_max, y_max, content_w, content_h))
  return content_w, content_h
end

function StrategicalMapWindow:_draw_map_texture(x_min, y_min, x_max, y_max, dx, dy)
  local engine = self.engine
  local theme = engine.gear:get("theme")
  local gui = self.drawing.gui
  local scaled_geometry = gui.scaled_geometry
  local sdl_renderer = engine.gear:get("renderer").sdl_renderer
  local map = engine.gear:get("map")
  local terrain = engine.gear:get("terrain")

  -- print(string.format("generating map frame [%d:%d %d:%d]", x_min, y_min, x_max, y_max))

  local content_w, content_h =  self:_map_size(x_min, y_min, x_max, y_max)

  local format = theme.window.background.texture:query()
  local fog = terrain:get_icon('fog')

  -- shifted description contains the right coordinates (destination boxes)
  local shift_tile = map.tiles[x_min][y_min]
  local first_tile = map.tiles[1][1]
  local shift_x = gui.tile_positions[first_tile.id].dst.x - gui.tile_positions[shift_tile.id].dst.x - scaled_geometry.x_offset
  local shift_y = gui.tile_positions[first_tile.id].dst.y - gui.tile_positions[shift_tile.id].dst.y - scaled_geometry.height

  for i = x_min, x_max do
    -- for j = y_min, (i % 2 == 0) and y_max - 2 or y_max do
    for j = y_min, y_max do
      local tile = map.tiles[i][j]

      -- terrain
      local description = gui.tile_positions[tile.id]

      local h_multiplier = ((j == y_max) and (i%2 == 0)) and 0.5 or 1
      local w_multiplier = (i == x_max) and (scaled_geometry.x_offset/scaled_geometry.width) or 1

      local dst = {
        x = description.dst.x + shift_x + dx,
        y = description.dst.y + shift_y + dy,
        w = math.modf(description.dst.w * w_multiplier),
        h = math.modf(description.dst.h * h_multiplier),
      }
      local src = ((h_multiplier ~= 1) or (w_multiplier ~= 1 )) and {
            x = 0,
            y = 0,
            w = math.modf(description.image.w * w_multiplier),
            h = math.modf(description.image.h * h_multiplier),
          }
        or nil

      assert(sdl_renderer:copy(description.image.texture, src, dst))

      local spotting = map.united_spotting.map[tile.id]
      if (not spotting) then
        -- fog of war
        assert(sdl_renderer:copy(fog.texture, src, dst))
      elseif (description.flag_data) then
        -- unit flag, scaled up to hex
        local dst = {
          x = description.flag_data.dst.x + shift_x + dx,
          y = description.flag_data.dst.y + shift_y + dy,
          w = description.flag_data.dst.w * w_multiplier,
          h = description.flag_data.dst.h * h_multiplier,
        }
        local image = description.flag_data.image
        local src = ((h_multiplier ~= 1) or (w_multiplier ~= 1 )) and {
            x = 0,
            y = 0,
            w = math.modf(image.w * w_multiplier),
            h = math.modf(image.h * h_multiplier),
          }
        or nil
        assert(sdl_renderer:copy(image.texture, src, dst))
      end
    end
  end

  return map_texture
end

function StrategicalMapWindow:_update_frame(hx, hy)
  local frame = self.frame
  local gui = self.drawing.gui
  local scaled_geometry = gui.scaled_geometry
  local renderer = self.engine.gear:get("renderer")
  local map = self.engine.gear:get("map")

  frame.prev_box = _.clone(frame.hex_box)

  local window_w, window_h = renderer:get_size()

  local content_w, content_h = gui.content_size.w, gui.content_size.h
  local frame_w, frame_h = math.min(window_w, content_w), math.min(window_h, content_h)

  local w = math.floor( (frame_w - scaled_geometry.width) / scaled_geometry.x_offset ) - 1
  local h = math.floor( (frame_h - (scaled_geometry.height + scaled_geometry.y_offset)) / gui.scaled_geometry.height) - 1

  hx = (hx + w >= map.width) and math.min(1, map.width - w) or hx
  hy = (hy + h >= map.height) and math.min(1, map.height - h) or hy

  local frame_x_max, frame_y_max = w + hx - 1, h + hy - 1

  -- print(string.format("frame h, w = %d:%d", w, h))
  local map_w, map_h = self:_map_size(hx, hy, frame_x_max, frame_y_max)
  local frame_dx = math.modf((window_w - map_w)/2)
  local frame_dy = math.modf((window_h - map_h)/2)


  -- print(string.format("map_w, map_h = %d:%d, window_w, window_h = %d:%d", map_w, map_h, window_w, window_h))
  -- print(string.format("frame_dx, frame_dy = %d:%d", frame_dx, frame_dy))

  -- x, y are uodated on scroll
  frame.hex_box.x = hx
  frame.hex_box.y = hy
  frame.hex_box.w = w
  frame.hex_box.h = h

  frame.dst.x = frame_dx
  frame.dst.y = frame_dy
  frame.dst.w = map_w
  frame.dst.h = map_h

  frame.screen.w = window_w
  frame.screen.h = window_h
  -- print("frame = " .. inspect(frame))
  -- print("updated frame. old " .. inspect(frame.prev_box) .. ", new : " .. inspect(frame.hex_box))
end

-- if frame didn't updated, returns the current texture
-- otherwise, it generates a new sub-texture(s) and merges it
-- with the previous
function StrategicalMapWindow:_get_texture()
  local engine = self.engine
  local theme = engine.gear:get("theme")
  local sdl_renderer = engine.gear:get("renderer").sdl_renderer
  local frame = self.frame
  local hex_box = frame.hex_box
  local prev_box = frame.prev_box
  local x2, y2 = hex_box.x + hex_box.w - 1, hex_box.y + hex_box.h - 1


  local dx = hex_box.x - prev_box.x
  local dy = hex_box.y - prev_box.y
  local dw = hex_box.w - prev_box.w
  local dh = hex_box.h - prev_box.h


  if ((dx == 0) and (dy == 0) and (dw == 0) and (dh == 0)) then
    -- do nothing,
  else

    -- squares
    local s1, s2 = hex_box.w * hex_box.h, prev_box.w * prev_box.h

    -- if they are NOT equals by squares, we assume that window geometry
    -- has changed, hence, do complete redraw
    if ((s1 ~= s2) or ((dx ~= 0) and (dy ~= 0))) then
      local format = theme.window.background.texture:query()
      frame.texture = assert(sdl_renderer:createTexture(format, SDL.textureAccess.Target, frame.dst.w, frame.dst.h))
      assert(sdl_renderer:setTarget(frame.texture))
      self:_draw_map_texture(hex_box.x, hex_box.y, x2, y2, 0, 0)
      assert(sdl_renderer:setTarget(nil))
    else
      -- determine intersection area
      local gui = self.drawing.gui
      local scaled_geometry = gui.scaled_geometry
      local ix1 = math.max(hex_box.x, prev_box.x)
      local iy1 = math.max(hex_box.y, prev_box.y)
      local ix2 = math.min(hex_box.x + hex_box.w, prev_box.x + prev_box.w) - 1
      local iy2 = math.min(hex_box.y + hex_box.h, prev_box.y + prev_box.h) - 1

      local format = frame.texture:query()
      local new_texture = assert(sdl_renderer:createTexture(format, SDL.textureAccess.Target, frame.dst.w, frame.dst.h))
      local iw, ih = ix2 - ix1, iy2 - iy1

      local d_sign = _.map({dx, dy}, function(_, value)
        if (value > 0) then return 1
        elseif (value < 0) then return -1
        else return 0
        end
      end)

      -- we add +1/-1 to enlarge actually cut area
      local delta = _.map({dx, dy}, function(idx, value)
        return math.abs(d_sign[idx]) * (value + d_sign[idx])
      end)

      -- print("delta = " .. inspect(delta))


      -- here we wd do -2, because:
      -- a) previoulsy we've added + 1 to enlarge AREA
      -- b) we need to skip the additionally drown row
      local nx1 = (delta[1] == 0) and hex_box.x or ((delta[1] > 0) and (prev_box.x + prev_box.w - 2) or hex_box.x)
      local ny1 = (delta[2] == 0) and hex_box.y or ((delta[2] > 0) and (prev_box.y + prev_box.h - 2) or hex_box.y)


      local nx2 = (delta[1] == 0) and x2 or (nx1 + math.abs(delta[1]))
      local ny2 = (delta[2] == 0) and y2 or ((ny1 + math.abs(delta[2]) - ((delta[2] > 0) and 1 or 0) ))
      local nw, nh = nx2 - nx1, ny2 - ny1

      --[[
      print(string.format("intersected frame %d:%d %d:%d (h:w = %d:%d)", ix1, iy1, ix2, iy2, ih, iw))
      print(string.format("new frame %d:%d %d:%d (h:w = %d:%d)", nx1, ny1, nx2, ny2, nw, nh))
      ]]

      assert(sdl_renderer:setTarget(new_texture))

      local existing_w = (iw + ((delta[1] >= 0) and 0 or -1)) * scaled_geometry.x_offset
      local existing_h = (ih + ((delta[2] >= 0) and 0 or -1)) * scaled_geometry.height

      -- copy exisitng part of map
      local old_src = {
        x = (delta[1] >= 0) and (d_sign[1] * (delta[1] - 1) * scaled_geometry.x_offset) or (scaled_geometry.x_offset),
        y = (delta[2] >= 0) and (d_sign[2] * (delta[2] - 1) * scaled_geometry.height) or scaled_geometry.height,
        w = existing_w,
        h = existing_h,
      }

      local new_dst = {
        x = (delta[1] > 0) and 0 or ((math.abs(delta[1]) - 0) * scaled_geometry.x_offset),
        y = (delta[2] > 0) and 0 or ((math.abs(delta[2]) - 0) * scaled_geometry.height),
        w = existing_w,
        h = existing_h,
      }
      -- copy old/intersected frame
      assert(sdl_renderer:copy(frame.texture, old_src, new_dst))

      -- visual debug
      -- assert(sdl_renderer:copy(theme.window.background.texture, nil, nil))

      self:_draw_map_texture(nx1, ny1, nx2, ny2,
        (delta[1] > 0) and (new_dst.w - scaled_geometry.x_offset) or 0,
        (delta[2] > 0) and (new_dst.h) or 0
      )

      frame.texture = new_texture
      assert(sdl_renderer:setTarget(nil))
      -- error("z")
    end
  end
  return frame.texture
end

function StrategicalMapWindow:_on_ui_update(show)
  local engine = self.engine
  local context = self.drawing.context
  local handlers_bound = self.handlers_bound

  if (show) then
    local theme = engine.gear:get("theme")
    local sdl_renderer = engine.gear:get("renderer").sdl_renderer
    local gui = self.drawing.gui
    local map = engine.gear:get("map")
    local terrain = engine.gear:get("terrain")
    local scaled_geometry = gui.scaled_geometry
    local frame = self.frame

    local x, y = table.unpack(self.drawing.position)

    -- remove action hints, as we don't need them for strategical map
    engine.reactor:publish('map.active_tile.change', nil)

    local hex_box = frame.hex_box
    local frame_x_max, frame_y_max = hex_box.x + hex_box.w - 1, hex_box.y + hex_box.h - 1


    local map_texture = self:_get_texture()

    -- draw screen texture
    local format = theme.window.background.texture:query()
    local screen_texture = assert(sdl_renderer:createTexture(format, SDL.textureAccess.Target, frame.screen.w, frame.screen.h))
    assert(sdl_renderer:setTarget(screen_texture))
    -- copy background
    assert(sdl_renderer:copy(theme.window.background.texture, nil,
      {x = x, y = y, w = frame.screen.w, h = frame.screen.h}
    ))
    -- copy map texture into the center of the screen
    -- print(string.format("copying map texture [%d x %d] to screen [%d x %d]", map_w, map_h, screen_w, screen_h))

    local content_x, content_y = x + frame.dst.x, y + frame.dst.y
    -- print(string.format("content_x, content_y = %d, %d", content_x, content_y))
    assert(sdl_renderer:copy(map_texture, nil,
      { x = content_x, y = content_y, w = frame.dst.w, h = frame.dst.h }
    ))
    assert(sdl_renderer:setTarget(nil))

    local map_region = Region.create(content_x, content_y, content_x + frame.dst.w, content_y + frame.dst.h)
    -- print(inspect(map_region))

    local screen_dst = {x = x, y = y, w = frame.screen.w, h = frame.screen.h}

    -- actual draw function is rather simple
    self.drawing.fn = function()
      assert(sdl_renderer:copy(screen_texture, nil, screen_dst))
    end

    if (not handlers_bound) then
      self.handlers_bound = true

      local pointer_to_tile = function (event)
        -- pointer_to_tile assumes that (x, y) are related to (0, 0) where map is being drawn
        -- meanwhile, event.x, event.y already include shift-to-center our strategical map,
        -- have to adjust a bit
        local pos_x = event.x - frame.dst.x
        local pos_y = event.y - frame.dst.y
        return map:pointer_to_tile(pos_x, pos_y, gui.scaled_geometry, frame.hex_box.x - 1,  frame.hex_box.y - 1)
      end

      local mouse_move = function(event)
        engine.state:set_mouse_hint('')
        if (map_region:is_over(event.x, event.y)) then
          local tile_coords = pointer_to_tile(event)
          local tile = map.tiles[tile_coords[1]][tile_coords[2]]
          engine.reactor:publish('map.active_tile.change', tile)
          engine.reactor:publish("event.delay", 20)
        end
        return true -- stop further event propagation
      end
      local mouse_click = function(event)
        if (map_region:is_over(event.x, event.y)) then
          local tile_coords = pointer_to_tile(event)
          local center_x, center_y = table.unpack(tile_coords)

          -- click has been performed on some tile, but we update view frame
          local view_frame = engine.state:get_view_frame()
          local half_frame_w = math.modf(view_frame.w / 2)
          local half_frame_h = math.modf(view_frame.h / 2)

          center_x = math.min(map.width - half_frame_w, center_x)
          center_y = math.min(map.height - half_frame_h, center_y)

          local x0 = math.max(center_x - half_frame_w, 1)
          local y0 = math.max(center_y - half_frame_h, 1)
          local new_view_frame = {x = x0, y = y0, w = view_frame.w, h = view_frame.h}
          -- print("new view frame = " .. inspect(new_view_frame))
          engine.state:set_view_frame(new_view_frame)
          engine.reactor:publish("map.update")
        end
        engine.interface:remove_window(self)
         -- stop further event propagation
        return true
      end

      local idle = function(event)
        local x, y = event.x, event.y
        local hx, hy = frame.hex_box.x, frame.hex_box.y
        local refresh = false
        local map_x, map_y = frame.hex_box.x, frame.hex_box.y
        if ((math.abs(map_region.y_min - y) < SCROLL_TOLERANCE) and map_y > SCROLL_DELTA) then
          hy = hy - SCROLL_DELTA
          refresh = true
        elseif ((math.abs(map_region.y_max - y) < SCROLL_TOLERANCE) and ( (map_y + frame.hex_box.h + SCROLL_DELTA) < map.height)) then
          hy = hy + SCROLL_DELTA
          refresh = true
        elseif ((math.abs(map_region.x_min - x) < SCROLL_TOLERANCE) and map_x > SCROLL_DELTA) then
          hx = hx - SCROLL_DELTA
          refresh = true
        elseif ((math.abs(map_region.x_max - x) < SCROLL_TOLERANCE) and ( (map_x + frame.hex_box.w + SCROLL_DELTA) < map.width)) then
          hx = hx + SCROLL_DELTA
          refresh = true
        end

        if (refresh) then
          -- print("frame_pos = " .. inspect(frame_pos))
          self:_update_frame(hx, hy)
          self:_on_ui_update(true)
          -- speed up scrolling on idle
          engine.reactor:publish("event.delay", 20)
        end
        return true
      end

      context.events_source.add_handler('idle', idle)
      context.events_source.add_handler('mouse_move', mouse_move)
      context.events_source.add_handler('mouse_click', mouse_click)

      self.drawing.idle = idle
      self.drawing.mouse_move = mouse_move
      self.drawing.mouse_click = mouse_click
    end
  elseif(handlers_bound) then -- unbind everything
    self.handlers_bound = false
    context.events_source.remove_handler('idle', self.drawing.idle)
    context.events_source.remove_handler('mouse_click', self.drawing.mouse_click)
    context.events_source.remove_handler('mouse_move', self.drawing.mouse_move)
    self.drawing.idle = nil
    self.drawing.mouse_click = nil
    self.drawing.mouse_move = nil
    self.drawing.fn = function() end
  end
end

function StrategicalMapWindow:bind_ctx(context)
  local engine = self.engine

  -- remember ctx first, as it is involved in gui construction
  self.drawing.context = context
  local gui = self:_construct_gui()
  local ui_update_listener = function()
    self:_update_frame(self.frame.hex_box.x, self.frame.hex_box.y)
    return self:_on_ui_update(true)
  end

  self.drawing.ui_update_listener = ui_update_listener
  self.drawing.gui = gui

  engine.reactor:subscribe('ui.update', ui_update_listener)

  return {gui.content_size.w, gui.content_size.h}
end

function StrategicalMapWindow:set_position(x, y)
  -- completely draw over all other objects (map), i.e. ignore this settings
  -- self.drawing.position = {x, y}
end

function StrategicalMapWindow:unbind_ctx(context)
  self:_on_ui_update(false)
  self.engine.reactor:unsubscribe('ui.update', self.drawing.ui_update_listener)
  self.drawing.ui_update_listener = nil
  self.drawing.context = nil
end

function StrategicalMapWindow:draw()
  self.drawing.fn()
end


return StrategicalMapWindow
