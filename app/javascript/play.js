// WHERE THE VIEWPORT SITS WHILE A TURN ARRIVES.
//
// Ported from the `EventSource` handler this replaced, and it matters more with
// Turbo, not less: there is no end-of-turn reload left to land the player at
// `#bottom`, so following the narration down is now the only thing that keeps
// the prose on screen as it is written.
//
// Plain ES modules over importmap. No Stimulus: there is no element with state
// or a lifecycle here, only two document-level listeners, and a controller
// would be a class and a data attribute wrapped around them for nothing.

// Follow the narration down, but only while the player is already reading the
// bottom. `stick` goes false the moment they scroll away to re-read something,
// and true again when they come back -- our own scrollTo fires this listener too,
// and lands at the bottom, so it re-arms itself.
let stick = true

function atBottom() {
  const d = document.documentElement
  return window.innerHeight + window.scrollY >= d.scrollHeight - 40
}

function follow() {
  if (stick) window.scrollTo(0, document.documentElement.scrollHeight)
}

// The input is rendered fresh every time `#turn_log` is replaced, and `autofocus`
// only fires on a page load -- so without this the player has to click the box
// again after every turn, where the old reload gave them the focus back for free.
//
// `preventScroll` because focusing an element the player has scrolled away from
// would drag them to it, which is precisely what `stick` exists to stop.
function refocus() {
  const input = document.querySelector("#turn_log input[type=text]")
  if (input && document.activeElement !== input) input.focus({ preventScroll: true })
}

window.addEventListener("scroll", () => { stick = atBottom() })

// Every batch of prose and the finished turn both arrive as Turbo Stream
// actions, so one listener covers the whole turn. The render itself happens
// after this event, hence the frame's delay before measuring the page.
document.addEventListener("turbo:before-stream-render", () => {
  requestAnimationFrame(() => {
    follow()
    refocus()
  })
})

// A plain page load, and every Turbo Drive navigation, arms the follow again:
// the play page is entered at `#bottom`, which is where the story is.
document.addEventListener("turbo:load", () => {
  stick = atBottom()
})
