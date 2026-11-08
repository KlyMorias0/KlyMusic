from __future__ import annotations

import asyncio
import json
import os
import time
from collections import OrderedDict
from typing import Awaitable, Callable

from redis.asyncio import Redis


class Cache:
    """Bounded development cache; Redis shared cache when configured."""
    def __init__(self, capacity: int = 4000):
        self.items: OrderedDict[str, tuple[float, object]] = OrderedDict()
        self.capacity = capacity
        self.pending: dict[str, asyncio.Task] = {}
        self.redis = Redis.from_url(os.environ["REDIS_URL"], socket_connect_timeout=.5, socket_timeout=.5) if os.getenv("REDIS_URL") else None

    async def get(self, key: str):
        if self.redis:
            try:
                raw = await self.redis.get("kly:" + key)
                return json.loads(raw) if raw else None
            except Exception:
                pass
        item = self.items.get(key)
        if item and item[0] > time.time():
            self.items.move_to_end(key)
            return item[1]
        self.items.pop(key, None)
        return None

    async def set(self, key: str, value, ttl: int):
        if self.redis:
            try:
                await self.redis.setex("kly:" + key, ttl, json.dumps(value))
            except Exception:
                pass
        self.items[key] = (time.time() + ttl, value)
        self.items.move_to_end(key)
        while len(self.items) > self.capacity:
            self.items.popitem(last=False)

    async def delete(self, key: str):
        self.items.pop(key, None)
        if self.redis:
            try:
                await self.redis.delete("kly:" + key)
            except Exception:
                pass

    async def load(self, key: str, ttl: int, loader: Callable[[], Awaitable]):
        cached = await self.get(key)
        if cached is not None:
            return cached
        async def run():
            try:
                value = await loader()
                await self.set(key, value, ttl)
                return value
            finally:
                self.pending.pop(key, None)
        if key not in self.pending:
            self.pending[key] = asyncio.create_task(run())
        return await asyncio.shield(self.pending[key])

    async def close(self):
        for task in list(self.pending.values()):
            task.cancel()
        await asyncio.gather(*list(self.pending.values()), return_exceptions=True)
        if self.redis:
            await self.redis.aclose()
