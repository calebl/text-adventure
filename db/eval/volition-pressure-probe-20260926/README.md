# Typed volition request: 4-call price probe

`rake eval:volition_probe SET=volition-pressure-probe-20260926` sent the pinned
request (`test/fixtures/files/volition_system_one_request.json`, with the
pressure question's true/false criteria) to OpenRouter Decisions
(`typesafe/jev-1.13`) four times, under a 0.05 USD ceiling. All four answered 200.

`rake eval:volition_probe_price SET=volition-pressure-probe-20260926` recomputes
the figures from `receipts.json`:

- per call: 0.000030702 USD (731 input and 143 output tokens, the same on every call)
- four calls: 0.000122808 USD
- projected 48 calls: 0.001473696 USD

The credit bracket was taken right before and right after the run, and both
readings were `total_usage` 58.603755023. So the charge had not settled when
the second reading was taken. A reading four minutes later was 58.649766311,
a rise of 0.046 USD. That is far more than four calls cost, and the account is
shared, so the rise cannot be attributed to this run. The receipts'
`usage.cost` is the per-call figure.
