--[[

Copyright (C) 2015,2016 Ivan Baidakou

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

local Widget = require ('polkovodets.gui.Widget')
local Image = require 'polkovodets.utils.Image'
local Region = require 'polkovodets.utils.Region'

local BattleDetailsWindow = {}
BattleDetailsWindow.__index = BattleDetailsWindow
setmetatable(BattleDetailsWindow, Widget)

local FONT_SIZE = 12
local AVAILABLE_COLOR = 0xAAAAAA
local HILIGHT_COLOR = 0xFFFFFF


function BattleDetailsWindow.create(engine, data)
  local o = Widget.create(engine)
  setmetatable(o, BattleDetailsWindow)
  o.drawing.content_fn = nil
  o.content = {}
  o.record = data
  local theme = engine.gear:get("theme")

  o.text = {
    font  = theme:get_font('default', FONT_SIZE),
  }
  o.drawing.position = {0, 0}

  return o
end

function BattleDetailsWindow:_classy_battle_weapons(record)
  local engine = self.engine
  local weapon_instance_for = engine.gear:get("weapon_instaces::map")
  local renderer = engine.gear:get("renderer")

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
      local wi = assert(weapon_instance_for[wi_id])
      local class = assert(wi:get_class())
      local data_key = class.id .. "_" .. side .. "_" .. property
      data[data_key] = (data[data_key] or 0) + quantity
      available_classes[class.id] = true
    end
  end

  local font = self.text.font
  local create_image = function(str, color)
    local surface = font:renderUtf8(tostring(str), "solid", color)
    return Image.create(renderer.sdl_renderer, surface)
  end

  -- print("data = " .. inspect(data))
  local images = {}
  for key, quantity in pairs(data) do
    images[key] = {
      available = create_image(tostring(quantity), AVAILABLE_COLOR),
      hilight   = create_image(tostring(quantity), HILIGHT_COLOR),
    }
  end

  local classifyer = function(class_id, side, property)
    local key = class_id .. "_" .. side .. "_" .. property
    return images[key]
  end
  return classifyer, available_classes
end

function BattleDetailsWindow:_construct_gui(available_classes, record)
  local engine = self.engine
  local weapon_classes = engine.gear:get("weapons/classes")
  local renderer = engine.gear:get("renderer")

  assert (#weapon_classes > 0)
  -- print(inspect(weapon_classes))
  local class_icon = weapon_classes[1]:get_icon('available')

  local create_image = function(surface)
    return Image.create(renderer.sdl_renderer, surface)
  end

  local font = self.text.font
  local was_label = create_image(font:renderUtf8(engine:translate('ui.window.battle_details.header.was'), "solid", HILIGHT_COLOR))
  local casualities_label = create_image(font:renderUtf8(engine:translate('ui.window.battle_details.header.casualities'), "solid", HILIGHT_COLOR))

  local max_unit_height = 0
  local unit_mapper = function(idx, unit_data)
    local u = engine:get_unit(unit_data.unit_id)
    local unit_icon = u.definition:get_icon(unit_data.state)
    if (max_unit_height < unit_icon.h) then max_unit_height = unit_icon.h end
    return {
      name        = u.name,
      unit_id     = unit_id,
      unit_icon   = unit_icon,
      nation_icon = u.definition.nation.unit_flag,
    }
  end
  local i_units = _.map(record.context.i_units, unit_mapper)
  local p_units = _.map(record.context.p_units, unit_mapper)
  local i_units_w = _.reduce(i_units, function(state, v) return state + v.unit_icon.w end, 0)
  local p_units_w = _.reduce(p_units, function(state, v) return state + v.unit_icon.w end, 0)

  local header_dx = 10
  local initial_header_w = _.reduce({class_icon, was_label, casualities_label}, function(state, image)
    return state + image.w
  end,
  0)
  local max_w = math.max(i_units_w, p_units_w)
  if (initial_header_w < max_w) then
    local delta = max_w - initial_header_w
    header_dx = math.modf(delta / 2) + 1
  end

  local dy = 10 + max_unit_height + 10

  -- initiator columns
  local labels = {
    {
      label = was_label,
      dx    = class_icon.w + header_dx,
      dy    = dy,
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
  local line_dy = dy + header_h + 2
  local my_weapon_classes = {}
  _.eachi(weapon_classes, function(k, class)
    if (available_classes[class.id]) then
      table.insert(my_weapon_classes, class)
    end
  end)
  -- local my_weapon_classes = _.select(weapon_classes, function(k, class) return available_classes[class.id] end)

  for idx, class in pairs(my_weapon_classes) do
    local icon = class:get_icon('available')
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

  dy = line_dy

  local content_w = header_w
  local content_h = line_dy

  local dx = 0
  dy = 10
  local unit_gfx_mapper = function(unit_info)
    local data = unit_info
    data.dy = dy
    data.dx = dx
    dx = dx + unit_info.unit_icon.w + 5
    return data
  end
  local units = {}
  _.each(i_units, function(idx, unit_data)
    units[#units + 1] = unit_gfx_mapper(unit_data)
  end)
  dx = separator.dx + separator.w
  _.each(p_units, function(idx, unit_data)
    units[#units + 1] = unit_gfx_mapper(unit_data)
  end)
  -- print("units = " .. inspect(units))

  local gui = {
    units  = units,
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

function BattleDetailsWindow:_on_ui_update(show)
  local engine = self.engine
  engine.state:set_mouse_hint('')

  local record = self.record
  local classifyer, available_classes = self:_classy_battle_weapons(record)
  local gui = self:_construct_gui(available_classes, record)

  local context = self.drawing.context
  local handlers_bound = self.handlers_bound

  if (show) then
    local theme = engine.gear:get("theme")
    local weapon_classes = engine.gear:get("weapons/classes")
    local weapon_instance_for = engine.gear:get("weapon_instaces::map")

    local details_ctx = _.clone(context, true)
    local content_w = gui.content_size.w
    local content_h = gui.content_size.h
    details_ctx.content_size = { w = content_w, h = content_h}

    local x, y = table.unpack(self.drawing.position)
    details_ctx.x = x
    details_ctx.y = y

    local weapon_class_icon = weapon_classes[1]:get_icon('available')

    local content_x, content_y = x + self.contentless_size.dx, y + self.contentless_size.dy

    local max_x, max_y = x + content_w + self.contentless_size.w, y + content_h + self.contentless_size.h
    local window_region = Region.create(x, y, max_x, max_y)

    local l_infos = gui.header.labels

    local line_regions = _.map(gui.lines, function(idx, line)
      local y_min = content_y + line.dy
      local y_max = content_y + line.dy + line.icon.h
      local ix_min, ix_max = content_x + l_infos[1].dx, content_x + l_infos[2].dx + l_infos[2].label.w
      local px_min, px_max = content_x + l_infos[3].dx, content_x + l_infos[4].dx + l_infos[4].label.w
      return {
        whole = Region.create(content_x, y_min, content_x + l_infos[4].dx + l_infos[4].label.w, y_max),
        i     = Region.create(ix_min, y_min, ix_max, y_max),
        p     = Region.create(px_min, y_min, px_max, y_max),
      }
    end)
    local unit_regions = _.map(gui.units, function(idx, unit_data)
      local icon = unit_data.unit_icon
      local x, y = content_x + unit_data.dx, content_y + unit_data.dy
      return Region.create(x, y, x + icon.w, y + icon.h)
    end)

    local line_styles = {}
    local active_class, active_side
    local update_line_styles = function(x, y)
      line_styles = _.map(line_regions, function(idx, line_region)
        local styles = {i = "available", p = "available"}
        if (line_region.whole:is_over(x, y)) then
          if (line_region.i:is_over(x, y)) then
            styles.i = "hilight"
          elseif (line_region.p:is_over(x, y)) then
            styles.p = "hilight"
          end
        end
        return styles
      end)
    end
    local mouse = engine.state:get_mouse()
    update_line_styles(mouse.x, mouse.y)

    local get_line_image = function(idx, side, property)
      local line = gui.lines[idx]
      local images_pair = classifyer(line.class_id, side, property)
      local style = line_styles[idx][side]
      -- do not hilight row, if there are no casualities nor losses
      if (style == 'hilight' ) then
        local opposite_property = (property  == 'casualities') and 'participants' or 'casualities'
        local opposite_pair = classifyer(line.class_id, side, opposite_property)
        if (not(images_pair) and not(opposite_pair)) then
          style = 'available'
        end
      end
      return (images_pair or gui.not_found)[style]
    end

    local sdl_renderer = engine.gear:get("renderer").sdl_renderer
    self.drawing.content_fn = function()
      -- drawing order: background, window decorations, controls

      -- background
      assert(sdl_renderer:copy(theme.window.background.texture, nil,
        {x = content_x, y = content_y, w = content_w, h = content_h}
      ))

      -- participating units
      for idx, unit_data in ipairs(gui.units) do
        local unit_icon = unit_data.unit_icon
        local nation_icon = unit_data.nation_icon
        assert(sdl_renderer:copy(unit_icon.texture, nil,
          {x = content_x + unit_data.dx, y = content_y + unit_data.dy, w = unit_icon.w, h = unit_icon.h}
        ))
        assert(sdl_renderer:copy(nation_icon.texture, nil, {
          x = content_x + unit_data.dx + unit_icon.w - nation_icon.w,
          y = content_y + unit_data.dy + unit_icon.h - nation_icon.h,
          w = nation_icon.w,
          h = nation_icon.h
        }))
      end

      -- weapon classes icons with counts/casualities for initial/passive sides
      for idx, line in ipairs(gui.lines) do
        local icon = line.icon
        assert(sdl_renderer:copy(icon.texture, nil,
          {x = content_x + line.dx, y = content_y + line.dy, w = icon.w, h = icon.h}
        ))
        local i_was = get_line_image(idx, "i", "participants")
        assert(sdl_renderer:copy(i_was.texture, nil,{
          x = math.modf(content_x + line.center.i.was.dx - i_was.w/2),
          y = math.modf(content_y + line.center.i.was.dy - i_was.h/2),
          w = i_was.w,
          h = i_was.h,
        }))
        local i_casualities = get_line_image(idx, "i", "casualities")
        assert(sdl_renderer:copy(i_casualities.texture, nil,{
          x = math.modf(content_x + line.center.i.casualities.dx - i_casualities.w/2),
          y = math.modf(content_y + line.center.i.casualities.dy - i_casualities.h/2),
          w = i_casualities.w,
          h = i_casualities.h,
        }))
        local p_was = get_line_image(idx, "p", "participants")
        assert(sdl_renderer:copy(p_was.texture, nil,{
          x = math.modf(content_x + line.center.p.was.dx - p_was.w/2),
          y = math.modf(content_y + line.center.p.was.dy - p_was.h/2),
          w = p_was.w,
          h = p_was.h,
        }))
        local p_casualities = get_line_image(idx, "p", "casualities")
        assert(sdl_renderer:copy(p_casualities.texture, nil,{
          x = math.modf(content_x + line.center.p.casualities.dx - p_casualities.w/2),
          y = math.modf(content_y + line.center.p.casualities.dy - p_casualities.h/2),
          w = p_casualities.w,
          h = p_casualities.h,
        }))

        Widget.draw(self)
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
    Widget.update_drawer(self, x, y, content_w, content_h)

    if (not handlers_bound) then
      self.handlers_bound = true

      local mouse_click = function(event)
        if (window_region:is_over(event.x, event.y)) then
          local class_idx, side
          for idx, line_style in ipairs(line_styles) do
            local my_side = ((line_style.i == 'hilight') and 'i')
                      or ((line_style.p == 'hilight') and 'p')
            if (my_side) then
              class_idx, side = idx, my_side
              break
            end
          end
          -- clicked on the hilighed class
          if (class_idx) then
            -- print("selected " .. class_idx .. ", side " .. side)
            local class_id = gui.lines[class_idx].class_id

            -- print(inspect(record.results[side]))
            local has_at_least_one_instance = false
            local filter = function(source)
              local result = {}
              for wi_id, quantity in pairs(source) do
                local wi = assert(weapon_instance_for[wi_id])
                if (wi:get_class().id  == class_id) then
                  result[wi_id] = quantity
                  has_at_least_one_instance = true
                end
              end
              return result
            end
            local participants = filter(record.results[side].participants)
            local casualities  = filter(record.results[side].casualities)
            if (has_at_least_one_instance) then
              engine.interface:add_window('weapon_casualities_details_window', {
                participants = participants,
                casualities  = casualities,
                position     = {
                  x = event.x,
                  y = gui.lines[class_idx].dy + gui.lines[class_idx].icon.h + content_y,
                }
              })
            end
          end
        else
          engine.interface:remove_window(self)
        end
        return true -- stop further event propagation
      end

      local mouse_move = function(event)
        engine.state:set_mouse_hint('')
        if (window_region:is_over(event.x, event.y)) then
          update_line_styles(event.x, event.y)
          for idx, unit_region in ipairs(unit_regions) do
            if (unit_region:is_over(event.x, event.y)) then
              engine.state:set_mouse_hint(gui.units[idx].name)
            end
          end
          for idx, line_region in ipairs(line_regions) do
            if (line_region.whole:is_over(event.x, event.y)) then
              local class_id = gui.lines[idx].class_id
              local key = 'db.weapon-class.' .. class_id
              engine.state:set_mouse_hint(engine:translate(key))
            end
          end
        end
        return true -- stop further event propagation
      end

      context.events_source.add_handler('mouse_click', mouse_click)
      context.events_source.add_handler('mouse_move', mouse_move)
      self.content.mouse_click = mouse_click
      self.content.mouse_move = mouse_move
    end
  elseif(handlers_bound) then -- unbind everything
    self.handlers_bound = false
    context.events_source.remove_handler('mouse_click', self.content.mouse_click)
    context.events_source.remove_handler('mouse_move', self.content.mouse_move)
    self.content.mouse_click = nil
    self.content.mouse_move = nil
    self.drawing.content_fn = function() end
  end
end

function BattleDetailsWindow:bind_ctx(context)
  local engine = self.engine

  local record = self.record
  local classifyer, available_classes = self:_classy_battle_weapons(record)
  local gui = self:_construct_gui(available_classes, record)

  local ui_update_listener = function() return self:_on_ui_update(true) end

  self.drawing.context = context
  self.drawing.ui_update_listener = ui_update_listener
  self.drawing.gui = gui

  engine.reactor:subscribe('ui.update', ui_update_listener)

  local w, h = gui.content_size.w + self.contentless_size.w, gui.content_size.h + self.contentless_size.h
  return {w, h}
end

function BattleDetailsWindow:set_position(x, y)
  self.drawing.position = {x, y}
end

function BattleDetailsWindow:unbind_ctx(context)
  self:_on_ui_update(false)
  self.engine.reactor:unsubscribe('ui.update', self.drawing.ui_update_listener)
  self.drawing.ui_update_listener = nil
  self.drawing.context = nil
end

function BattleDetailsWindow:draw()
  self.drawing.content_fn()
end

return BattleDetailsWindow
