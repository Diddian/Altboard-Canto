# Jyutping dictionary data and attribution

The Altboard-Canto offline lexicon is generated from the file Modules/Preparing/Sources/Preparing/Resources/jyutping.txt in https://github.com/yuetyam/jyutping, at commit 16bda076094abd63e0961cdc49e2b08ab4e381a3, Git blob SHA1 708236a9458ec933aa3d2b70aa372e613a7cc0b6.

The upstream repository publishes code under CC0 1.0 and credits the Rime-Cantonese lexicon maintained by CanCLID: https://github.com/rime/rime-cantonese. The main Rime-Cantonese data is licensed CC BY 4.0: https://creativecommons.org/licenses/by/4.0/.

Altboard-Canto changes the source by normalizing lowercase Jyutping, filtering invalid/duplicate rows, and converting the word/romanization data to a read-only SQLite lookup database with indexes and source-order priority. No ODbL jyut6ping3.maps dataset is included.

Attribution does not imply upstream endorsement. The app's source code remains subject to its own GPL-3.0 license.
