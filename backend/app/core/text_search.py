import re
import unicodedata


_TURKISH_TRANSLATION = str.maketrans(
    {
        "Ç": "C",
        "Ğ": "G",
        "İ": "I",
        "I": "I",
        "Ö": "O",
        "Ş": "S",
        "Ü": "U",
        "ç": "c",
        "ğ": "g",
        "ı": "i",
        "ö": "o",
        "ş": "s",
        "ü": "u",
    }
)


def normalize_search(value: str | None) -> str:
    if value is None:
        return ""
    translated = str(value).translate(_TURKISH_TRANSLATION)
    without_marks = "".join(
        character
        for character in unicodedata.normalize("NFKD", translated)
        if not unicodedata.combining(character)
    )
    # Treat punctuation as a word separator. This lets database searches use
    # token/phrase boundaries, so "tip" matches "Tip Fakultesi" but not
    # "Katip Celebi".
    words_only = re.sub(r"[^a-z0-9]+", " ", without_marks.casefold())
    return " ".join(words_only.split())
