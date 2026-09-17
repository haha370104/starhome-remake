"""Probe exact source references missing from each local alternate-release archive once."""
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT.parent/'cross_release_asset_review'
BASES={'free':'http://update.ftxjjy.com/gameser/fr_www/','jz':'http://update.ftxjjy.com/gameser/jznp_www/'}
MAX_BYTES=64*1024*1024


def probe(task):
    """Fetch only the recorded logical path; validate bytes before caching any response."""
    release,key,source=task
    while source.startswith('../') or source.startswith('./'):source=source.split('/',1)[1]
    source=source.lstrip('/')
    if not source.lower().endswith(Path(key).suffix):source=key
    url=BASES[release]+urllib.parse.quote(source,safe='/')
    result={'release':release,'logical_path':key,'source_reference':source,'url':url}
    try:
        with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'Starhome-source-audit/1.0'}),timeout=10) as response:
            data=response.read(MAX_BYTES+1); result['http_status']=response.status
        if len(data)>MAX_BYTES:raise ValueError('response exceeds 64 MiB limit')
        result.update(bytes=len(data),md5=hashlib.md5(data,usedforsecurity=False).hexdigest(),sha256=hashlib.sha256(data).hexdigest())
        if key.endswith('.ale') and data[:4] not in (b'ALE\0',b'AEX\0',b'RLE0'):
            result['status']='invalid_animation_header';return result
        if not key.endswith('.ale') and data.lstrip()[:1]==b'<':
            result['status']='html_response_not_asset';return result
        target=DEST/'remote_cache'/release/'raw'/key
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
        result.update(status='downloaded',local_path=str(target))
    except urllib.error.HTTPError as error:
        result.update(status='not_found' if error.code==404 else 'http_error',http_status=error.code)
    except Exception as error:
        result.update(status='error',error=str(error))
    return result


def main():
    """Persist all successes and failures; repeat runs never repeat an already-recorded URL."""
    report=json.loads((DEST/'audit.json').read_text('utf-8'))
    path=DEST/'remote_checks.json'
    checks=json.loads(path.read_text('utf-8')) if path.exists() else {}
    tasks=[]
    for row in report['records']:
        if row['glory_now_available']:continue
        for release,found in row['releases'].items():
            identity=release+':'+row['reference']
            if not found['candidates'] and identity not in checks:tasks.append((release,row['reference'],row['source_reference']))
    print('exact-path remote checks',len(tasks),flush=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        for index,future in enumerate(as_completed([pool.submit(probe,t) for t in tasks]),1):
            result=future.result();checks[result['release']+':'+result['logical_path']]=result
            path.write_text(json.dumps(checks,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
            if index%20==0 or result['status']=='downloaded':print(index,result['status'],result['logical_path'],flush=True)
    from collections import Counter
    print('REMOTE_RESULTS',dict(Counter(x['status'] for x in checks.values())),flush=True)
    spec=importlib.util.spec_from_file_location('audit_ale_decoder',ROOT.parent/'fch_decrypt_tool/ale_sprite.py')
    decoder=importlib.util.module_from_spec(spec);sys.modules[spec.name]=decoder;spec.loader.exec_module(decoder)
    for row in checks.values():
        if row['status'] not in ['downloaded','decoded'] or not row['logical_path'].endswith('.ale'):continue
        try:
            target=DEST/'remote_cache'/row['release']/'ale_sprites'/row['logical_path'].removesuffix('.ale')
            if not (target/'frames.json').exists():decoder.build_sheets(decoder.AleFile(Path(row['local_path'])),target,8192)
            row['status']='decoded'
        except Exception as error:row.update(status='decode_error',error=str(error))
    path.write_text(json.dumps(checks,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':main()
