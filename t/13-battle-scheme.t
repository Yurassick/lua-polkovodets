#!/usr/bin/env lua

package.path = "?.lua;" .. "src/lua/?.lua;" .. package.path

local t = require 'Test.More'

local inspect = require('inspect')
local DummyRenderer = require 't.DummyRenderer'

local Gear = require "gear"

local Engine = require 'polkovodets.Engine'
local BattleFormula = require 'polkovodets.BattleFormula'
local BattleScheme = require 'polkovodets.BattleScheme'

local gear = Gear.create()
gear:declare("renderer", { constructor = function() return DummyRenderer.create(640, 480) end})
local engine = Engine.create(gear, "en")

local bs = BattleScheme.create()

subtest("parse condition", function()

  subtest("always true condition", function()
    local r = bs:_parse_condition('I.orientation == I.orientation')
    print(inspect(r))
    ok(r)
    is(r.kind, 'Relation')
  end)

  subtest("orientation eq", function()
    local r = bs:_parse_condition('I.orientation == P.orientation')
    print(inspect(r))
    ok(r)
    is(r.kind, 'Relation')
    is(r.v1.object, 'I')
    is(r.v1.property, 'orientation')
  end)

  subtest("check state", function()
    local r = bs:_parse_condition('I.state == "A"')
    print(inspect(r))
    ok(r)
    is(r.kind, 'Relation')
    is(r.v1.object, 'I')
    is(r.v1.property, 'state')
    is(r.v2.kind, 'Literal')
    is(r.v2.value, 'A')
  end)

  subtest("check type", function()
    local r = bs:_parse_condition('I.type == "ut_land"')
    print(inspect(r))
    ok(r)
    is(r.kind, 'Relation')
    is(r.v1.object, 'I')
    is(r.v1.property, 'type')
    is(r.v2.kind, 'Literal')
    is(r.v2.value, 'ut_land')
  end)


  subtest("parenthesis", function()
    local r = bs:_parse_condition('((I.state == "A"))')
    print(inspect(r))
    ok(r)
    is(r.kind, 'Relation')
    is(r.v1.object, 'I')
    is(r.v1.property, 'state')
    is(r.v2.kind, 'Literal')
    is(r.v2.value, 'A')
  end)

  subtest("binary mixture of && and ||", function()
    local r = bs:_parse_condition('((P.state == "A") || (P.state == "D")) && (I.orientation == P.orientation)')
    print("r == " .. inspect(r))
    ok(r)
    is(r.kind, 'LogicalOperation')
    is(r.operator, '&&')
    is(r.relations[1].operator, '||')
    is(r.relations[1].relations[1].operator, '==')
    is(r.relations[1].relations[1].v1.object, 'P')
    is(r.relations[1].relations[1].v2.value, 'A')
  end)

  subtest("tripple and", function()
    local r = bs:_parse_condition('(I.state == "A") && (P.state == "D") && (I.orientation != P.orientation)')
    print("r == " .. inspect(r))
    ok(r)
    is(r.kind, 'LogicalOperation')
    is(r.operator, '&&')
    is(r.relations[3].operator, '!=')
    is(r.relations[3].v1.object, 'I')
    is(r.relations[3].v2.object, 'P')
  end)

  subtest("tripple and with additional parenthesis", function()
    local r = bs:_parse_condition('(I.state == "A") && ((P.state == "D")) && (I.orientation != P.orientation)')
    print("r == " .. inspect(r))
    ok(r)
    is(r.kind, 'LogicalOperation')
    is(r.operator, '&&')
    is(r.relations[3].operator, '!=')
    is(r.relations[3].v1.object, 'I')
    is(r.relations[3].v2.object, 'P')
  end)

  subtest("ternary mixture of && and ||", function()
    local r = bs:_parse_condition('(I.state == "A") && ((P.state == "A") || (P.state == "D")) && (I.orientation == P.orientation)')
    print("r == " .. inspect(r))
    ok(r)
    is(r.kind, 'LogicalOperation')
    is(r.operator, '&&')

    is(r.relations[2].operator, '||')
    is(r.relations[2].relations[1].operator, '==')
    is(r.relations[2].relations[1].v1.object, 'P')
    is(r.relations[2].relations[1].v2.value, 'A')

    is(r.relations[3].operator, '==')
    is(r.relations[3].v1.object, 'I')
    is(r.relations[3].v2.object, 'P')
  end)

  subtest("non-valid cases", function()
    nok(bs:_parse_condition('I.state == A"'))
    nok(bs:_parse_condition("I.state == 'A'"))
    nok(bs:_parse_condition('I.state() == "A"'))
  end)
end)

subtest("match/not-match", function()
    local r = bs:_parse_condition('(I.type == "ut_land") && (P.type == "ut_land") && (I.state == "defending") && (P.state == "attacking") && (I.orientation != P.orientation)')
    print(inspect(r))
    subtest("not-match", function()
        local i_unit = { data = { state = "defending", orientation = "left"}, definition = { unit_type = { id = "ut_land"} }}
        local p_unit = { data = { state = "defending", orientation = "right"}, definition = { unit_type = { id = "ut_land"} }}
        local result = r:matches(i_unit, p_unit)
        is(result, false)
    end)

    subtest("match", function()
        local i_unit = { data = { state = "defending", orientation = "left"},  definition = { unit_type = { id = "ut_land"} }}
        local p_unit = { data = { state = "attacking", orientation = "right"}, definition = { unit_type = { id = "ut_land"} }}
        local result = r:matches(i_unit, p_unit)
        is(result, true)
    end)
end)

subtest("parse selection", function()
  subtest("simple selector", function()
    ok(bs:_parse_selection('I.category("wc_artil")'))
    ok(bs:_parse_selection('!I.category("wc_tank")'))
    ok(bs:_parse_selection('P.category("wc_hweap") && P.category("wc_antitank")'))
    ok(bs:_parse_selection('P.category("wc_hweap") || P.category("wc_antitank")'))
    ok(bs:_parse_selection('I.category("wc_infant") || I.category("wc_hweap") || I.category("wc_antitank")'))
    ok(bs:_parse_selection('P.category("wc_infant") && !P.category("wc_tank")'))
  end)
end)


subtest("blocks", function()
  local condition = bs:_parse_condition("I.orientation == P.orientation")
  ok(condition)
  local b_parent = bs:_create_block('1', 'battle', condition)
  ok(b_parent)
  b_parent:validate()
  local b_child = bs:_create_block('1.1', nil,
    bs:_parse_condition('(I.type == "ut_land") && (P.type == "ut_land")'),
    bs:_parse_condition('I.category("wc_artil")'), 1,
    bs:_parse_condition('P.category("wc_hweap") || P.category("wc_antitank")'), 1,
    'fire'
  )
  ok(b_child)
  b_child:validate()
end)

subtest("initialization", function()
  gear:set("data/battle_blocks", {
    { block_id = "1", fire_type = "battle", condition = '(I.state == "attacking") && (P.state == "defending")'},
    { block_id = "1.1", active_weapon = 'I.category("wc_infant")', active_multiplier = "1", passive_weapon = 'P.target("any")', passive_multiplier = "1", action = "battle" },
  })

  local bs2 = gear:get("battle_scheme")
  ok(bs2)
end)

done_testing()
