# Jyutping dictionary data and attribution

The Altboard-Canto offline lexicon is generated from the file Modules/Preparing/Sources/Preparing/Resources/jyutping.txt in https://github.com/yuetyam/jyutping, at commit 16bda076094abd63e0961cdc49e2b08ab4e381a3, Git blob SHA1 708236a9458ec933aa3d2b70aa372e613a7cc0b6.

The upstream repository publishes code under CC0 1.0 and credits the Rime-Cantonese lexicon maintained by CanCLID: https://github.com/rime/rime-cantonese. The main Rime-Cantonese data is licensed CC BY 4.0: https://creativecommons.org/licenses/by/4.0/.

Altboard-Canto changes the source by normalizing lowercase Jyutping, filtering invalid/duplicate rows, and converting the word/romanization data to a read-only SQLite lookup database with indexes and source-order priority. No ODbL jyut6ping3.maps dataset is included.

Attribution does not imply upstream endorsement. The app's source code remains subject to its own GPL-3.0 license.

The offline Cantonese N-gram/word-frequency tables are aggregate counts derived from the Hong Kong Cantonese Corpus (HKCanCor), via the PyCantonese CHAT conversion pinned to commit `3d729c01e53f6056cb1c6c527953837e9a106147`. The original HKCanCor was compiled by Kang Kwong Luke, with the citation Luke and Wong (2015), *The Hong Kong Cantonese Corpus: Design and Uses*, Journal of Chinese Linguistics Monograph Series 25, 312–333. HKCanCor is licensed CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). The build extracts word and character 1–3-gram counts, and bundles no source dialogue or speaker metadata. This adaptation is not endorsed by the corpus creators. Attribution is also shipped in `JyutpingResources/HKCanCorAttribution.txt`.
