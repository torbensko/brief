#!/usr/bin/env python3
"""Offline synthetic cleanup evaluation. No microphone or personal history is read."""
import argparse,json,pathlib,subprocess,uuid,select,time
parser=argparse.ArgumentParser()
parser.add_argument('--model',required=True)
parser.add_argument('--worker',default='build/Brief.app/Contents/MacOS/DictationWorker')
args=parser.parse_args()
cases=json.loads(pathlib.Path('Tests/Fixtures/cleanup.json').read_text())
p=subprocess.Popen([args.worker],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,bufsize=1)
failures=0
try:
 for case in cases:
  start=time.monotonic()
  request=dict(id=str(uuid.uuid4()),operation='cleanup',modelDirectory=args.model,text=case['text'],context='Blint, JSON, package.json, useInfiniteQuery',language='English',tokenBudgetMultiplier=1)
  p.stdin.write(json.dumps(request)+'\n');p.stdin.flush()
  deadline=start+90
  while True:
   if not select.select([p.stdout],[],[],max(0,deadline-time.monotonic()))[0]:raise TimeoutError('Cleanup timed out')
   line=p.stdout.readline()
   if not line:raise RuntimeError('Worker exited '+str(p.poll()))
   if line.startswith('LOCALDICTATION:'):break
  response=json.loads(line[len('LOCALDICTATION:'):])
  assert response['success'],response
  result=response['cleanup'];text=result['text']
  passed=all(term in text for term in case.get('contains',[])) and ('expected' not in case or case['expected']==text)
  conservativeFallback=bool(case.get('allowConservativeFallback') and text==case['text'] and result.get('note'))
  passed=passed or conservativeFallback
  failures+=not passed
  print(json.dumps(dict(passed=passed,conservativeFallback=conservativeFallback,seconds=round(time.monotonic()-start,2),input=case['text'],output=text,note=result.get('note')),ensure_ascii=False),flush=True)
finally:
 p.terminate();p.wait(timeout=10)
raise SystemExit(1 if failures else 0)
