"""Render verified findings without losing the original adversarial evidence."""
from pathlib import Path
import html
import json
import re

ROOT = Path(__file__).resolve().parent
findings = json.loads((ROOT / "original-findings.json").read_text())
verification = json.loads((ROOT / "verification.json").read_text())
escape = html.escape
status_colors = {"Verified": "fixed", "Partial": "partial", "Open": "open", "Pending": "pending"}

for finding in findings:
    finding.update(verification["findings"].get(finding["id"], {
        "status": "Open", "change": "Outside this repair batch.",
        "proof": [], "remaining": finding["direction"]
    }))

css = re.search(r"<style>(.*?)</style>", (ROOT / "original-index.html").read_text(), re.S).group(1)
css += """
.fixed{color:var(--green)}.partial{color:var(--gold)}.open{color:var(--red)}.pending{color:var(--muted)}
.status{display:inline-block;border:1px solid currentColor;padding:.1rem .45rem;font-size:.75rem;margin:.2rem 0}
.current{border-left:2px solid var(--green);padding:.3rem 1rem;background:#101918;margin:1rem 0}
.history{color:var(--muted)}.finding h2{margin-top:.4rem}.checks{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.8rem}
.check{border:1px solid var(--line);padding:1rem;background:var(--panel)}.check strong{display:block;color:var(--green)}
.evaluation-table{overflow-x:auto}.evaluation-table small{display:block;color:var(--muted)}
.check,.current{min-width:0;overflow-wrap:anywhere}.evidence-image{width:100%;height:auto;border:1px solid var(--line)}
@media(max-width:720px){.checks{grid-template-columns:minmax(0,1fr)}}
/* The original stylesheet's table geometry was written for the findings table
   alone: a 4rem ID column, a 4rem risk column, and a last column dropped
   entirely under 720px so a phone reads the finding rather than the repair.
   Applied to the live comparison it fragmented "Measure" and "Before" into one
   word per line and deleted every REAL/NOISE/INCONCLUSIVE verdict and p-value
   on a narrow screen. So the live table gets its own widths and keeps all four
   columns, inside its own horizontal scroller. */
.evaluation-table table{table-layout:fixed;min-width:44rem}
.evaluation-table th:first-child{width:26%}.evaluation-table th:nth-child(2){width:22%}
.evaluation-table th:nth-child(3){width:22%}.evaluation-table th:nth-child(4){width:30%}
@media(max-width:720px){.evaluation-table th:last-child,.evaluation-table td:last-child{display:table-cell}
.evaluation-table th:nth-child(3){width:22%}}
"""

rows, cards = [], []
for f in findings:
    badge = f'<span class="status {status_colors[f["status"]]}">{escape(f["status"])}</span>'
    rows.append(f'<tr data-id="{f["id"]}"><td><a href="#{f["id"]}">{f["id"]}</a></td>'
                f'<td>{escape(f["priority"])}</td><td><a href="#{f["id"]}">{escape(f["title"])}</a><small>{badge}</small></td>'
                f'<td>{escape(f["change"])}</td></tr>')
    proof = ''.join(f'<li>{escape(value)}</li>' for value in f["proof"])
    refs = ''.join(f'<a href="https://github.com/calebl/text-adventure/blob/8dd1f5c3ebeea704771220a4257ff4e3aa7086d1/{path}#L{line}">{escape(path)}:{line}</a>'
                   for path, line in f["refs"])
    cards.append(f'''<article class="finding" id="{f['id']}" data-status="{f['status']}" data-priority="{f['priority']}">
      <div class="eyebrow">{f['id']} · {f['priority']} · {escape(f['kind'])}</div>
      <h2>{escape(f['title'])}</h2>{badge}
      <div class="current"><h3>Current result</h3><p>{escape(f['change'])}</p>
      {('<h3>Verification</h3><ul>' + proof + '</ul>') if proof else ''}
      <h3>Remaining limit</h3><p>{escape(f['remaining'])}</p></div>
      <details><summary>Original evidence at 8dd1f5c</summary><div class="detail-body history">
      <p>{escape(f['impact'])}</p><p>{escape(f['evidence'])}</p>
      <h3>Reproduced before the fixes</h3><p>{escape(f['observed'])}</p>
      <h3>Limits of that observation</h3><p>{escape(f['limitation'])}</p>
      <div class="sources">{refs}</div></div></details><a class="back" href="#findings">↑ Findings</a></article>''')

checks = ''.join(f'<div class="check"><strong>{escape(check["name"])}</strong><p>{escape(check["result"])}</p>'
                 f'<a href="{escape(check["file"], quote=True)}">Evidence</a></div>' for check in verification["checks"])
counts = {status: sum(f["status"] == status for f in findings) for status in status_colors}
stats = ''.join(f'<div class="stat"><strong>{count}</strong><span>{status} findings</span></div>' for status, count in counts.items())
approval = ""
evaluation = ""
if verification.get("evaluation"):
    measured = verification["evaluation"]
    comparisons = ''.join(
        f'<tr><td>{escape(row["metric"])}</td><td>{escape(row["before"])}</td>'
        f'<td>{escape(row["after"])}</td><td><strong>{escape(row["verdict"])}</strong>'
        f'<small>{escape(row["detail"])}</small></td></tr>' for row in measured["rows"])
    evaluation = f'''<section class="section" id="live-evaluation"><h2>What the live model actually changed</h2>
    <p class="muted">{escape(measured['model'])} · stored before/after outputs · four runs per arm</p>
    <div class="evaluation-table"><table><thead><tr><th>Measure</th><th>Before</th><th>After</th><th>Verdict</th></tr></thead>
    <tbody>{comparisons}</tbody></table></div><p>{escape(measured['note'])}</p></section>'''
    screenshot = ROOT / "evaluation/toll-notice-ui.png"
    if screenshot.exists():
        evaluation += '''<figure><img class="evidence-image" src="evaluation/toll-notice-ui.png" alt="Actual game turn view with a persisted crossing outcome below quiet arrival prose">
        <figcaption>Actual Rails turn view, rendered from an isolated deterministic fixture with debug disabled. The crossing notice comes from the saved toll, independently of the model's description.</figcaption></figure>'''
if verification.get("evaluation_permission_pending"):
    approval = '''<section class="section" id="evaluation-permission"><h2>Permission needed for the live evaluation</h2>
    <p>The remaining prompt changes need before-and-after measurements. The calls send fixed fictional test scenes and their game instructions to OpenRouter’s <strong>mistralai/mistral-medium-3.1</strong>, with a <strong>$3 total budget ceiling</strong>. They use isolated test worlds; no existing player saves are included.</p>
    <p class="muted">Automatic approval review rejected the live baseline because permission for this external destination and payload was not explicit. Offline verification continues.</p>
    <form data-lavish-question="evaluation-permission" id="evaluation-form">
    <label><input type="radio" name="permission" value="approve" required> Approve the fixed-fixture evaluation</label><br>
    <label><input type="radio" name="permission" value="hold" required> Keep the live evaluation on hold</label><br>
    <button type="submit">Queue this answer</button><p id="permission-status" class="muted" aria-live="polite">No answer queued.</p></form></section>'''
page = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Text Adventure — repair verification</title><style>{css}</style></head><body><main>
<header><div class="eyebrow">Text Adventure / adversarial review / repair verification</div>
<h1>Decisions need consequences.<br>Turns need integrity.</h1><p class="intro">{escape(verification['summary'])}</p>
<p class="muted">{escape(verification['revision'])}</p>
<nav><a href="#findings">Finding status</a><a href="#live-evaluation">Live comparison</a><a href="#validation">Verification</a><a href="report.md">Markdown report</a><a href="original-index.html">Original review</a></nav>
<div class="stats">{stats}</div></header>
{approval}
{evaluation}
<section class="section" id="validation"><h2>Evidence for this repair batch</h2><div class="checks">{checks}</div>
<p class="muted">{escape(verification['limits'])}</p></section>
<section class="section" id="findings"><h2>All findings, with the repair status kept separate</h2>
<div class="toolbar"><label for="status">Status</label><select id="status"><option value="">All</option><option>Verified</option><option>Partial</option><option>Open</option><option>Pending</option></select>
<input id="search" type="search" placeholder="Search findings" aria-label="Search findings"><button id="expand" type="button">Expand original evidence</button></div>
<p id="count" class="muted" aria-live="polite">{len(findings)} findings shown</p>
<table><thead><tr><th>ID</th><th>Risk</th><th>Finding / status</th><th>Current result</th></tr></thead><tbody>{''.join(rows)}</tbody></table></section>
<div id="detail-list">{''.join(cards)}</div>
<footer>Design source: the repository’s existing application and debug layouts—dark surfaces, monospace typography and state colors. Original source links remain pinned to the reviewed commit; repair evidence is linked above.</footer>
<script>
// Rows are looked up by data-id rather than by position: `tbody tr` matched the
// live comparison table too, so the Nth card hid the Nth row of whichever table
// came first and every filter showed the wrong findings while deleting the
// evaluation rows. Scoped to #findings and keyed by id, neither can happen.
const cards=[...document.querySelectorAll('.finding')];
const rows=new Map([...document.querySelectorAll('#findings tbody tr')].map(row=>[row.dataset.id,row]));
const statusFilter=document.getElementById('status'), search=document.getElementById('search');
function filter(){{let count=0;const query=search.value.toLowerCase().trim();cards.forEach(card=>{{const show=(!statusFilter.value||card.dataset.status===statusFilter.value)&&(!query||card.textContent.toLowerCase().includes(query));card.hidden=!show;const row=rows.get(card.id);if(row)row.hidden=!show;if(show)count++;}});document.getElementById('count').textContent=count+' findings shown';}}
statusFilter.addEventListener('change',filter);search.addEventListener('input',filter);
document.getElementById('expand').addEventListener('click',event=>{{const details=[...document.querySelectorAll('details')];const expand=details.some(item=>!item.open);details.forEach(item=>item.open=expand);event.target.textContent=expand?'Collapse original evidence':'Expand original evidence';}});
document.getElementById('evaluation-form')?.addEventListener('submit',event=>{{
event.preventDefault();const choice=new FormData(event.currentTarget).get('permission');
if(!window.lavish){{document.getElementById('permission-status').textContent='Open this report in Lavish, or send your answer in the conversation.';return;}}
const answer=choice==='approve'?'I approve sending the fixed fictional test scenes and game instructions to OpenRouter mistralai/mistral-medium-3.1 for before-and-after evaluation, up to $3 total, using isolated fixtures and no player saves.':'Keep the live model evaluation on hold; continue only offline work.';
window.lavish.queuePrompt(answer,{{tag:'approval',queueKey:'evaluation-permission',element:event.currentTarget,data:{{question:'evaluation-permission',answer:choice}}}});
document.getElementById('permission-status').textContent='Answer queued. Use Send to Agent to submit it.';
}});
</script></main></body></html>'''
(ROOT / "index.html").write_text("\n".join(line.rstrip() for line in page.splitlines()) + "\n")
(ROOT / "findings.json").write_text(json.dumps(findings, indent=2) + "\n")
markdown = ["# Adversarial review — repair verification", "", verification["summary"], "", verification["revision"], "",
            "Original evidence is preserved in [the original report](original-report.md).", "", "## Verification", ""]
for check in verification["checks"]:
    markdown.extend([f'- **{check["name"]}:** {check["result"]} [Evidence]({check["file"]})'])
markdown.extend(["", verification["limits"], ""])
if verification.get("evaluation"):
    measured = verification["evaluation"]
    markdown.extend(["## Live comparison", "", measured["model"], "",
                     "| Measure | Before | After | Verdict |", "| --- | --- | --- | --- |"])
    for row in measured["rows"]:
        markdown.append(f'| {row["metric"]} | {row["before"]} | {row["after"]} | {row["verdict"]}; {row["detail"]} |')
    markdown.extend(["", measured["note"], ""])
if verification.get("evaluation_permission_pending"):
    markdown.extend([
        "## Live-evaluation permission", "",
        "R01/R03 prompt integration is held under the repository's baseline rule. "
        "The prepared evaluation sends fixed fictional test scenes and game instructions "
        "to OpenRouter's mistralai/mistral-medium-3.1, using isolated fixtures and a shared $3 ceiling.", "",
        "Automatic approval review rejected those calls because authorization for the "
        "external destination and payload was not explicit. User permission is still pending.", ""
    ])
for f in findings:
    markdown.extend([f'## {f["id"]} · {f["status"]} · {f["title"]}', "", f["change"], ""])
    markdown.extend(f'- {proof}' for proof in f["proof"])
    markdown.extend(["", f'**Remaining:** {f["remaining"]}', ""])
(ROOT / "report.md").write_text("\n".join(markdown))
