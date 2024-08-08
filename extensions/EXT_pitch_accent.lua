local logger = require("logger")
local util = require("util")
local u = require("lua_utils/utils")

local PitchAccent = {
    description = [[
Some definitions contain pitch accent information.
e.g. さけ・ぶ [2]【叫ぶ】
this extension extracts the [2] from the definition's headword and stores it as a html representation and/or a number.
    ]],
    -- These 2 fields should be modified to point to the desired field on the card
    field_pitch_html = 'Graph',
    field_pitch_num = 'Graph',

    -- SVG element templates used to display pitch accent
    mark_accented = "<circle cx=\"%d\" cy=\"25\" r=\"15\" style=\"stroke-width:5;fill:currentColor;stroke:currentColor;\"></circle>",
    mark_downstep = "<circle cx=\"%d\" cy=\"25\" r=\"15\" style=\"fill:none;stroke-width:5;stroke:currentColor;\"></circle><circle cx=\"%d\" cy=\"25\" r=\"5\" style=\"fill:currentColor;\"></circle>",
    unmarked_char = "<circle cx=\"%d\" cy=\"75\" r=\"15\" style=\"stroke-width:5;fill:currentColor;stroke:currentColor;\"></circle>",
    pitch_downstep_pattern = "(%[([0-9])%])",
}

function PitchAccent:convert_pitch_to_HTML(accents)
    local converter = nil
    if #accents == 0 then
        converter = function(_) return nil end
    elseif #accents == 1 then
        converter = function(field) return accents[1][field] end
    else
        converter = function(field) return self:convert_to_HTML {
            entries = accents,
            class = "pitch",
            build = function(accent) return string.format("<li>%s</li>", accent[field]) end
        }
        end
    end
    return converter("pitch_num"), converter("pitch_accent")
end

function PitchAccent:split_morae(word)
    local small_aeio = u.to_set(util.splitToChars("ゅゃぃぇょゃ"))
    local morae = u.defaultdict(function() return {} end)
    for _,ch in ipairs(util.splitToChars(word)) do
        local is_small = small_aeio[ch] or false
        table.insert(morae[is_small and #morae or #morae+1], ch)
    end
    logger.info(("EXT: PitchAccent#split_morae(): split word %s into %d morae: "):format(word, #morae))
    return morae
end

local function get_first_line(linestring)
    local start_idx = linestring:find('\n', 1, true)
    return start_idx and linestring:sub(1, start_idx + 1) or linestring
end

function PitchAccent:get_pitch_downsteps(dict_result)
    return string.gmatch(get_first_line(dict_result.definition), self.pitch_downstep_pattern)
end
function PitchAccent:get_pitch_accents(dict_result)
    local _morae = nil
    local function get_morae()
        if not _morae then
            _morae = self:split_morae(dict_result:get_kana_words()[1])
        end
        return _morae
    end

    local function _convert(downstep)
        local pitch_visual = {}
        local mora_count = #get_morae()
        local svg_width = 100 + (mora_count - 1) * 50
        local last_cx = 25
        local last_cy = 25
        local tri_y = 25
        local path_d = "M"
        local is_heiban = downstep == "0"
        local was_downstep = false
    
        for idx, mora in ipairs(get_morae()) do
            local marking = nil
            local cx = 25 + (idx - 1) * 50  -- Calculate cx based on the index
            local cy

            if is_heiban then
                -- Handle heiban (no downstep)
                marking = idx == 1 and self.unmarked_char:format(cx) or self.mark_accented:format(cx)
                cy = idx == 1 and 75 or 25
            elseif idx == tonumber(downstep) then
                -- Handle downstep case
                marking = self.mark_downstep:format(cx, cx)
                cy = 25
                was_downstep = true
            elseif idx < tonumber(downstep) then
                if idx == 1 then
                    -- Handle non-heiban first mora
                    marking = self.unmarked_char:format(cx)
                    cy = 75
                else
                    -- Handle accents before downstep
                    marking = self.mark_accented:format(cx)
                    cy = 25
                end
            else
                -- Handle unmarked characters
                marking = self.unmarked_char:format(cx)
                cy = 75
            end

            -- Update path data
            if idx == 1 then
                path_d = path_d .. string.format(" %d %d", cx, cy)
            else
                path_d = path_d .. string.format(" L%d %d", cx, cy)
            end

            last_cx = cx  -- Store the cx value for later use
            last_cy = cy  -- Update last_cy

            logger.dbg("EXT: PitchAccent#get_pitch_accent(): determined marking for mora: ", idx, table.concat(mora), marking)
            for _, ch in ipairs(mora) do
                table.insert(pitch_visual, marking)
            end
        end

        -- After processing all moras, if the last mora was a downstep, adjust last_cy
        tri_y = was_downstep and 75 or (is_heiban and 25 or last_cy)

        -- Add the path element
        local path_element = string.format(
            "<path d=\"%s\" style=\"fill:none;stroke-width:5;stroke:currentColor;\"></path><path d=\"M%d %d L%d %d\" style=\"fill:none;stroke-width:5;stroke:currentColor;stroke-dasharray:5 5;\"></path><path d=\"M0 13 L15 -13 L-15 -13 Z\" transform=\"translate(%d,%d)\" style=\"fill:none;stroke-width:5;stroke:currentColor;\"></path>",
            path_d,
            last_cx, last_cy, last_cx + 50, tri_y,
            last_cx + 50, tri_y
        )
        
        table.insert(pitch_visual, path_element)
    
        -- Format the SVG with dynamic width
        local pitch_pattern = string.format(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" focusable=\"false\" viewBox=\"0 0 %d 100\" style=\"display:inline-block;vertical-align:middle;height:1.5em;\">%s</svg>",
            svg_width,
            table.concat(pitch_visual)
        )

        return pitch_pattern
    end

    local downstep_iter = self:get_pitch_downsteps(dict_result)
    return function(iter)
        local with_brackets, downstep = iter()
        if downstep then
            return with_brackets, _convert(downstep)
        end
    end, downstep_iter
end

function PitchAccent:run(note)
    if not self.popup_dict.is_extended then
        self.popup_dict.results = require("langsupport/ja/dictwrapper").extend_dictionaries(self.popup_dict.results, self.conf)
        self.popup_dict.is_extended = true
    end
    local selected = self.popup_dict.results[self.popup_dict.dict_index]

    local pitch_accents = {}
    for _, result in ipairs(self.popup_dict.results) do
        if selected:get_kana_words():contains_any(result:get_kana_words()) then
            for num, accent in self:get_pitch_accents(result) do
                if not pitch_accents[num] then
                    pitch_accents[num] = true -- add as k/v pair too so we can detect uniqueness
                    table.insert(pitch_accents, { pitch_num = num, pitch_accent = accent })
                end
            end
        end
    end
    local pitch_num, pitch_accent = self:convert_pitch_to_HTML(pitch_accents)
    note.fields[self.field_pitch_num] = pitch_num
    note.fields[self.field_pitch_html] = pitch_accent
    return note
end

return PitchAccent
