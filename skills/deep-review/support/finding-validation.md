# Independent finding validation

Confidence is certainty that the stated issue AND its claimed impact are supported;
severity is the magnitude/urgency of that impact. Do not mix them.

Validate against source, scope, versions, documented constraints, counterexamples,
and justified exceptions. For architectural findings use architecture-review.md:
verify all duplicate locations or dependency edges and the causal consequence.
Scanner hits, smell labels, file size, fan-in, and popularity of a pattern are not
proof. Confirmed change amplification, policy drift, or unnecessary operational
complexity can have high confidence without an immediate runtime failure.

Score 0-100: 0-20 contradicted/false positive; 21-40 weak/theoretical;
41-60 plausible but key evidence missing; 61-80 supported with uncertainty;
81-100 independently confirmed, including confirmed maintainability improvements.
A high score does not promote P2 debt to P1/P0. Lack of immediate production harm
does not lower confidence when the claimed maintainability impact is evidenced.
Pure style preferences and speculative redesigns should still be rejected.
