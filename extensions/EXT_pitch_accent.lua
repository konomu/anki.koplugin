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
        local last_cx = 25  -- Initialize cx for the first mora
        local last_cy = 25  -- Initialize last_cy to a default value
        local tri_y = 25
        local path_d = "M"  -- Start the path data with a move command
        local is_heiban = downstep == "0"
        local was_downstep = false  -- Flag to track if the last mora was a downstep
    
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
                path_d = path_d .. string.format(" %d %d", cx, cy)  -- Move command for the first point
            else
                path_d = path_d .. string.format(" L%d %d", cx, cy)  -- Line command for subsequent points
            end

            last_cx = cx  -- Store the cx value for later use
            last_cy = cy  -- Update last_cy

            logger.dbg("EXT: PitchAccent#get_pitch_accent(): determined marking for mora: ", idx, table.concat(mora), marking)
            for _, ch in ipairs(mora) do
                table.insert(pitch_visual, marking)
            end
        end

        -- After processing all moras, set tri_y based on last_mora conditions
        tri_y = was_downstep and 75 or (is_heiban and 25 or last_cy)

        -- Add the path element
        local path_element = string.format(
            "<path d=\"%s\" style=\"fill:none;stroke-width:5;stroke:currentColor;\"></path><path d=\"M%d %d L%d %d\" style=\"fill:none;stroke-width:5;stroke:currentColor;stroke-dasharray:5 5;\"></path><path d=\"M0 13 L15 -13 L-15 -13 Z\" transform=\"translate(%d,%d)\" style=\"fill:none;stroke-width:5;stroke:currentColor;\"></path>",
            path_d,
            last_cx, last_cy, last_cx + 50, tri_y,
            last_cx + 50, tri_y  -- Keep the previous transform values; adjust if needed
        )
        
        table.insert(pitch_visual, path_element)
    
        return self.pitch_pattern:format(table.concat(pitch_visual))
    end

    local downstep_iter = self:get_pitch_downsteps(dict_result)
    return function(iter)
        local with_brackets, downstep = iter()
        if downstep then
            return with_brackets, _convert(downstep)
        end
    end, downstep_iter
end
