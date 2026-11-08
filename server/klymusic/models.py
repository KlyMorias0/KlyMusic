from __future__ import annotations

import re
import unicodedata
from difflib import SequenceMatcher
from typing import Literal

from pydantic import BaseModel, Field


class Track(BaseModel):
    id: str = Field(pattern=r"^(apple:[0-9]+|saavn:[A-Za-z0-9_-]{1,32}|youtube:[A-Za-z0-9_-]{11})$")
    title: str = Field(max_length=500)
    artist: str = Field(max_length=500)
    album: str = ""
    duration: float = 0
    artwork: str | None = None
    artistID: str | None = None
    albumID: str | None = None
    explicit: bool = False
    source: str = "apple"


class Collection(BaseModel):
    id: str
    title: str
    artist: str = ""
    artwork: str | None = None
    kind: str = "album"


class Artist(BaseModel):
    id: str
    name: str
    artwork: str | None = None
    banner: str | None = None


class SearchResult(BaseModel):
    tracks: list[Track] = []
    albums: list[Collection] = []
    artists: list[Artist] = []
    warnings: list[str] = []


class HomeSection(BaseModel):
    id: str
    title: str
    subtitle: str = ""
    tracks: list[Track]


class ResolveRequest(BaseModel):
    track: Track
    provider: Literal["auto", "saavn", "youtube"] = "auto"
    quality: Literal["auto", "high", "data"] = "auto"


class PlaybackAsset(BaseModel):
    id: str
    path: str
    provider: str
    codec: str
    bitrate: int
    expiresAt: float
    duration: float


def normalized(value: str) -> str:
    value = value.replace("ı", "i").replace("İ", "I")
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode().lower()
    return " ".join(re.sub(r"[^a-z0-9]+", " ", value).split())


def version_tags(title: str) -> set[str]:
    return set(normalized(title).split()) & {
        "live", "remix", "cover", "acoustic", "instrumental", "karaoke", "sped", "slowed"
    }


def canonical_title(title: str) -> str:
    title = re.sub(r'[\(\[]\s*from\b.*?[\)\]]', '', title, flags=re.I)
    value = normalized(title)
    for suffix in (" official audio", " official music video", " official video", " lyrics", " orijinal versiyon", " original version"):
        value = value.removesuffix(suffix)
    return value.strip()


def match_score(requested: Track, candidate: Track) -> float:
    """Reject wrong versions before scoring spelling, artist and duration."""
    if version_tags(requested.title) != version_tags(candidate.title):
        return 0
    a, b = canonical_title(requested.title), canonical_title(candidate.title)
    title = SequenceMatcher(None, a, b).ratio()
    artist = SequenceMatcher(None, normalized(requested.artist), normalized(candidate.artist)).ratio()
    if title < .76 or artist < .45:
        return 0
    if requested.duration and candidate.duration:
        delta = abs(requested.duration - candidate.duration)
        if delta > max(8, requested.duration * .05):
            return 0
        duration = max(0, 1 - delta / 10)
    else:
        duration = .5
    return .55 * title + .35 * artist + .1 * duration
