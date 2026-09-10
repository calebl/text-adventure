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
  static targets = [ "command", "receipt", "recovery" ]

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

  disconnect() {
    clearTimeout(this.recoveryTimer)
  }

  // A lost broadcast or a stopped worker must leave a way back to the saved
  // command. This offers a read-only reload; elapsed time never declares the
  // worker dead and never retries an action on its own.
  scheduleRecovery() {
    if (this.recoveryTimer) return

    this.recoveryTimer = setTimeout(() => {
      if (this.hasRecoveryTarget) this.recoveryTarget.hidden = false
    }, 30000)
  }

  clearRecovery() {
    clearTimeout(this.recoveryTimer)
    this.recoveryTimer = null
    if (this.hasRecoveryTarget) this.recoveryTarget.hidden = true
  }

  reloadSavedTurn(event) {
    event.preventDefault()
    window.location.reload()
  }

  // WHAT AN ACCEPTED SUBMISSION LOOKS LIKE, and it has to look like something.
  // The acknowledgement carries a fresh token and no page at all, and the
  // pending page is broadcast by the job only once it owns the game's lock --
  // so with the queue behind an unfinished turn the page did not change at all
  // and the typed line just sat there, which is what makes a player retype.
  //
  // THE LINE COMES OFF THE PAYLOAD TURBO SENT, not off the field. Measured in a
  // browser: `turbo:submit-start` does not fire synchronously inside
  // `requestSubmit()`, so a draft typed in the same tick was already in the box
  // by the time a handler there read it -- and this echoed the draft and then
  // cleared it. `formSubmission.body` is what actually went to the server.
  //
  // Three guards, and each one is a way this could lie:
  //
  //   * only on `success`, so a submission the server did not take is never
  //     echoed as though it had been;
  //   * only while the form is still in the document, so a response that lost
  //     the race to its own turn's page cannot put an echo under a finished
  //     turn -- a `#turn_log` replace detaches the form this was submitted from;
  //   * only if the field still holds what was sent, so a line typed while the
  //     POST was in flight is left alone rather than wiped.
  //
  // A hidden field is a battle button's fixed line: it is echoed and never
  // cleared, because clearing it would disarm the button.
  acknowledgeSubmission(event) {
    if (!event.detail?.success) return

    const form = event.target
    const line = event.detail.formSubmission?.body?.get?.("command")
    if (!line || !document.contains(form)) return

    this.scheduleRecovery()

    const field = form.elements?.command
    if (field && field.type !== "hidden" && field.value === line) field.value = ""
    if (!this.hasReceiptTarget) return

    this.receiptTarget.textContent = `> ${line}`
    this.receiptTarget.hidden = false
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
      if (streamElement.getAttribute("target") === "turn_log") {
        if (this.element.querySelector("#stream")) this.scheduleRecovery()
        else this.clearRecovery()
      }
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
