"""Text cleanup before Kokoro (every spoken line goes through `prepare`).

Kokoro (kokoro-onnx) turns text into phonemes with espeak-ng, which reads "hm" as the letters "H M", "brb" as
"B R B", emoji names, raw numbers as digits strings, and Japanese script not at all. This layer:
  1. removes emoji, kaomoji and symbols; turns money, percentages, times, dates, ordinals, years and numbers
     into words; splits viewer usernames (@xX_dark_knight99_Xx -> dark knight ninety nine);
  2. collapses repeated letters (hmmmm -> hmm, sooooo -> soo), lower-cases shouted words that are not known
     acronyms (WOW -> wow), and gives vowel-less words a speakable form;
  3. applies the editable dictionary data/tts_pronunciations.json (words and names; a value may be a respelling or
     [shown](/phonemes/) - the misaki-style inline phoneme syntax);
  4. returns either plain text, or - when the line holds inline phonemes - one phoneme string for the whole line
     (the plain parts phonemized by Kokoro's own tokenizer, the marked words spliced in), for is_phonemes=True.
`spelled_out(word)` says whether espeak would still read a word letter by letter (logged during streams).
"""

import json
import os
import re
import unicodedata

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
# the dictionary: $TTS_DICT, else the game's data/tts_pronunciations.json, else a copy next to this file (Mika-Live)
DICT_PATH = next((p for p in (os.environ.get("TTS_DICT", ""), os.path.join(ROOT, "data", "tts_pronunciations.json"),
                              os.path.join(os.path.dirname(os.path.abspath(__file__)), "tts_pronunciations.json")) if p and os.path.exists(p)),
                 os.path.join(ROOT, "data", "tts_pronunciations.json"))

_ONES = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split()
_TENS = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()
_ORD = {"one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth", "nine": "ninth", "twelve": "twelfth"}
_MONTHS = "January February March April May June July August September October November December".split()
_VOWELS = set("aeiouyAEIOUY")
_INLINE = re.compile(r"\[([^\]]+)\]\(/([^/]+)/\)")

_PH = re.compile(r"QQPH[a-z]+QQ")                  # a kept span's place (letters only: the number rules skip it)


def _ph(i):
    s = ""
    while True:
        s = chr(97 + i % 26) + s
        i //= 26
        if i == 0:
            return "QQPH" + s + "QQ"


def _ph_index(p):
    i = 0
    for c in p[4:-2]:
        i = i * 26 + (ord(c) - 97)
    return i


_dict = None
_dict_mtime = 0.0


def _load():
    """The dictionary, re-read when the file changes (edits apply without a restart)."""
    global _dict, _dict_mtime
    try:
        m = os.path.getmtime(DICT_PATH)
    except OSError:
        m = 0.0
    if _dict is None or m != _dict_mtime:
        try:
            with open(DICT_PATH, encoding="utf-8") as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            d = {}
        words = {k.lower(): v for k, v in d.get("words", {}).items()}
        names = dict(d.get("names", {}))
        _dict = {"words": words, "names": names, "acronyms": set(d.get("acronyms", []))}
        _dict_mtime = m
    return _dict


def number_words(n):
    n = int(n)
    if n < 0:
        return "minus " + number_words(-n)
    if n < 20:
        return _ONES[n]
    if n < 100:
        return _TENS[n // 10] + ("" if n % 10 == 0 else " " + _ONES[n % 10])
    if n < 1000:
        return _ONES[n // 100] + " hundred" + ("" if n % 100 == 0 else " and " + number_words(n % 100))
    for div, name in ((10 ** 9, "billion"), (10 ** 6, "million"), (1000, "thousand")):
        if n >= div:
            rest = n % div
            return number_words(n // div) + " " + name + ("" if rest == 0 else (" and " if rest < 100 else " ") + number_words(rest))
    return str(n)


def ordinal_words(n):
    w = number_words(n)
    head, _, last = w.rpartition(" ")
    if last in _ORD:
        last = _ORD[last]
    elif last.endswith("y"):
        last = last[:-1] + "ieth"
    else:
        last += "th"
    return (head + " " + last).strip()


def year_words(y):
    y = int(y)
    if 2000 <= y <= 2009:
        return number_words(y)
    hi, lo = divmod(y, 100)
    return number_words(hi) + (" hundred" if lo == 0 else (" oh " + _ONES[lo] if lo < 10 else " " + number_words(lo)))


def _time_words(h, m, ap):
    h = int(h)
    m = int(m)
    s = number_words(h)
    if m == 0:
        s += "" if ap else " o'clock"
    elif m < 10:
        s += " oh " + _ONES[m]
    else:
        s += " " + number_words(m)
    return s + (" " + " ".join(ap.replace(".", "").upper()) if ap else "")


def _numbers(t):
    t = re.sub(r"\$(\d+)(?:\.(\d\d))?", lambda m: number_words(m.group(1)) + (" dollar" if m.group(1) == "1" else " dollars")
               + (" and " + number_words(m.group(2)) + " cents" if m.group(2) and int(m.group(2)) else ""), t)
    t = re.sub(r"(\d+(?:\.\d+)?)\s?%", lambda m: m.group(1) + " percent", t)
    t = re.sub(r"\b(\d{1,2}):(\d{2})\s?([ap]\.?m\.?)?(?=\W|$)", lambda m: _time_words(m.group(1), m.group(2), (m.group(3) or "").lower()), t, flags=re.I)
    t = re.sub(r"\b(\d{4})-(\d{1,2})-(\d{1,2})\b", lambda m: "%s %s, %s" % (_MONTHS[int(m.group(2)) - 1], ordinal_words(m.group(3)), year_words(m.group(1)))
               if 1 <= int(m.group(2)) <= 12 else m.group(0), t)
    t = re.sub(r"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b", lambda m: "%s %s%s" % (_MONTHS[int(m.group(1)) - 1], ordinal_words(m.group(2)),
               (", " + year_words(m.group(3) if len(m.group(3)) == 4 else "20" + m.group(3))) if m.group(3) else "") if 1 <= int(m.group(1)) <= 12 else m.group(0), t)
    t = re.sub(r"\b(\d+)(st|nd|rd|th)\b", lambda m: ordinal_words(m.group(1)), t, flags=re.I)
    t = re.sub(r"\b(19\d\d|20\d\d)\b", lambda m: year_words(m.group(1)), t)
    t = re.sub(r"#(\d+)", lambda m: "number " + m.group(1), t)
    t = re.sub(r"\b(\d+)\.(\d+)\b", lambda m: number_words(m.group(1)) + " point " + " ".join(_ONES[int(c)] for c in m.group(2)), t)
    t = re.sub(r"\d+", lambda m: " " + number_words(m.group(0)) + " ", t)
    return t


_KAOMOJI = re.compile(r"[\(\[（][^\w\s]{0,3}[\^°ಠ;TˆﾟoOxX><≧≦♥ω・_\-~=\.ᴗ][^\)\]）]{0,10}[\)\]）][^\w\s]{0,4}|"
                      r"(?<!\w)(?::|;|=|x|X)-?[\)\(DPpOo3\]\[/\\|*]+(?!\w)|<3+|\^[_\-\.ω]?\^|>[_\.]?<|\bT_T\b|;_;|o7\b")


def _strip_symbols(t):
    t = _KAOMOJI.sub(" ", t)
    out = []
    for ch in t:
        cat = unicodedata.category(ch)
        if cat in ("So", "Sk", "Cs", "Co", "Cn") or ord(ch) in (0x200D, 0xFE0F):
            out.append(" ")                              # emoji, pictographs, joiners
        elif cat == "Sm" and ch not in "+=":
            out.append(" ")
        elif ch in "*_~`|<>{}\\^":
            out.append(" ")
        else:
            out.append(ch)
    t = "".join(out)
    t = t.replace("&", " and ").replace("+", " plus ").replace("=", " equals ").replace("@", " ")
    return t


def _username(tok):
    """A viewer handle into words: decorations off, underscores and camelCase split, digits as numbers."""
    s = re.sub(r"^(?:xX|Xx|xx)+|(?:Xx|xX|xx)+$", "", tok)
    s = s.replace("_", " ").replace(".", " ")
    s = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", s)
    s = re.sub(r"(?<=[A-Za-z])(?=\d)|(?<=\d)(?=[A-Za-z])", " ", s)
    return s


def _collapse_repeats(w):
    w2 = re.sub(r"(.)\1{2,}", r"\1\1", w)               # hmmmm -> hmm, sooooo -> soo
    return w2


def _word_fix(w, d):
    """One word (letters, maybe an apostrophe) after the dictionary missed it."""
    if not w:
        return w
    if w in d["acronyms"] or w.upper() in d["acronyms"]:
        return w
    if len(w) >= 2 and w.isupper() and w.isalpha():
        w = w.lower()                                     # WOW -> wow (shouting, not an acronym)
        hit = d["words"].get(w)
        if hit is not None:
            return hit
    if w.isalpha() and not (set(w) & _VOWELS) and len(w) >= 2:
        lw = w.lower()
        # no vowel at all: a hum, a hush, or a growl - never letter names
        if lw[0] in "hm" or set(lw) <= set("mnh"):
            return "[hm](/hˈʌm/)"
        if lw.startswith("sh") or set(lw) <= set("sh"):
            return "[shh](/ʃˈʌʃ/)"
        if lw[0] in "gbr":
            return "[grr](/ɡɹˈɜː/)"
        if lw[0] in "pf":
            return "[pfft](/pˈʊf/)"     # (pfˈʌt came back from the recogniser as a swear word)
        return ""                                         # (unknown consonant soup: dropped, logged by the caller)
    return w


def _possessive(v):
    """A dictionary value with 's added: inside the phonemes of an inline span (z after a voiced sound, s after a
    voiceless one, ɪz after a hiss), or as plain 's on a respelling."""
    m = _INLINE.fullmatch(v.strip())
    if not m:
        return v + "'s"
    ph = m.group(2).rstrip()
    last = re.sub(r"[ˈˌː\s]", "", ph)[-1:]
    suf = "ɪz" if last in "szʃʒ" or ph.endswith(("tʃ", "dʒ")) else ("s" if last in "ptkfθ" else "z")
    return "[%s's](/%s%s/)" % (m.group(1), ph, suf)


def normalize(text):
    """Speakable text, possibly holding [shown](/phonemes/) spans."""
    d = _load()
    t = text
    # viewer handles into words first, so names inside them are found too
    t = re.sub(r"@([\w\.]+)", lambda m: _username(m.group(1)), t)
    t = re.sub(r"\b(?=\w*_)\w+\b", lambda m: _username(m.group(0)), t)       # handles written without @
    # names and multi-word entries (they may hold spaces or Japanese script)
    for k in sorted(list(d["names"].keys()) + [k for k in d["words"] if " " in k], key=len, reverse=True):
        v = d["names"].get(k, d["words"].get(k.lower()))
        if re.search(r"[^\x00-\x7f]", k):
            t = t.replace(k, " " + v + " ")
        else:
            # a possessive goes INTO the name ("Luna's" was spoken "Luna, S": the name became a phoneme span and the
            # 's was left on its own, 2026-10-22 stream)
            t = re.sub(r"(?<![\w\[])" + re.escape(k) + r"(['\u2019]s)?(?![\w\]])", lambda m, v=v: _possessive(v) if m.group(1) else v, t, flags=re.I)
    # keep inline phonemes safe from the rules below
    spans = []

    def keep(m):
        spans.append(m.group(0))
        return " " + _ph(len(spans) - 1) + " "

    t = _INLINE.sub(keep, t)
    t = _strip_symbols(t)
    t = _numbers(t)
    t = re.sub(r"[^\x00-\x7f]+", " ", t.replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"').replace("…", "..."))   # other scripts: unspeakable for an English voice

    def word(m):
        w = m.group(0)
        if _PH.fullmatch(w):
            return w
        c = _collapse_repeats(w)
        lc = c.lower()
        # laughs of any length: hahahaha, ahahah, hehehe, lool
        if re.fullmatch(r"(?:ha|ah){3,}h?", lc):
            lc = "hahaha"
        elif re.fullmatch(r"(?:he|hi){3,}h?", lc):
            lc = "hehe"
        elif re.fullmatch(r"lo+l", lc):
            lc = "lol"
        hit = d["words"].get(lc)
        if hit is None and c != w:
            hit = d["words"].get(re.sub(r"(.)\1+", r"\1", c.lower()))   # hahahahaha -> (haha..) / ahhh -> ah
        if hit is not None:
            return hit
        return _word_fix(c, d)

    t = re.sub(r"[A-Za-z][A-Za-z']*", word, t)
    t = _INLINE.sub(keep, t)                              # (the dictionary may have produced new spans)
    t = _PH.sub(lambda m: spans[_ph_index(m.group(0))], t)
    t = re.sub(r"\s+([,\.!\?;:])", r"\1", t)
    t = re.sub(r"([,\.!\?])\1+", r"\1", t)
    return re.sub(r"\s{2,}", " ", t).strip(" ,")


def has_inline(t):
    return bool(_INLINE.search(t))


def to_phonemes(t, tokenizer, lang="en-us"):
    """The whole line as phonemes: plain parts through Kokoro's tokenizer, [x](/p/) spans spliced in."""
    out = []
    pos = 0
    for m in _INLINE.finditer(t):
        plain = t[pos:m.start()]
        if plain.strip():
            out.append(tokenizer.phonemize(plain, lang).strip())
        elif plain and out:
            out.append(" ")
        out.append(m.group(2))
        pos = m.end()
    rest = t[pos:]
    if rest.strip():
        out.append(tokenizer.phonemize(rest, lang).strip())
    s = ""
    for part in out:
        if part == " ":
            continue
        if s and not s.endswith(" ") and part[:1] not in ",.!?;:":
            s += " "
        s += part
    return s


_letters = {}


def spelled_out(word, tokenizer, lang="en-us"):
    """True when espeak reads `word` as its letter names (H M, B R B)."""
    w = re.sub(r"[^A-Za-z]", "", word)
    if len(w) < 2:
        return False
    strip = lambda p: re.sub(r"[ˈˌ\s]", "", p)
    if not _letters:
        for c in "abcdefghijklmnopqrstuvwxyz":
            _letters[c] = strip(tokenizer.phonemize(c, lang))
    return strip(tokenizer.phonemize(w, lang)) == "".join(_letters[c] for c in w.lower())


def prepare(text, tokenizer=None, lang="en-us"):
    """(spoken string, is_phonemes) for Kokoro."""
    t = normalize(text)
    if tokenizer is not None and has_inline(t):
        return to_phonemes(t, tokenizer, lang), True
    return _INLINE.sub(lambda m: m.group(1), t), False


if __name__ == "__main__":
    import sys
    for line in sys.argv[1:] or ["hmm, hmmmm I don't know lol 😂 (╯°□°)╯ it's 3:30pm on 10/19, see you @xX_DarkKnight99_Xx!"]:
        print(repr(line), "->", repr(normalize(line)))
