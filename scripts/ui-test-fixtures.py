import http.server, json, io, wave, math, struct, urllib.parse
from pathlib import Path
cover=(Path(__file__).parent/'fixtures'/'cover.jpg').read_bytes()
buf=io.BytesIO()
with wave.open(buf,'wb') as out:
    out.setnchannels(1); out.setsampwidth(2); out.setframerate(8000)
    out.writeframes(b''.join(struct.pack('<h',int(900*math.sin(2*math.pi*220*i/8000))) for i in range(8000*90)))
audio=buf.getvalue()
track={'id':'fixture:lyrics','title':'Gece Yolu','artist':'KlyMusic Test','album':'Arayüz Kontrolü','duration':90,'artwork':'http://127.0.0.1:8879/fixture-cover.jpg','explicit':False,'source':'test','artistID':'9001','albumID':'9002'}
tracks=[track]+[dict(track, id=f'fixture:{key}', title=title) for key,title in [('next','Sabah Işığı'),('third','Bir Adım'),('last','Son Durak')]]

album={'id':'9002','title':'Arayüz Kontrolü','artist':'KlyMusic Test','artwork':track['artwork'],'kind':'album'}
artist={'id':'9001','name':'KlyMusic Test','artwork':track['artwork']}
category_sources=json.loads((Path(__file__).parent/'fixtures'/'category-sources.json').read_text())
category_images={item['file']:(Path(__file__).parent/'fixtures'/item['file']).read_bytes() for item in category_sources.values()}
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_POST(self): self.handle_api()
    def do_GET(self): self.handle_api()
    def do_HEAD(self): self.handle_api()
    def handle_api(self):
        if self.path=='/fixture-cover.jpg' or self.path.startswith('/fixture-category/'):
            picture=category_images.get(self.path.split('/')[-1],cover)
            self.send_response(200); self.send_header('Content-Type','image/jpeg'); self.send_header('Content-Length',len(picture)); self.end_headers()
            if self.command!='HEAD': self.wfile.write(picture)
            return
        request=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0)))) if self.command=='POST' else {}
        if self.path.startswith('/v1/media/'):
            data=audio; status=200; start=0; end=len(data)-1
            if self.headers.get('Range'):
                try:
                    a,b=self.headers['Range'].removeprefix('bytes=').split('-'); start=int(a); end=int(b) if b else end; status=206
                except ValueError: pass
            end=min(end,len(data)-1); body=data[start:end+1]
            self.send_response(status); self.send_header('Content-Type','audio/wav'); self.send_header('Accept-Ranges','bytes')
            if status==206: self.send_header('Content-Range',f'bytes {start}-{end}/{len(data)}')
        else:
            if self.path.startswith('/v1/home'): result={'sections':[{'id':'tr','title':'Türkiye’de şimdi','subtitle':'','tracks':tracks}]}
            elif self.path.startswith('/v1/search'): result={'tracks':tracks,'albums':[album],'artists':[artist],'warnings':[]}
            elif self.path.startswith('/v1/resolve'): result={'id':request.get('track',track)['id'],'path':'v1/media/fixture','provider':'test','codec':'wav','bitrate':128,'expiresAt':9999999999,'duration':90}
            elif self.path.startswith('/v1/category-artwork'):
                query=urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get('query',[''])[0]
                name=category_sources.get(query,{}).get('file','cover.jpg')
                result={'artwork':'http://127.0.0.1:8879/fixture-category/'+name}
            elif self.path.startswith('/v1/albums/'): result={'tracks':tracks}
            elif self.path.startswith('/v1/artists/'): result={'artist':artist,'tracks':tracks,'albums':[album]}
            elif self.path.startswith('/v1/lyrics'): result={'plain':None,'instrumental':False,'synced':'[00:00]Gece yoluna çıkalım\n[00:04]Şehir usulca uyansın\n[00:08]Ritim bizimle kalsın\n[00:16]Yeni bir sabah gelsin\n[00:30]Yolumuz ışığa varsın\n[00:55]Son bir nota duyulsun'}
            else: self.send_error(404); return
            body=json.dumps(result).encode(); self.send_response(200); self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',len(body)); self.end_headers()
        if self.command!='HEAD': self.wfile.write(body)
http.server.ThreadingHTTPServer(('127.0.0.1',8879),Handler).serve_forever()
