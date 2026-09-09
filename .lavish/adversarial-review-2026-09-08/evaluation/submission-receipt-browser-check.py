"""Drives a real Chromium through the four cases the submission receipt has to get
right, and writes what it actually saw to submission-receipt-browser-log.json.

WHAT THIS IS AND IS NOT. It is the acknowledgement path in a real browser --
installed Turbo, the real Stimulus controller, real form submissions against a
real Rails server -- over the fixture in submission-receipt-fixture.rb, with no
worker running so every submission stays queued. It is NOT gameplay: no turn is
ever played, no model is ever asked anything, and nothing here says the game
narrates well. The same fixture-only scope as the toll-notice check beside it.

Usage, from the repository root, with a server already up on a non-3000 port and
chrome-devtools-axi pointed at a browser you started yourself:

    CHROME_DEVTOOLS_AXI_BROWSER_URL=http://127.0.0.1:9336 \
    python3 .lavish/adversarial-review-2026-09-08/evaluation/submission-receipt-browser-check.py \
            http://127.0.0.1:3142/playthroughs/1
"""
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:3142/playthroughs/1"

# Read the field and the receipt the way a player sees them. `[data-play-target]`
# rather than an id: the battle panel puts a `command` field in every one of its
# forms, so `getElementById` finds a button's hidden line instead of the box.
READ = """() => {
  const ask = document.querySelector("[data-play-target=command]")
  const receipt = document.querySelector("[data-play-target=receipt]")
  const battle = document.querySelector(".sheet.battle form")
  return {
    box: ask ? ask.value : null,
    receipt: receipt ? receipt.textContent : null,
    receiptHidden: receipt ? receipt.hidden : null,
    battleLine: battle ? battle.elements.command.value : null,
    battleFieldType: battle ? battle.elements.command.type : null,
    streamPresent: !!document.getElementById("stream"),
    tokens: document.querySelectorAll("input.request-token").length
  }
}"""

CASES = [
    ("a typed line is echoed and the box is cleared",
     """() => {
       const ask = document.querySelector("[data-play-target=command]")
       ask.value = "wait quietly by the door"
       ask.form.requestSubmit()
       return "submitted"
     }"""),
    ("a draft typed while the POST is in flight survives, and the echo is what was sent",
     """() => {
       const ask = document.querySelector("[data-play-target=command]")
       ask.value = "look at the tide-slate"
       ask.form.requestSubmit()
       ask.value = "a newer draft typed while it was in flight"
       return "submitted, then a newer draft typed in the same tick"
     }"""),
    ("a battle button is echoed and stays armed",
     """() => {
       const form = document.querySelector(".sheet.battle form")
       form.requestSubmit(form.querySelector("input[type=submit]"))
       return "clicked"
     }"""),
    ("a response that lost the race to its turn's page shows nothing",
     """() => {
       const log = document.getElementById("turn_log")
       const copy = log.outerHTML
       const ask = document.querySelector("[data-play-target=command]")
       ask.value = "shout for the clerk"
       ask.form.requestSubmit()
       log.outerHTML = copy
       return "submitted, then the page was replaced under the form"
     }"""),
]


def axi(*command):
    done = subprocess.run(["chrome-devtools-axi", *command], capture_output=True, text=True)
    return {"command": list(command), "status": done.returncode,
            "stdout": done.stdout, "stderr": done.stderr}


steps = []
for title, script in CASES:
    steps.append({"case": title, "records": [
        axi("open", URL),
        axi("eval", READ),
        axi("eval", script),
    ]})
    time.sleep(2)
    steps[-1]["records"].append(axi("eval", READ))

# THE QUEUED CONDITION, READ OFF THE RECORDS RATHER THAN OFF THE PAGE. Every
# line above was accepted and none of them was played: no worker exists to play
# one, so `playthrough_commands` is all `pending` and no pending page was ever
# broadcast (`#stream` is absent throughout the reads above).
queued = subprocess.run(
    ["bin/rails", "runner",
     "puts Playthrough.order(:id).first.commands.order(:id).pluck(:command, :status).to_json"],
    capture_output=True, text=True)
steps.append({"case": "every submission was accepted and none was played",
              "records": [ {"command": ["bin/rails", "runner", "commands.pluck(:command, :status)"],
                            "status": queued.returncode,
                            "stdout": queued.stdout.strip().splitlines()[-1] if queued.stdout.strip() else "",
                            "stderr": queued.stderr.strip().splitlines()[-1] if queued.stderr.strip() else ""} ]})

revision = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
dirty = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout.strip()

(ROOT / "submission-receipt-browser-log.json").write_text(json.dumps({
    "what": "The submission acknowledgement in a real Chromium: installed Turbo, the real "
            "play controller, real form submissions against a real Rails server. Fixture only "
            "-- no turn is played and no model is asked anything.",
    "revision": revision,
    "uncommitted_at_capture": dirty.splitlines(),
    "url": URL,
    "conditions": [
        "isolated worktree-local SQLite fixture built by submission-receipt-fixture.rb",
        "web process only on 127.0.0.1:3142; no bin/jobs worker, so every accepted "
        "submission stays queued and no pending page is ever broadcast",
        "no OPENROUTER_API_KEY and TA_LOCAL_MODELS unset: no model call is possible",
    ],
    "steps": steps,
}, indent=2) + "\n")
print(f"wrote submission-receipt-browser-log.json at {revision}")
