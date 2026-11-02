# Cantonese Colloquial ASR Review (traditional Hong Kong)

Review-only inventory; NOT automatically added to the recognizer. These forms
contain phonetic variation, alternative orthography, code-switching and several
**non-equivalent** words. User approval and phrase-level tests are required
before any recognition correction or automatic writing normalization.

## 1. Sentence-final particles and discourse markers
啊 呀 阿 吖 喇 啦 囉 咯 咁囉 呢 嘞 嘅 㗎 㗎喇 㗎啦 㗎喎
喎 噃 啫 咋 㗎啫 嘛 咩 咩呀 噉啦 㖭 添 㗎嘛 噚 吓 噯 唉 嘩 噢 哦
呀嘛 喎喂 喂 呵 呵呵 哈 哈哈

## 2. Demonstratives, reference and quantity
呢 依 嗰 果 哩 呢個 嗰個 呢啲 嗰啲 啲 D
呢樣 嗰樣 呢度 嗰度 呢邊 嗰邊 呢排 呢期 嗰陣 嗰時
咁 噉 咁樣 噉樣 咁多 咁少 咁快 咁耐 咁滯

## 3. Negatives, confirmations, uncertainty
唔 冇 無 未 唔係 係喎 係咪 係咩 係囉 係呀 係吖 係呀係呀
唔得 唔使 唔駛 唔好 唔會 唔知 唔明 唔記得 唔緊要 唔怕
冇嘢 冇乜 冇所謂 冇問題 冇錯 應該 可能 未必 大概
嗯 唔嗯 呃 唔係呀 咦 嗯哼

## 4. Function words and particles
緊 咗 佐 過 住 晒 嗮 埋 返 番 嚟 黎 去 俾 畀 比
哋 嘅 地 噉 咁 咪 唔 唔該 嗌 嘢 睇 寫 係

## 5. Questions and conversation transitions
乜 乜嘢 咩 邊 邊個 邊度 邊處 幾時 幾多 點 點樣
點解 點算 點搞 點做 做乜 做咩 做乜嘢
即係 跟住 跟住呢 然之後 之後 然後 所以 因為
不過 但係 定係 或者 話說 又或者 總之 咁所以

## 6. Common spoken verbs, colloquial nouns
睇 聽 講 話 傾 整 搞 攞 拎 揾 搵 撳 㩒
諗 捱 掂 郁 唞 嗌 扮 飲 食 搞掂 搞唔掂
嘢 啲嘢 呢啲嘢 嗰啲嘢 嘢食 嘢飲 嘢做
嚿 舊 篤 啖 撻 碌 抽 隻 條 樽 棟
咁鬼 勁 超 鬼 真係 直情 簡直 麻麻 冇癮 正 爽 嬲

## 7. English / Cantonese code-switch, mixed script
OK 唔OK AI App Apps Bug Bugs Loading Settings Keyboard
Feature Features Mode Update Push GitHub Workflow IPA
Test Testing Model Models Transcribe Transcription
LLM Prompt Rewrite Clean Up Full Access Shortcut iPhone

## 8. Pairs that must NEVER be globally collapsed

- 嘅 / 㗎: distinct functions and sentence-end forces.
- 啊 / 呀 / 吖 / 阿: overlapping spoken particles, but 阿 also a prefix/name marker.
- 咁 / 噉: use and orthography depend on sentence role and register.
- 啲 / D: D also a literal English character or identifier.
- 唔 / 嗯: negation versus vocal acknowledgment.
- 返 / 番: lexical form depends on context; 番 also appears in names/words.
- 比 / 俾 / 畀: comparisons, giving, passive/causative differ.
- 黎 / 嚟: traditional corpus preferences versus canonical come verb.
- 咗 / 佐: spoken aspect versus separate name/character.
- 囉 / 咯: regional writing differences; preserve user preference.
- 嘢 / 野: colloquial noun versus wild/open-field sense.
- 「m」「ng」: syllabic nasal readings are different; IME convenience aliases
  must not rewrite recognizer output without context.
- 啦 / 喇: particle role and preferred transcription can differ.

## Review workflow
1. User marks preferred forms, allowed synonyms, and forms to preserve verbatim.
2. Create 20+ full-sentence recordings per class with accent, speed and code-switch.
3. Compare raw ASR versus suggested normalized text, preserving the raw record.
4. Apply only low-risk approved rules; high ambiguity remains a suggestion.
5. Add regression tests for negative statements, names, honorifics and English.

