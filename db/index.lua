local contraJapan = require("db.contra_japan")
local kirbysAdventureUsaRev1 = require("db.kirbys_adventure_usa_rev_1")
local theGuardianLegendUsa = require("db.the_guardian_legend_usa")
local zeldaIITheAdventureOfLinkUsa = require("db.zelda_ii_the_adventure_of_link_usa")
local superMarioBrosUsa = require("db.super_mario_bros_usa")

local db = {
  ["376836361F404C815D404E1D5903D5D11F4EFF0E"] = contraJapan,
  ["F324E7C8C3AD102ECDCCA011ECC494F6F345D768"] = kirbysAdventureUsaRev1,
  ["D00D73C7764A4C3513892B97AFB939F30E522245"] = theGuardianLegendUsa,
  ["353489A57F24A429572E76BD455BC51D821F7036"] = zeldaIITheAdventureOfLinkUsa,
  ["EA343F4E445A9050D4B4FBAC2C77D0693B1D0922"] = superMarioBrosUsa,
}

return db
