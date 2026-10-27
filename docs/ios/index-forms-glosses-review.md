# Index → Forms: glosses for scholarly review (G3)

The Index's **Forms** tab (Index 2.0, PR E) lists the 23 poetic forms that the printed
headings of Sri Guru Granth Sahib Ji name, from `shabd_poetic_genre`. Each row shows only:

- the form's name, transliterated from the heading (e.g. *Barah Maha*);
- the **verbatim** Gurmukhi heading it was read from;
- the raag and the Ang.

**What a form means is deliberately not shown.** The table below is a draft of one-line literal
glosses. It ships **nowhere in the app** until a Granthi/scholar has reviewed it (gate G3). Once
approved, the glosses can be added to `PoeticForms` and shown under each form name.

| Form (key) | First at | Draft literal gloss | Confidence |
|---|---|---|---|
| Pahare (`pahare`) | Sri Raag, Ang 74 | "watches": the watches of the night as the stages of a life | likely |
| Vanjara (`vanjara`) | Sri Raag, Ang 81 | "the trader" | likely |
| Barah Maha (`barah_maha`) | Majh, Ang 133; Tukhari, Ang 1107 | "twelve months" | high |
| Din Raini (`din_raini`) | Majh, Ang 136 | "day and night" | high |
| Karhale (`karhale`) | Gauri, Ang 234 | "camels" (the restless mind as a camel) | likely |
| Bavan Akhri (`bavan_akhri`) | Gauri, Ang 250; Gauri (Kabir), Ang 340 | "fifty-two letters" | high |
| Thitti (`thitti`) | Gauri, Ang 296; Gauri (Kabir), Ang 343; Bilaval, Ang 838 | "lunar days" | high |
| Dakhne (`dakhne`) | Gauri, Ang 322; Maru, Ang 1094 | "of the south"? (dialect/metre); **needs a scholar** | uncertain |
| Birhare (`birhare`) | Asa, Ang 431 | "songs of separation" | likely |
| Patti (`patti`) | Asa, Ang 432 and 434 | "the writing tablet" (an alphabet acrostic) | likely |
| Ghorian (`ghorian`) | Vadhans, Ang 575 | "mares" (wedding songs) | likely |
| Alahunian (`alahunian`) | Vadhans, Ang 578 | "dirges" (songs of mourning) | likely |
| Kuchaji (`kuchaji`) | Suhi, Ang 762 | "the unrefined bride" | likely |
| Suchaji (`suchaji`) | Suhi, Ang 762 | "the refined bride" | likely |
| Gunvanti (`gunvanti`) | Suhi, Ang 763 | "the virtuous bride" | likely |
| Sadd (`sadd`) | Ramkali, Ang 923 | "the call" | likely |
| Ruti (`ruti`) | Ramkali, Ang 927 | "seasons" | high |
| Anjulian (`anjulian`) | Maru, Ang 1007 and 1019 | "cupped hands" (offering) | uncertain |
| Gatha (`gatha`) | after the raags, Ang 1360 | a form in the Gatha/Sahaskriti register; **needs a scholar** | uncertain |
| Funhe (`funhe`) | after the raags, Ang 1361 | **needs a scholar** | uncertain |
| Chaubole (`chaubole`) | after the raags, Ang 1363 | "four-word/four-voiced verses"? **needs a scholar** | uncertain |
| Savaiye (`savaiye`) | after the raags, Ang 1385 onward | the savaiya metre | high |
| Mundavani (`mundavani`) | after the raags, Ang 1429 | "the seal" | likely |

## Related data finding (sggs-data, not this app)

`sections` currently names Ang 1363–1384 `ਚਉਬੋਲੇ` (815 lines). The corpus carries the headings
`ਸਲੋਕ ਭਗਤ ਕਬੀਰ ਜੀਉ ਕੇ` (Ang 1364) and `ਸਲੋਕ ਸੇਖ ਫਰੀਦ ਕੇ` (Ang 1377), so that one section
holds Chaubole, Salok Bhagat Kabir Ji and Salok Sheikh Farid Ji. This is a metadata-only fix in
sggs-data (section boundaries; scripture byte-identical). The Index will show the corrected
sections as soon as the dataset pin moves.
