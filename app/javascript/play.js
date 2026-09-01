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

// The input is rendered fresh every time `#turn_log` is replaced, and the
// attribute that would normally handle this is deliberately not in the
// broadcast: Turbo focuses `[autofocus]` after a stream render with a plain
// `.focus()`, which scrolls the element into view and undoes everything above.
// So focus is restored here instead, with `preventScroll`, and the player who
// scrolled up to re-read something stays where they are.
function refocus() {
  const input = document.querySelector("#turn_log input[type=text]")
  if (input && document.activeElement !== input) input.focus({ preventScroll: true })
}

window.addEventListener("scroll", () => { stick = atBottom() })

// EVERY BATCH OF PROSE AND THE FINISHED TURN both arrive as Turbo Stream
// actions, so one hook covers the whole turn.
//
// It has to be this hook, and not the event on its own. `turbo:before-stream-render`
// fires, Turbo then awaits a repaint, and only *then* mutates the DOM -- so
// measuring the page from the event (even a frame later) reads the layout from
// before the batch that just arrived, and the follow ends up one batch behind
// and drifts further off the foot with every one. Measured in a browser: 480px
// adrift by the end of a single narration. Wrapping `detail.render` puts this
// after the mutation, with no timing to guess at.
document.addEventListener("turbo:before-stream-render", (event) => {
  const render = event.detail.render

  event.detail.render = async (streamElement) => {
    await render(streamElement)
    follow()
    refocus()
  }
})

// A plain page load, and every Turbo Drive navigation, decides afresh whether
// the player is at the foot of the log -- so arriving at the top of a long
// transcript does not drag them down on the next turn.
document.addEventListener("turbo:load", () => {
  stick = atBottom()
})
