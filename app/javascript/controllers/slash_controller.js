import { Controller } from "@hotwired/stimulus"

// THE SLASH MENU: what this turn can be completed with, and nothing else.
//
// The captain's ruling of 2026-09-04, evening: "support a slash prefix
// autocomplete in the text box, and resolve those and verb-prefixed lines
// offline then fallback to the model." This is the box half of it. The server
// half is `Playthrough::Grammar` -- a `/take slate` line submits as ordinary
// text and the slash is stripped before the line is read, so this controller
// writes nothing the plain box could not have been typed by hand.
//
// EVERY FACT IT NEEDS ARRIVES WITH THE TURN. `menuValue` is rendered into
// `#turn_log` by `Playthrough::SlashMenu` on every render, and `#turn_log` is
// replaced by a Turbo Stream at the end of every turn -- so the controller is
// torn down and rebuilt with this turn's exits, cast and items, and there is no
// request to make, no cache to invalidate and no model to ask. That is also why
// the scope is INSIDE the replaced element, which is the opposite of
// `play_controller`'s: that one has to survive the replacement and this one has
// to be renewed by it.
//
// IT DEGRADES TO A PLAIN TEXT BOX. With no JavaScript there is no menu, the
// input is an ordinary field in an ordinary form, and every line a player could
// have picked off the menu can still be typed.
export default class extends Controller {
  static targets = [ "input", "menu" ]
  static values = { menu: Object }

  connect() {
    this.index = -1
    this.options = []
    this.close()
  }

  // WHAT THE BOX SHOULD OFFER FOR WHAT IS IN IT. Called on every keystroke and
  // on focus; it is a filter over an object already in memory, so it costs
  // nothing to run this often.
  refresh() {
    const value = this.inputTarget.value

    if (!value.startsWith("/")) return this.close()

    const [ word, rest ] = this.split(value)

    // `/` and a partial verb: the five verbs that resolve a record.
    if (rest === null) {
      return this.open(
        this.verbs.filter((verb) => verb.word.startsWith(word)).map((verb) => ({
          value: `/${verb.word} `, label: verb.word, hint: verb.hint, keepOpen: true
        }))
      )
    }

    // A verb and a space: the closed set that verb resolves against, this turn.
    const targets = this.menuValue.targets?.[word]
    if (!targets) return this.close()

    const wanted = rest.toLowerCase()
    this.open(
      targets.filter((name) => name.toLowerCase().includes(wanted)).map((name) => ({
        value: `/${word} ${name}`, label: name, hint: null, keepOpen: false
      }))
    )
  }

  // ARROWS MOVE, ENTER AND TAB ACCEPT, ESCAPE DISMISSES -- and every one of them
  // is a no-op while the menu is shut, so the box behaves exactly as it did
  // before for a player who never types a slash.
  navigate(event) {
    if (!this.open_) {
      // Escape with the menu already shut is the browser's business.
      return
    }

    switch (event.key) {
      case "ArrowDown": event.preventDefault(); this.move(1); break
      case "ArrowUp": event.preventDefault(); this.move(-1); break
      case "Tab":
        if (this.index < 0) return
        event.preventDefault()
        this.accept(this.options[this.index])
        break
      // ENTER ON A LINE THAT IS ALREADY THE ACTIVE OPTION SUBMITS IT. A player
      // who typed the whole thing -- or accepted it a moment ago -- means "go",
      // and swallowing that Enter to re-accept the text already in the box
      // would cost them a keystroke every turn for nothing.
      case "Enter":
        if (this.index < 0) return
        if (this.options[this.index].value === this.inputTarget.value) return this.close()
        event.preventDefault()
        this.accept(this.options[this.index])
        break
      case "Escape": event.preventDefault(); this.close(); break
    }
  }

  // A click on a row is the same acceptance as Enter on it. `mousedown` rather
  // than `click`, because the input loses focus first and a blur that closed the
  // menu would take the row out from under the click.
  pick(event) {
    event.preventDefault()
    const row = event.currentTarget
    this.accept(this.options[Number(row.dataset.slashIndex)])
  }

  dismiss() {
    this.close()
  }

  // --- the menu itself ------------------------------------------------------

  get verbs() {
    return this.menuValue.verbs || []
  }

  // The verb typed so far, and what follows the first space -- null when there
  // is no space yet, which is what tells "still naming the verb" from "naming
  // the thing".
  split(value) {
    const text = value.slice(1)
    const space = text.indexOf(" ")

    if (space === -1) return [ text.toLowerCase(), null ]

    return [ text.slice(0, space).toLowerCase(), text.slice(space + 1) ]
  }

  open(options) {
    this.options = options
    if (options.length === 0) return this.close()

    // The first row is active, so Enter always means something once the menu is
    // showing. Arrow keys move from there.
    this.index = 0
    this.render()
    this.open_ = true
    this.menuTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.open_ = false
    this.index = -1
    this.options = []
    if (!this.hasMenuTarget) return

    this.menuTarget.hidden = true
    this.menuTarget.replaceChildren()
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }

  move(step) {
    this.index = (this.index + step + this.options.length) % this.options.length
    this.render()
  }

  // ACCEPTING A VERB LEAVES THE MENU OPEN on the set it resolves against, which
  // is the whole point of the two-step: `/ta` -> `/take ` -> the things lying
  // here. Accepting a name closes it, because the line is finished and the next
  // key should be Enter.
  accept(option) {
    if (!option) return

    this.inputTarget.value = option.value
    this.inputTarget.focus()

    if (option.keepOpen) return this.refresh()

    this.close()
  }

  render() {
    this.menuTarget.replaceChildren(...this.options.map((option, index) => {
      const row = document.createElement("li")
      row.id = `${this.element.id || "slash"}_option_${index}`
      row.className = "slash-option"
      row.setAttribute("role", "option")
      row.setAttribute("aria-selected", String(index === this.index))
      row.dataset.slashIndex = String(index)
      row.dataset.action = "mousedown->slash#pick"
      row.textContent = option.label
      if (option.hint) {
        const hint = document.createElement("span")
        hint.className = "slash-hint"
        hint.textContent = option.hint
        row.appendChild(hint)
      }
      if (index === this.index) this.inputTarget.setAttribute("aria-activedescendant", row.id)
      return row
    }))
  }
}
