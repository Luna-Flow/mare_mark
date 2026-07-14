# `stats` Design

Statistics are pure transformations over explicit arrays. Raw event storage is
owned by sinks, so filtering cannot rewrite historical observations.

`compare_paired` currently uses median paired delta and a practical percentage
threshold. Its `Interval` stores delta quartiles; it is not a bootstrap or
confidence interval. Empty inputs produce neutral summaries and an `Unknown`
decision rather than raising.

