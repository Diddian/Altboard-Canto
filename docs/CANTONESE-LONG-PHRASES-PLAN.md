# Cantonese long-phrase roadmap (planning only)

## Canonical source, not three hand-written spellings

Every new entry is Traditional Chinese text and **one verified Jyutping pronunciation**, with tone numbers and syllable boundaries. The existing builder derives Sidney Lau and Yale indexed spellings. A Chinese phrase alone is insufficient where characters are polyphonic or have colloquial readings. Check existing upstream entries before adding duplicates.

The whole-phrase indexes do not yet decode words typed with different systems *at different syllables*. For example, 佢對 may be typed `kuideoi` or `keoidui`, while the three phrase-level indexes store only `ku idui` without the space (Sidney Lau), `keuideui` (Yale), and `keoideoi` (Jyutping). Rather than generate exponential combinations for every phrase, segment the raw stream into syllables and decode with a bounded trie/beam search.

## Candidate backlog: NOT YET IMPORTED (requires reading and frequency validation)

- Explanations: 我都唔知點解、我真係唔明、其實我覺得、唔係咁簡單、唔係好清楚、唔知點講好、好似有啲問題、應該都可以
- Questions: 可唔可以幫我、可唔可以解釋、你覺得點樣、點解會咁樣、有冇其他方法、係咪即係話、你講緊乜嘢、咁樣得唔得
- Scheduling: 我而家唔得閒、我一陣覆你、我遲啲覆你、你幾時得閒、幾時有時間、我哋遲啲再傾、我而家出發、不如搵日出嚟
- Requests: 唔該你幫我、麻煩你幫我睇、可唔可以再講一次、可唔可以講清楚、我想問一問、幫我睇一睇、我想搵你傾、如果冇問題
- Particles: 咁又唔係喎、唔係咁講喎、咁樣都得嘅、其實唔係咁、唔係話唔得、我又唔係話、真係冇計啦、咁就冇辦法

## Execution criteria

1. Count existing upstream n-grams and license conditions; prioritize attested frequent Hong Kong phrases and preserve traditional colloquial forms.
2. Verify one tone-numbered Jyutping reading for every new entry; preserve legitimately different readings and spelling variants separately.
3. Derive three conventions automatically and smoke-test exact word → all indexed spellings.
4. Implement syllable-aware mixed decoder (bounded states, no combinatorial stored aliases), prefer exact matches, and respect tone digits when provided.
5. Rank by corpus frequency + context + local candidate selection, not just source row order; never auto-replace user text.
6. Benchmark real iPhone p95 lookup latency and memory, false Cantonese matches while typing English, and 3/5/8-character examples.

No new phrases in this roadmap are claimed shipped. Live meeting transcription remains planning-only and follows swipe keyboard stabilization.
