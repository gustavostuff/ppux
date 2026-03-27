local contraJapan = require("db.contra_japan")
local kirbysAdventureUsaRev1 = require("db.kirbys_adventure_usa_rev_1")
local theGuardianLegendUsa = require("db.the_guardian_legend_usa")

local db = {
  ["376836361F404C815D404E1D5903D5D11F4EFF0E"] = contraJapan,
  ["F324E7C8C3AD102ECDCCA011ECC494F6F345D768"] = kirbysAdventureUsaRev1,
  ["D00D73C7764A4C3513892B97AFB939F30E522245"] = theGuardianLegendUsa,
}

return db
