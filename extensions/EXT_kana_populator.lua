local KanaFieldPopulator = {
    kana_field = "Reading"
}

function KanaFieldPopulator:run(note)
    if not self.popup_dict.is_extended then
        self.popup_dict.results = require("langsupport/ja/dictwrapper").extend_dictionaries(self.popup_dict.results, self.conf)
        self.popup_dict.is_extended = true
    end

    local selected_dict = self.popup_dict.results[self.popup_dict.dict_index]
    local kana = selected_dict:get_kana_words():get()
    note.fields[self.kana_field] = table.concat(kana, ", ")
    return note
end

return KanaFieldPopulator
