.pragma library

// Nerd Font glyphs, by code point so they survive any editor or copy-paste.
var scene = String.fromCodePoint(0xF0FCE)     // clapperboard
var save = String.fromCodePoint(0xF0193)      // floppy
var history = String.fromCodePoint(0xF02DA)   // clock with arrow
var restore = String.fromCodePoint(0xF099B)
var rename = String.fromCodePoint(0xF03EB)    // pencil
var trash = String.fromCodePoint(0xF0A7A)
var terminal = String.fromCodePoint(0xF018D)
var web = String.fromCodePoint(0xF059F)
var app = String.fromCodePoint(0xF08C6)
var monitor = String.fromCodePoint(0xF0379)
var sync = String.fromCodePoint(0xF04E6)
var search = String.fromCodePoint(0xF0349)

function forKind(kind) {
  if (kind === "terminal") return terminal
  if (kind === "webapp" || kind === "pwa" || kind === "browser") return web
  return app
}
