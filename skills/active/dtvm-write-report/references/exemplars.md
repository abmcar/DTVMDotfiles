# Primary-source report exemplars

Read these examples for report structure and language, not as evidence for a
specific DTVM measurement.

## Performance and compiler reports

- [V8: Background compilation](https://v8.dev/blog/background-compilation)
  opens with the shipped change and its 5–20% result, then moves through
  implementation, results, and next steps.
- [V8: Sparkplug](https://v8.dev/blog/sparkplug) places benchmark effects next
  to the relevant charts and states repeats and dispersion in the visual
  context.
- [Meta: Accelerating large-scale applications with BOLT](https://engineering.fb.com/2018/06/19/data-infrastructure/accelerate-large-scale-applications-with-bolt/)
  gives the effect range near the start, explains the mechanism, and ties
  variation to workload and architecture.
- [Cloudflare: Unpacking Workers CPU performance benchmarks](https://blog.cloudflare.com/unpacking-cloudflare-workers-cpu-performance-benchmarks/)
  names the exact confounder and the question the benchmark therefore cannot
  answer instead of using a vague confidence label.

## Measurement and validity

- [LLVM benchmarking tips](https://llvm.org/docs/Benchmarking.html) treats CPU
  isolation, repetition, timer resolution, and frequency control as an
  execution checklist. These are quality gates and supporting evidence, not a
  mandatory reader-facing outline.
- [SIGPLAN empirical evaluation checklist](https://www.sigplan.org/Resources/EmpiricalEvaluation/)
  and its [checklist rationale](https://blog.sigplan.org/2019/08/28/a-checklist-manifesto-for-empirical-evaluation-a-preemptive-strike-against-a-replication-crisis-in-computer-science/)
  organize claims, baselines, benchmarks, analysis, metrics, design, and
  presentation while warning against mechanical checklist use.
- [Microsoft: Integrating A/B Testing at Scale](https://www.microsoft.com/en-us/research/wp-content/uploads/2023/05/ICSE2023-Integrating-AB-testing-Offering-at-Scale-Preprint.pdf)
  distinguishes controlled experiments from prototypes, canaries, gradual
  rollouts, and dark launches. Reserve A/B terminology for randomized
  concurrent treatment and control with statistical analysis.

## Technical narrative

- [Google SRE: Postmortem culture](https://sre.google/workbook/postmortem-culture/)
  leads with impact and root cause, quantifies claims, rejects dramatic or
  vague wording, and gives action items a verifiable end state.
- [USENIX: How (and How Not) to Write a Good Systems Paper](https://www.usenix.org/legacy/events/samples/submit/advice.html)
  argues for assumptions and results in the opening, proportional length, and
  precise language without ambiguity or cute phrasing.
- [Google Technical Writing: Clear sentences](https://developers.google.com/tech-writing/one/clear-sentences)
  and [short sentences](https://developers.google.com/tech-writing/one/short-sentences)
  favor explicit subjects, strong verbs, objective numbers, and one main idea
  per sentence.

## Adopted pattern

Use the common pattern visible across these sources:

1. shipped or proposed change;
2. effect size and comparison basis;
3. mechanism and the smallest useful visual;
4. decision, tradeoff, or next action;
5. concrete scope note;
6. methods, commands, identity, and full checks in provenance or appendices.
