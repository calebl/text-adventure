import { Controller } from "@hotwired/stimulus"

// WHERE THE VIEWPORT SITS WHILE A TURN ARRIVES, and where the cursor is when it
// lands.
//
// Ported from the `EventSource` handler the Turbo swap replaced, and it matters
// more with Turbo, not less: there is no end-of-turn reload left to drop the
// player at `#bottom`, so following the narration down is the only thing keeping
// the prose on screen as it is written.
//
// The scope is the wrapper on `playthroughs/show`, NOT `#turn_log` -- see the
// comment there. Three of the four things below were found in a browser rather
// than in the suite, and each one is a comment because losing it is silent.
export default class extends Controller {
  static targets = [ "command" ]

  // ARMED FROM BOTH ENDS, and it has to be both -- measured, not assumed:
  //
  //   * on a full page load `turbo:load` fires BEFORE Stimulus has attached the
  //     listener, so it never arrives here and `connect()` is the only hook that
  //     runs. By then the position has settled (measured y=852, atBottom true).
  //   * on a Turbo Drive visit -- the index's Resume link -- `connect()` runs
  //     BEFORE Turbo applies the scroll, so it reads y=0 and would decide the
  //     player is not at the foot of a log they are about to be dropped at the
  //     foot of. `turbo:load` fires 5ms later with the real position.
  //
  // So `connect()` covers the load, `turbo:load` corrects the navigation, and
  // dropping either one gets a case wrong.
  connect() {
    this.notePosition()
  }

  // Follow the narration down, but only while the player is already reading the
  // bottom. This goes false the moment they scroll away to re-read something,
  // and true again when they come back -- our own scrollTo fires the `scroll`
  // action too, and lands at the bottom, so the follow re-arms itself.
  notePosition() {
    this.stick = this.atBottom
  }

  // EVERY BATCH OF PROSE AND THE FINISHED TURN both arrive as Turbo Stream
  // actions, so this one hook covers a whole turn.
  //
  // It has to WRAP `detail.render` rather than just listen for the event.
  // `turbo:before-stream-render` fires, Turbo then awaits a repaint, and only
  // *then* mutates the DOM -- so measuring the page from the event, even a frame
  // later, reads the layout from before the batch that just arrived, and the
  // follow ends up one batch behind and drifts further off the foot with every
  // one. Measured in a browser: 480px adrift by the end of a single narration.
  // Wrapping the render puts this after the mutation, with no timing to guess.
  followStreamRender(event) {
    const render = event.detail.render

    event.detail.render = async (streamElement) => {
      await render(streamElement)
      this.follow()
      this.refocus()
    }
  }

  get atBottom() {
    const documentElement = document.documentElement
    return window.innerHeight + window.scrollY >= documentElement.scrollHeight - 40
  }

  follow() {
    if (this.stick) window.scrollTo(0, document.documentElement.scrollHeight)
  }

  // The input is rendered fresh every time `#turn_log` is replaced, and the
  // attribute that would normally handle this is deliberately absent from the
  // broadcast: Turbo focuses `[autofocus]` after a stream render with a plain
  // `.focus()`, which scrolls the element into view and undoes everything above.
  // So focus is restored here instead, with `preventScroll`, and a player who
  // scrolled up to re-read something stays where they are.
  refocus() {
    if (!this.hasCommandTarget) return
    if (document.activeElement === this.commandTarget) return

    this.commandTarget.focus({ preventScroll: true })
  }
}
