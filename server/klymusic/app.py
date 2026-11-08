from __future__ import annotations

import asyncio
import hashlib
import logging
import os
import re
import secrets
import time
from collections import OrderedDict, deque
from contextlib import asynccontextmanager
from urllib.parse import urljoin

import httpx
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import Response, StreamingResponse

from .cache import Cache
from .models import HomeSection, PlaybackAsset, ResolveRequest, SearchResult, Track, canonical_title, match_score, normalized
from .providers import Providers, USER_AGENT, apple_track, art_size, safe_media_url

log = logging.getLogger("klymusic")
cache = Cache()
client: httpx.AsyncClient
providers: Providers
rate_buckets: OrderedDict[str, deque] = OrderedDict()


@asynccontextmanager
async def lifespan(app: FastAPI):
    global client, providers
    client = httpx.AsyncClient(timeout=httpx.Timeout(12, read=25), follow_redirects=False,
                               headers={"User-Agent": USER_AGENT}, limits=httpx.Limits(max_connections=80))
    providers = Providers(client)
    yield
    await providers.close()
    await cache.close()
    await client.aclose()


app = FastAPI(title="KlyMusic", version="1.0.0", lifespan=lifespan)


@app.middleware("http")
async def controls(request: Request, call_next):
    address = request.client.host if request.client else "unknown"
    now = time.monotonic()
    bucket = rate_buckets.setdefault(address, deque())
    while bucket and bucket[0] < now - 60:
        bucket.popleft()
    if len(bucket) >= int(os.getenv("REQUESTS_PER_MINUTE", "180")):
        return Response("Çok fazla istek. Biraz sonra tekrar dene.", status_code=429, headers={"Retry-After": "30"})
    bucket.append(now)
    rate_buckets.move_to_end(address)
    while len(rate_buckets) > 10000:
        rate_buckets.popitem(last=False)
    if request.headers.get("content-length", "0").isdigit() and int(request.headers.get("content-length", "0")) > 65536:
        return Response(status_code=413)
    start = time.monotonic()
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Server-Timing"] = f"api;dur={(time.monotonic() - start) * 1000:.1f}"
    if not request.url.path.startswith("/v1/media"):
        log.info("%s status=%s ms=%.0f", request.scope.get("route", request.url.path), response.status_code,
                 (time.monotonic() - start) * 1000)
    return response


@app.get("/health")
async def health():
    return {"status": "ok", "app": "KlyMusic", "version": "1.0.0"}


@app.get("/v1/config")
async def config():
    return {"version": 1, "providers": ["saavn", "youtube"], "minimumIOS": "17.0",
            "artworkProvider": "apple", "accountRequired": False}


async def chart(country: str) -> list[Track]:
    async def load():
        r = await client.get(f"https://rss.marketingtools.apple.com/api/v2/{country}/music/most-played/50/songs.json", timeout=6)
        r.raise_for_status()
        return [Track(id="apple:" + row["id"], title=row["name"], artist=row["artistName"],
                      artistID=row.get("artistId"), artwork=art_size(row.get("artworkUrl100")),
                      explicit="explicit" in row.get("contentAdvisoryRating", "").lower()).model_dump()
                for row in r.json().get("feed", {}).get("results", [])]
    return [Track(**row) for row in await cache.load("chart:" + country, 3600, load)]


@app.get("/v1/home")
async def home():
    async def load():
        results = await asyncio.gather(chart("tr"), chart("us"), providers.apple_search("chill", limit=15), return_exceptions=True)
        sections = []
        for index, (title, subtitle) in enumerate((("Türkiye’de şimdi", "EN ÇOK DİNLENENLER"),
                                                 ("Dünyanın ritmi", "GLOBAL SEÇKİ"),
                                                 ("Biraz yavaşla", "KENDİNE BİR AN AYIR"))):
            rows = results[index]
            if index == 0 and not isinstance(rows, list):
                try:
                    rows = [apple_track(s) for s in await providers.apple_search("Türkçe Pop", limit=20) if s.get("kind") == "song"]
                    title, subtitle = "Türkçe seçki", "KEŞFETMEYE BAŞLA"
                except httpx.HTTPError:
                    pass
            if isinstance(rows, list) and rows:
                tracks = rows if index < 2 else [apple_track(s) for s in rows if s.get("kind") == "song"]
                sections.append(HomeSection(id=str(index), title=title, subtitle=subtitle, tracks=tracks).model_dump())
        if not sections:
            raise HTTPException(503, "Katalog şu anda yüklenemiyor. Yeniden dene.")
        return {"sections": sections}
    return await cache.load("home", 1800, load)


@app.get("/v1/search", response_model=SearchResult)
async def search(q: str = Query(min_length=1, max_length=200), source: str = Query("all", pattern="^(all|youtube|saavn)$")):
    async def load():
        if source == "youtube":
            return SearchResult(tracks=await providers.youtube_search(q)).model_dump()
        if source == "saavn":
            return SearchResult(tracks=await providers.saavn_search(q)).model_dump()
        apple, saavn = await asyncio.gather(providers.apple_search_all(q), providers.saavn_search(q), return_exceptions=True)
        result = apple if isinstance(apple, SearchResult) else SearchResult(warnings=["Katalog araması şu anda kullanılamıyor."])
        if not result.tracks and isinstance(saavn, list):
            result.tracks = saavn
        tokens = normalized(q).split()
        def relevance(track):
            haystack = normalized(track.artist + " " + track.title).split()
            return sum(any(token == word for word in haystack) for token in tokens) / max(1, len(tokens))
        if not result.tracks or (len(tokens) > 1 and max(map(relevance, result.tracks), default=0) < .75):
            try:
                extra = await providers.youtube_search(q)
                result.tracks.extend(track for track in extra if not any(match_score(track, item) >= .82 for item in result.tracks))
            except Exception:
                result.warnings.append("Müzik kaynaklarına şu anda erişilemiyor.")
        result.tracks.sort(key=relevance, reverse=True)
        return result.model_dump()
    try:
        return await cache.load(f"search:{source}:{q.casefold()}", 1800, load)
    except Exception as exc:
        raise HTTPException(503, "Arama kaynağına şu anda erişilemiyor.") from exc


@app.get("/v1/albums/{identifier}")
async def album(identifier: str):
    if not identifier.isdigit():
        raise HTTPException(400, "Geçersiz albüm.")
    async def load():
        rows = await providers.apple_lookup(identifier)
        return {"tracks": [apple_track(s).model_dump() for s in rows if s.get("kind") == "song"]}
    return await cache.load("album:" + identifier, 86400, load)


@app.get("/v1/artists/{identifier}")
async def artist(identifier: str):
    if not identifier.isdigit():
        raise HTTPException(400, "Geçersiz sanatçı.")
    try:
        return await cache.load("artist:" + identifier, 86400, lambda: providers.artist(identifier))
    except (ValueError, httpx.HTTPError) as exc:
        raise HTTPException(404, "Sanatçı şu anda yüklenemiyor.") from exc


@app.post("/v1/resolve", response_model=PlaybackAsset)
async def resolve(body: ResolveRequest):
    key = hashlib.sha256((body.track.model_dump_json() + body.provider + body.quality).encode()).hexdigest()
    existing = await cache.get("resolve:" + key)
    if existing and existing["expiresAt"] > time.time() + 120 and await cache.get("asset:" + existing["id"]):
        return existing
    if existing:
        await cache.delete("resolve:" + key)

    async def load():
        track = body.track
        if track.id.startswith("apple:") and not track.duration:
            try:
                rows = await providers.apple_lookup(track.id.split(":")[1])
                if rows and rows[0].get("trackId"):
                    track = apple_track(rows[0])
            except Exception:
                pass
        order = ["saavn", "youtube"] if body.provider == "auto" else [body.provider]
        for source in order:
            try:
                if track.id.startswith(source + ":"):
                    candidates = [track]
                else:
                    query = f"{track.artist} {canonical_title(track.title)}"
                    rows = await (providers.saavn_search(query) if source == "saavn" else providers.youtube_search(query))
                    candidates = sorted((s for s in rows if match_score(track, s) >= .82),
                                        key=lambda s: match_score(track, s), reverse=True)[:2]
                for candidate in candidates:
                    try:
                        stream = await (providers.saavn_stream(candidate.id.split(":")[1], body.quality)
                                        if source == "saavn" else providers.youtube_stream(candidate.id.split(":")[1], body.quality))
                        asset_id = secrets.token_urlsafe(24)
                        expires = time.time() + 1800
                        await cache.set("asset:" + asset_id, {**stream, "provider": source}, 1800)
                        asset = PlaybackAsset(id=asset_id, path="/v1/media/" + asset_id, provider=source,
                                              codec=stream["codec"], bitrate=stream["bitrate"], expiresAt=expires,
                                              duration=stream["duration"] or track.duration)
                        return asset.model_dump()
                    except (ValueError, httpx.HTTPError, asyncio.TimeoutError):
                        continue
            except Exception as exc:
                log.warning("provider=%s resolution=%s", source, type(exc).__name__)
        raise HTTPException(422, "Bu kaydın aynı sürümü kaynaklarda çalınamıyor. Başka bir sonuç veya kaynak dene.")
    return await cache.load("resolve:" + key, 1500, load)


@app.api_route("/v1/media/{identifier}", methods=["GET", "HEAD"])
async def media(identifier: str, request: Request):
    if not re.fullmatch(r"[A-Za-z0-9_-]{32}", identifier):
        raise HTTPException(404, "Ses bağlantısı bulunamadı.")
    asset = await cache.get("asset:" + identifier)
    if not asset:
        raise HTTPException(410, "Ses bağlantısı yenilenmeli.")
    headers = dict(asset["headers"])
    byte_range = request.headers.get("range")
    if byte_range:
        if not re.fullmatch(r"bytes=(?:\d+-\d*|-\d+)", byte_range):
            raise HTTPException(416, "Geçersiz aralık.")
        start, end = byte_range[6:].split("-", 1)
        if (start and end and int(start) > int(end)) or (not start and int(end) == 0):
            raise HTTPException(416, "Geçersiz aralık.")
        headers["Range"] = byte_range
    url = asset["url"]
    upstream = None
    try:
        for _ in range(4):
            if not safe_media_url(url):
                raise HTTPException(502, "Geçersiz ses sunucusu.")
            upstream = await client.send(client.build_request(request.method, url, headers=headers), stream=True)
            if upstream.is_redirect:
                location = upstream.headers.get("location", "")
                await upstream.aclose()
                url = urljoin(url, location)
                continue
            break
        else:
            raise HTTPException(502, "Ses sunucusu yönlendirme hatası.")
    except httpx.HTTPError as exc:
        raise HTTPException(502, "Ses bağlantısı kurulamadı.") from exc
    if upstream.status_code not in (200, 206):
        status = upstream.status_code
        await upstream.aclose()
        if status in (403, 404):
            await cache.delete("asset:" + identifier)
        raise HTTPException(416 if status == 416 else 410 if status in (403, 404) else 502, "Ses bağlantısı yenilenmeli.")
    response_headers = {k: upstream.headers[k] for k in ("content-length", "content-range", "accept-ranges", "content-type", "etag", "last-modified") if k in upstream.headers}
    response_headers["Cache-Control"] = "private, max-age=300"
    response_headers.setdefault("Accept-Ranges", "bytes")
    if request.method == "HEAD":
        await upstream.aclose()
        return Response(status_code=upstream.status_code, headers=response_headers)
    async def chunks():
        try:
            async for chunk in upstream.aiter_raw(128 * 1024):
                yield chunk
        finally:
            await upstream.aclose()
    return StreamingResponse(chunks(), status_code=upstream.status_code, headers=response_headers)


lyrics_lock = asyncio.Lock()
lyrics_last = 0.0


@app.post("/v1/lyrics")
async def lyrics(track: Track):
    async def load():
        global lyrics_last
        async with lyrics_lock:
            await asyncio.sleep(max(0, .3 - (time.monotonic() - lyrics_last)))
            params = {"track_name": re.sub(r'[\(\[]\s*from\b.*?[\)\]]', '', track.title, flags=re.I).strip(), "artist_name": track.artist}
            if track.album:
                params["album_name"] = track.album
            if track.duration:
                params["duration"] = str(round(track.duration))
            r = await client.get("https://lrclib.net/api/get", params=params,
                                 headers={"User-Agent": os.getenv("LRCLIB_USER_AGENT", "KlyMusic/1.0 (http://localhost:8787/docs)")})
            lyrics_last = time.monotonic()
            if r.status_code == 429:
                raise HTTPException(429, "Şarkı sözleri kaynağı meşgul.", headers={"Retry-After": r.headers.get("Retry-After", "30")})
        if r.status_code == 404:
            return {"plain": None, "synced": None, "instrumental": False}
        r.raise_for_status()
        data = r.json()
        return {"plain": data.get("plainLyrics"), "synced": data.get("syncedLyrics"), "instrumental": data.get("instrumental", False)}
    try:
        return await cache.load("lyrics:" + hashlib.sha256(track.model_dump_json().encode()).hexdigest(), 86400, load)
    except httpx.HTTPError:
        raise HTTPException(503, "Şarkı sözleri şu anda yüklenemiyor.")
