import asyncio
import time

import httpx
import pytest
from fastapi.testclient import TestClient

from klymusic import app as module
from klymusic.cache import Cache
from klymusic.models import Track, match_score
from klymusic.providers import safe_media_url, yt_track


@pytest.fixture
def api(monkeypatch):
    monkeypatch.setattr(module, "cache", Cache())
    module.rate_buckets.clear()
    with TestClient(module.app) as client:
        yield client


def song(**changes):
    return Track(**{"id": "apple:123", "title": "Dudu", "artist": "Tarkan", "duration": 278, **changes})


def test_matching_rejects_covers_wrong_artists_and_duration():
    assert match_score(song(), song(id="youtube:abcdefghijk", title="Dudu (Official Audio)")) > .9
    assert match_score(song(), song(title="Dudu (Live)")) == 0
    assert match_score(song(), song(artist="Different Singer")) == 0
    assert match_score(song(), song(duration=190)) == 0
    assert match_score(song(title="Şımarık"), song(title="Simarik")) > .9
    assert match_score(song(title='Kesariya (From "Brahmastra")'), song(title="Kesariya")) > .9
    assert match_score(song(title='Kesariya (From "Brahmastra")'), song(title="Kesariya Remix")) == 0


@pytest.mark.parametrize("url", [
    "http://aac.saavncdn.com/a.mp4", "https://127.0.0.1/a", "https://googlevideo.com.evil.example/a",
    "https://saavncdn.com@evil.example/a", "https://aac.saavncdn.com:4430/a", "file:///etc/passwd"
])
def test_proxy_rejects_arbitrary_hosts(url):
    assert not safe_media_url(url)


def test_proxy_accepts_provider_cdn():
    assert safe_media_url("https://aac.saavncdn.com/a.mp4")
    assert safe_media_url("https://rr1---sn-test.googlevideo.com/videoplayback?x=1")


def test_youtube_duration_and_id_validation():
    track = yt_track({"videoId": "abcdefghijk", "title": "Song", "duration": "4:38", "artists": [{"name": "A"}]})
    assert track.duration == 278
    assert yt_track({"videoId": "../../etc/passwd"}) is None


def test_health_and_invalid_requests(api):
    assert api.get("/health").json()["app"] == "KlyMusic"
    assert api.post("/v1/resolve", json={"track": {"id": "file:///test", "title": "X", "artist": "Y"}}).status_code == 422
    assert api.get("/v1/media/not-an-asset").status_code == 404
    assert api.get("/v1/albums/not-a-number").status_code == 400


def test_fallback_and_resolve_cache(api, monkeypatch):
    calls = []
    async def saavn_search(_):
        return [song(id="saavn:abc", artist="Wrong person")]
    async def youtube_search(_):
        calls.append("youtube-search")
        return [song(id="youtube:abcdefghijk")]
    async def youtube_stream(identifier, quality):
        calls.append("youtube-stream")
        return {"url": "https://rr1.googlevideo.com/test", "headers": {}, "codec": "aac", "bitrate": 128, "duration": 278}
    monkeypatch.setattr(module.providers, "saavn_search", saavn_search)
    monkeypatch.setattr(module.providers, "youtube_search", youtube_search)
    monkeypatch.setattr(module.providers, "youtube_stream", youtube_stream)
    payload = {"track": song().model_dump()}
    first = api.post("/v1/resolve", json=payload)
    assert first.status_code == 200
    assert first.json()["provider"] == "youtube"
    second = api.post("/v1/resolve", json=payload)
    assert second.json()["id"] == first.json()["id"]
    assert calls == ["youtube-search", "youtube-stream"]
    assert "url" not in first.json()
    module.cache.items.pop("asset:" + first.json()["id"])
    refreshed = api.post("/v1/resolve", json=payload)
    assert refreshed.status_code == 200
    assert refreshed.json()["id"] != first.json()["id"]
    assert calls == ["youtube-search", "youtube-stream"] * 2


def test_failed_source_is_reported_without_fake_preview(api, monkeypatch):
    async def missing(_): return []
    monkeypatch.setattr(module.providers, "saavn_search", missing)
    monkeypatch.setattr(module.providers, "youtube_search", missing)
    result = api.post("/v1/resolve", json={"track": song().model_dump()})
    assert result.status_code == 422
    assert "detail" in result.json()


def test_range_media_proxy_and_expiry(api, monkeypatch):
    identifier = "a" * 32
    module.cache.items["asset:" + identifier] = (time.time() + 60, {
        "url": "https://aac.saavncdn.com/test.mp4", "headers": {}, "provider": "saavn"})
    def handler(request):
        assert request.headers["range"] == "bytes=0-3"
        return httpx.Response(206, headers={"Content-Range": "bytes 0-3/100", "Content-Length": "4", "Content-Type": "audio/mp4"}, stream=httpx.ByteStream(b"test"))
    original = module.client
    mock_client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    monkeypatch.setattr(module, "client", mock_client)
    try:
        response = api.get("/v1/media/" + identifier, headers={"Range": "bytes=0-3"})
        assert response.status_code == 206
        assert response.content == b"test"
        assert response.headers["content-range"] == "bytes 0-3/100"
        assert api.get("/v1/media/" + identifier, headers={"Range": "bytes=0-3,5-8"}).status_code == 416
        assert api.get("/v1/media/" + "b" * 32).status_code == 410
    finally:
        monkeypatch.setattr(module, "client", original)
        asyncio.run(mock_client.aclose())


@pytest.mark.asyncio
async def test_cache_coalesces_concurrent_requests_and_recovers_after_failure():
    cache = Cache(capacity=2)
    calls = 0
    async def load():
        nonlocal calls
        calls += 1
        await asyncio.sleep(.01)
        return {"ok": True}
    result = await asyncio.gather(*[cache.load("same", 60, load) for _ in range(10)])
    assert all(row == {"ok": True} for row in result)
    assert calls == 1
    async def fail(): raise ValueError("unavailable")
    with pytest.raises(ValueError): await cache.load("bad", 60, fail)
    assert await cache.load("bad", 60, load) == {"ok": True}
    await cache.set("three", 3, 60)
    assert len(cache.items) == 2
    await cache.close()


def test_turkish_original_version_label_matches_without_accepting_remix():
    from klymusic.models import Track, match_score
    requested = Track(id='apple:499334149', title='Kuzu Kuzu', artist='Tarkan', duration=233.639)
    original = Track(id='youtube:_CgHTNuEUHc', title='Kuzu Kuzu Orijinal Versiyon', artist='Tarkan', duration=234)
    remix = original.model_copy(update={'title': 'Kuzu Kuzu (Remix)'})
    assert match_score(requested, original) >= .98
    assert match_score(requested, remix) == 0


def test_search_recovers_missing_exact_song_and_keeps_relevant_song_first(api, monkeypatch):
    from klymusic.models import SearchResult
    async def primary(_):
        return SearchResult(tracks=[song(title='VUR', artist='BLOK3')])
    async def secondary(_):
        return []
    async def expanded(_):
        return [song(id='youtube:i-E7BYUjn_U', title='AFFETMEM', artist='BLOK3')]
    monkeypatch.setattr(module.providers, 'apple_search_all', primary)
    monkeypatch.setattr(module.providers, 'saavn_search', secondary)
    monkeypatch.setattr(module.providers, 'youtube_search', expanded)
    response = api.get('/v1/search', params={'q': 'BLOK3 AFFETMEM'})
    assert response.status_code == 200
    assert response.json()['tracks'][0]['title'] == 'AFFETMEM'
    assert len(response.json()['tracks']) == 2
