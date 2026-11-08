from __future__ import annotations

import asyncio
import base64
import html
import json
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlparse

import httpx
import requests
from Crypto.Cipher import DES
from Crypto.Util.Padding import unpad
from ytmusicapi import YTMusic

from .models import Artist, Collection, SearchResult, Track

USER_AGENT = "KlyMusic/1.0"
SAAVN_ENDPOINT = "https://www.jiosaavn.com/api.php"


def art_size(url: str | None, size: int = 600) -> str | None:
    if not url:
        return None
    url = re.sub(r"\d+x\d+(?:bb)?", f"{size}x{size}bb", url)
    return url.replace("{w}", str(size)).replace("{h}", str(size)).replace("{f}", "jpg").replace("{c}", "bb")


def apple_track(s: dict) -> Track:
    return Track(id=f"apple:{s['trackId']}", title=s["trackName"], artist=s["artistName"],
                 album=s.get("collectionName", ""), duration=s.get("trackTimeMillis", 0) / 1000,
                 artwork=art_size(s.get("artworkUrl100")), artistID=str(s.get("artistId", "")),
                 albumID=str(s.get("collectionId", "")), explicit=s.get("trackExplicitness") == "explicit")


def saavn_track(s: dict) -> Track:
    more = s.get("more_info", {})
    return Track(id="saavn:" + s["id"], title=html.unescape(s.get("song") or s.get("title") or ""),
                 artist=html.unescape(s.get("primary_artists") or more.get("artistMap", {}).get("primary_artists", [{}])[0].get("name", "") or s.get("subtitle", "")),
                 album=html.unescape(s.get("album") or more.get("album", "")),
                 duration=float(s.get("duration") or more.get("duration") or 0),
                 artwork=re.sub(r"\d+x\d+", "500x500", s.get("image", "")) or None,
                 source="saavn", explicit=str(s.get("explicit_content", more.get("explicit_content", "0"))) == "1")


def yt_track(s: dict) -> Track | None:
    vid = s.get("videoId")
    if not vid or not re.fullmatch(r"[A-Za-z0-9_-]{11}", vid):
        return None
    duration = s.get("duration_seconds") or 0
    if not duration and s.get("duration"):
        try:
            for part in s["duration"].split(":"):
                duration = duration * 60 + int(part)
        except (ValueError, AttributeError):
            duration = 0
    artists = s.get("artists") or []
    thumbs = s.get("thumbnails") or []
    return Track(id="youtube:" + vid, title=s.get("title", ""),
                 artist=", ".join(a["name"] for a in artists if a.get("name")),
                 album=(s.get("album") or {}).get("name", ""), duration=duration,
                 artwork=thumbs[-1]["url"] if thumbs else None, source="youtube", explicit=s.get("isExplicit", False))


def safe_media_url(url: str) -> bool:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    return parsed.scheme == "https" and parsed.port in (None, 443) and not parsed.username and any(
        host == domain or host.endswith("." + domain) for domain in ("saavncdn.com", "googlevideo.com")
    )


class Providers:
    def __init__(self, client: httpx.AsyncClient):
        self.http = client
        self.pool = ThreadPoolExecutor(max_workers=3, thread_name_prefix="kly-catalog")
        self.youtube_slots = asyncio.Semaphore(2)
        self.catalog_slots = asyncio.Semaphore(3)

    async def apple_search(self, query: str, kind: str = "song", country: str = "tr", limit: int = 30):
        r = await self.http.get("https://itunes.apple.com/search", params={
            "term": query, "entity": kind, "country": country, "limit": limit, "media": "music"}, timeout=6)
        r.raise_for_status()
        return r.json().get("results", [])

    async def apple_lookup(self, identifier: str, entity: str = "song", country: str = "tr"):
        if not identifier.isdigit():
            raise ValueError("Invalid Apple identifier")
        r = await self.http.get("https://itunes.apple.com/lookup", params={
            "id": identifier, "entity": entity, "country": country, "limit": 100})
        r.raise_for_status()
        return r.json().get("results", [])

    async def apple_search_all(self, query: str) -> SearchResult:
        songs, albums, artists = await asyncio.gather(
            self.apple_search(query), self.apple_search(query, "album", limit=10),
            self.apple_search(query, "musicArtist", limit=8), return_exceptions=True)
        return SearchResult(
            tracks=[apple_track(s) for s in songs if s.get("kind") == "song"] if isinstance(songs, list) else [],
            albums=[Collection(id=str(s["collectionId"]), title=s["collectionName"], artist=s["artistName"], artwork=art_size(s.get("artworkUrl100"))) for s in albums] if isinstance(albums, list) else [],
            artists=[Artist(id=str(s["artistId"]), name=s["artistName"]) for s in artists] if isinstance(artists, list) else [],
            warnings=["Katalog bağlantısı şu anda kullanılamıyor."] if isinstance(songs, Exception) else [])

    async def artist(self, identifier: str):
        items = await self.apple_lookup(identifier)
        artist = next((s for s in items if s.get("wrapperType") == "artist"), None)
        if not artist:
            raise ValueError("Sanatçı bulunamadı.")
        info = Artist(id=identifier, name=artist["artistName"])
        try:
            r = await self.http.get(f"https://music.apple.com/tr/artist/{identifier}", follow_redirects=True)
            r.raise_for_status()
            match = re.search(r'<script[^>]*id="serialized-server-data"[^>]*>(.*?)</script>', r.text, re.S)
            if match:
                data = json.loads(match.group(1))
                hero = data["data"][0]["data"]["sections"][0]["items"][0]
                def image(key):
                    return art_size((hero.get(key) or {}).get("dictionary", {}).get("url"), 1000)
                info.artwork = image("circleArtwork") or image("artwork")
                info.banner = image("wideArtwork") or info.artwork
        except (httpx.HTTPError, ValueError, KeyError, IndexError, TypeError):
            pass
        tracks = [apple_track(s) for s in items if s.get("kind") == "song"]
        albums = await self.apple_lookup(identifier, "album")
        return {"artist": info.model_dump(), "tracks": [s.model_dump() for s in tracks],
                "albums": [Collection(id=str(s["collectionId"]), title=s["collectionName"], artist=s["artistName"], artwork=art_size(s.get("artworkUrl100"))).model_dump() for s in albums if s.get("wrapperType") == "collection"]}

    async def saavn(self, method: str, **params):
        r = await self.http.get(SAAVN_ENDPOINT, params={
            "__call": method, "_format": "json", "_marker": "0", "ctx": "web6dot0", **params})
        r.raise_for_status()
        return r.json()

    async def saavn_search(self, query: str) -> list[Track]:
        data = await self.saavn("search.getResults", q=query, p=1, n=20)
        return [saavn_track(s) for s in data.get("results", []) if s.get("id")]

    async def saavn_stream(self, identifier: str, quality: str):
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,32}", identifier):
            raise ValueError("Invalid Saavn identifier")
        data = await self.saavn("song.getDetails", pids=identifier)
        if isinstance(data, list):
            song = data[0] if data else {}
        elif "songs" in data:
            song = data["songs"][0] if data["songs"] else {}
        else:
            song = data.get(identifier) or next((v for v in data.values() if isinstance(v, dict)), {})
        more = song.get("more_info", {})
        # The catalogue flag also appears on records with a public clear-media URL.
        # Only that URL field is supported; no DRM media or licence/key API is used.
        encoded = song.get("encrypted_media_url") or more.get("encrypted_media_url")
        if not encoded:
            raise ValueError("Ses bağlantısı bulunamadı.")
        url = unpad(DES.new(b"38346591", DES.MODE_ECB).decrypt(base64.b64decode(encoded)), 8).decode()
        high = str(song.get("320kbps", more.get("320kbps", "false"))).lower() == "true"
        bitrate = 320 if high and quality != "data" else 160 if quality != "data" else 96
        url = re.sub(r"_(?:12|48|96|160|320)\.mp4", f"_{bitrate}.mp4", url)
        if not safe_media_url(url):
            raise ValueError("Unexpected media host")
        return {"url": url, "headers": {}, "codec": "aac", "bitrate": bitrate,
                "duration": float(song.get("duration") or more.get("duration") or 0)}

    async def youtube_search(self, query: str) -> list[Track]:
        async with self.catalog_slots:
            loop = asyncio.get_running_loop()
            def run():
                class TimedSession(requests.Session):
                    def request(self, *args, **kwargs):
                        kwargs.setdefault("timeout", 8)
                        return super().request(*args, **kwargs)
                with TimedSession() as session:
                    return YTMusic(requests_session=session).search(query, filter="songs", limit=15)
            rows = await asyncio.wait_for(loop.run_in_executor(self.pool, run), 12)
        return [track for row in rows if (track := yt_track(row))]

    async def youtube_stream(self, identifier: str, quality: str):
        if not re.fullmatch(r"[A-Za-z0-9_-]{11}", identifier):
            raise ValueError("Invalid YouTube identifier")
        async with self.youtube_slots:
            runtime = "deno" if os.getenv("DENO_INSTALL") or os.path.exists("/usr/local/bin/deno") else "node"
            fmt = "bestaudio[ext=m4a][abr<=100]/bestaudio[ext=m4a]" if quality == "data" else "bestaudio[ext=m4a]"
            proc = await asyncio.create_subprocess_exec(
                sys.executable, "-m", "yt_dlp", "--dump-single-json", "--skip-download", "--no-playlist",
                "--no-warnings", "--socket-timeout", "8", "--retries", "1", "--js-runtimes", runtime,
                "--format", fmt, f"https://www.youtube.com/watch?v={identifier}",
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
            try:
                out, _ = await asyncio.wait_for(proc.communicate(), 25)
            except BaseException:
                if proc.returncode is None:
                    proc.kill()
                await proc.communicate()
                raise
            if proc.returncode:
                raise ValueError("YouTube bu kaydın ses bağlantısını vermedi.")
            data = json.loads(out)
        url = data.get("url", "")
        if not safe_media_url(url):
            raise ValueError("Unexpected media host")
        return {"url": url, "headers": {k: v for k, v in data.get("http_headers", {}).items() if k.lower() in ("user-agent", "referer", "origin")},
                "codec": "aac", "bitrate": int(data.get("abr") or 128), "duration": float(data.get("duration") or 0)}

    async def close(self):
        self.pool.shutdown(wait=False, cancel_futures=True)
