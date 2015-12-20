--[[

Copyright (C) 2015 Ivan Baidakou

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

local inspect = require('inspect')
local _ = require ("moses")

local Button = require ('polkovodets.gui.Button')
local HorizontalPanel = require ('polkovodets.gui.HorizontalPanel')
local Image = require 'polkovodets.utils.Image'

local BattleDetailsWindow = {}
BattleDetailsWindow.__index = BattleDetailsWindow
setmetatable(BattleDetailsWindow, HorizontalPanel)

function BattleDetailsWindow.create(engine)
  local o = HorizontalPanel.create(engine)
  setmetatable(o, BattleDetailsWindow)
  o.ctx_bound = false
  o.drawing.content_fn = nil
  o.content = {}

  o.text = {
    size  = 12,
    font  = engine.renderer.theme:get_font('default', 12),
  }

  return o
end

function BattleDetailsWindow:_classy_battle_weapons(record)
  local engine = self.engine

  local sources = {
    {"i", "participants"},
    {"i", "casualities"},
    {"p", "participants"},
    {"p", "casualities"},
  }
  local data = {}
  local available_classes = {}
  for idx, source in pairs(sources) do
    local side, property = source[1], source [2]
    local property_data = record.results[side][property]
    for wi_id, quantity in pairs(property_data) do
      local wi = assert(engine.weapon_instance_for[wi_id])
      local class = assert(wi:get_class())
      local data_key = class.id .. "_" .. side .. "_" .. property
      data[data_key] = (data[data_key] or 0) + quantity
      available_classes[class.id] = true
    end
  end

  -- print("data = " .. inspect(data))
  local images = {}
  local font = self.text.font
  for key, quantity in pairs(data) do
    local surface = font:renderUtf8(tostring(quantity), "solid", 0xFFFFFF)
    images[key] = Image.create(engine.renderer.sdl_renderer, surface)
  end

  local classifyer = function(class_id, side, property)
    local key = class_id .. "_" .. side .. "_" .. property
    return images[key]
  end
  return classifyer, available_classes
end

function BattleDetailsWindow:_construct_gui(available_classes)
  local engine = self.engine
  local weapon_classes = engine.unit_lib.weapons.classes.list

  assert (#weapon_classes > 0)
  -- print(inspect(weapon_classes))
  local class_icon = weapon_classes[1]:get_icon()

  local create_image = function(surface)
    return Image.create(engine.renderer.sdl_renderer, surface)
  end

  local font = self.text.font
  local was_label = create_image(font:renderUtf8(engine:translate('ui.window.battle_details.header.was'), "solid", 0xFFFFFF))
  local casualities_label = create_image(font:renderUtf8(engine:translate('ui.window.battle_details.header.casualities'), "solid", 0xFFFFFF))

  -- initiator columns
  local header_dx = 10
  local labels = {
    {
      label = was_label,
      dx    = class_icon.w + header_dx,
      dy    = 0,
    },
  }
  table.insert(labels, {
    label = casualities_label,
    dx    = labels[#labels].dx + header_dx + labels[#labels].label.w,
    dy    = labels[#labels].dy,
  })
  -- print(inspect(labels))

  -- separator
  local separator = {
    dx    = labels[#labels].dx + header_dx + labels[#labels].label.w + 5,
    dy    = labels[#labels].dy + labels[#labels].label.h + 1,
    w     = 1,
    h     = 0, -- to be defined later
    color = 0xFFFFFF,
  }

  -- passive columns
  table.insert(labels, {
    label = was_label,
    dx    = separator.dx + separator.w + 5 + header_dx,
    dy    = labels[#labels].dy,
  })
  table.insert(labels, {
    label = casualities_label,
    dx    = labels[#labels].dx + header_dx + labels[#labels].label.w,
    dy    = labels[#labels].dy,
  })

  local header_w = labels[#labels].dx + header_dx + labels[#labels].label.w + header_dx
  local header_h = labels[1].label.h + 2

  local header = {
    w         = header_w,
    h         = header_h,
    labels    = labels,
    separator = separator,
  }

  local lines = {}
  local line_dy = header_h + 2
  local my_weapon_classes = {}
  _.eachi(weapon_classes, function(k, class)
    if (available_classes[class.id]) then
      table.insert(my_weapon_classes, class)
    end
  end)
  -- local my_weapon_classes = _.select(weapon_classes, function(k, class) return available_classes[class.id] end)

  for idx, class in pairs(my_weapon_classes) do
    local icon = class:get_icon()
    local center_y = math.modf(line_dy + icon.h/2)
    local line = {
      class_id = class.id,
      icon     = icon,
      dx       = 0,
      dy       = line_dy,
      center   = {
        i = {
          was = {
            dx = math.modf(labels[1].dx + labels[1].label.w/2),
            dy = center_y,
          },
          casualities = {
            dx = math.modf(labels[2].dx + labels[2].label.w/2),
            dy = center_y,
          },
        },
        p = {
          was = {
            dx = math.modf(labels[3].dx + labels[3].label.w/2),
            dy = center_y,
          },
          casualities = {
            dx = math.modf(labels[4].dx + labels[4].label.w/2),
            dy = center_y,
          },
        },
      },
    }
    table.insert(lines, line)
    line_dy = line_dy + 2 + icon.h
  end
  separator.h = line_dy - lines[1].dy
  -- print("lines = " .. inspect(lines))

  local content_w = header_w
  local content_h = line_dy

  local gui = {
    header = header,
    lines  = lines,
    not_found = {
      available = create_image(font:renderUtf8('-', "solid", 0xAAAAAA)),
      hilight   = create_image(font:renderUtf8('-', "solid", 0xFFFFFF)),
    },
    content_size ={
      w = content_w,
      h = content_h,
    }
  }

  -- print(string.format("content size %d x %d", content_w, content_h))
  return gui
end

function BattleDetailsWindow:bind_ctx(context)
  local engine = self.engine
  if (engine.state.popups.battle_details_window) then
    self.ctx_bound = true
    local record = assert(context.state.history_record)
    local classifyer, available_classes = self:_classy_battle_weapons(record)
    local gui = self:_construct_gui(available_classes)

    local theme = assert(context.renderer.theme)
    local details_ctx = _.clone(context, true)
    local content_w = gui.content_size.w
    local content_h = gui.content_size.h
    details_ctx.content_size = { w = content_w, h = content_h}

    local window = assert(context.window)
    local x = math.modf(window.w/2 - content_w/2)
    local y = math.modf(window.h/2 - content_h/2)
    details_ctx.x = x
    details_ctx.y = y

    local weapon_classes = engine.unit_lib.weapons.classes.list
    local weapon_class_icon = weapon_classes[1]:get_icon()

    local content_x, content_y = x + self.contentless_size.dx, y + self.contentless_size.dy

    local max_x = x + content_w + self.contentless_size.w
    local max_y = y + content_h + self.contentless_size.h
    local is_over_window = function(mx, my)
      local over = ((mx >= x) and (mx <= max_x)
                and (my >= y) and (my <= max_y))
      return over
    end


    local sdl_renderer = assert(context.renderer.sdl_renderer)
    self.drawing.content_fn = function()

      -- background
      assert(sdl_renderer:copy(theme.window.background.texture, nil,
        {x = content_x, y = content_y, w = content_w, h = content_h}
      ))

      -- unit classes icons with counts/casualities for initial/passive sides
      for ignored, line in ipairs(gui.lines) do
        local icon = line.icon
        assert(sdl_renderer:copy(icon.texture, nil,
          {x = content_x + line.dx, y = content_y + line.dy, w = icon.w, h = icon.h}
        ))
        local i_was = classifyer(line.class_id, "i", "participants") or gui.not_found.available
        assert(sdl_renderer:copy(i_was.texture, nil,{
          x = math.modf(content_x + line.center.i.was.dx - i_was.w/2),
          y = math.modf(content_y + line.center.i.was.dy - i_was.h/2),
          w = i_was.w,
          h = i_was.h,
        }))
        local i_casualities = classifyer(line.class_id, "i", "casualities") or gui.not_found.available
        assert(sdl_renderer:copy(i_casualities.texture, nil,{
          x = math.modf(content_x + line.center.i.casualities.dx - i_casualities.w/2),
          y = math.modf(content_y + line.center.i.casualities.dy - i_casualities.h/2),
          w = i_casualities.w,
          h = i_casualities.h,
        }))
        local p_was = classifyer(line.class_id, "p", "participants") or gui.not_found.available
        assert(sdl_renderer:copy(p_was.texture, nil,{
          x = math.modf(content_x + line.center.p.was.dx - p_was.w/2),
          y = math.modf(content_y + line.center.p.was.dy - p_was.h/2),
          w = p_was.w,
          h = p_was.h,
        }))
        local p_casualities = classifyer(line.class_id, "p", "casualities") or gui.not_found.available
        assert(sdl_renderer:copy(p_casualities.texture, nil,{
          x = math.modf(content_x + line.center.p.casualities.dx - p_casualities.w/2),
          y = math.modf(content_y + line.center.p.casualities.dy - p_casualities.h/2),
          w = p_casualities.w,
          h = p_casualities.h,
        }))
      end

      -- table header
      for idx, label_info in ipairs(gui.header.labels) do
        local label = label_info.label
        assert(sdl_renderer:copy(label.texture, nil,
          {x = content_x + label_info.dx, y = content_y + label_info.dy, w = label.w, h = label.h}
        ))
      end

      -- initiator/passive separator
      local prev_color = sdl_renderer:getDrawColor()
      assert(sdl_renderer:setDrawColor(gui.header.separator.color))
      assert(sdl_renderer:drawLine({
        x1 = content_x + gui.header.separator.dx,
        y1 = content_y + gui.header.separator.dy,
        x2 = content_x + gui.header.separator.dx,
        y2 = content_y + gui.header.separator.dy + gui.header.separator.h,
      }))
      assert(sdl_renderer:setDrawColor(prev_color))
    end

    _.each(self.drawing.objects, function(k, v) v:bind_ctx(details_ctx) end)

    local mouse_click = function(event)
      if (is_over_window(event.x, event.y)) then
        -- print("ignore")
        -- click hasn't been processed by button, just ignore it
      else
        engine.state.popups.battle_details_window = false
        engine.mediator:publish({ "view.update" })
      end
      return true -- stop further event propagation
    end

    context.state.action = 'default'
    local mouse_move = function(event)
      return true -- stop further event propagation
    end

    context.events_source.add_handler('mouse_click', mouse_click)
    self.content.mouse_click = mouse_click
    context.events_source.add_handler('mouse_move', mouse_move)
    self.content.mouse_move = mouse_move

    HorizontalPanel.bind_ctx(self, details_ctx)
  end
end

function BattleDetailsWindow:unbind_ctx(context)
  if (self.ctx_bound and self.engine.state.popups.battle_details_window) then
    self.ctx_bound = false
    self.drawing.content_fn = nil
    _.each(self.drawing.objects, function(k, v) v:unbind_ctx(context) end)
    context.events_source.remove_handler('mouse_click', self.content.mouse_click)
    context.events_source.remove_handler('mouse_move', self.content.mouse_move)
    self.content.mouse_click = nil
    self.content.mouse_move = nil
    HorizontalPanel.unbind_ctx(self, context)
  end
end

function BattleDetailsWindow:draw()
  if (self.engine.state.popups.battle_details_window) then
    -- drawing order: background, window decorations, controls
    self.drawing.content_fn()
    HorizontalPanel.draw(self)
    _.each(self.drawing.objects, function(k, v) v:draw() end)
  end
end

return BattleDetailsWindow