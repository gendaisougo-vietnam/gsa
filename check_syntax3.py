import re, sys
try:
    import esprima
except ImportError:
    import subprocess, sys as _sys
    subprocess.check_call([_sys.executable, '-m', 'pip', 'install', 'esprima', '-q'])
    import esprima

with open('index.html', encoding='utf-8') as f:
    html = f.read()

scripts = re.findall(r'<script(?:[^>]*)>(.*?)</script>', html, re.DOTALL)
js = '\n'.join(scripts)

# Preprocess modern syntax that esprima doesn't support
js = re.sub(r'\?\.\[', '[', js)
js = re.sub(r'\?\.', '.', js)
js = re.sub(r'\?\?=', '=', js)
js = re.sub(r'\?\?', '||', js)
js = re.sub(r'\|\|=', '=', js)
js = re.sub(r'&&=', '=', js)

result = esprima.parseScript(js, tolerant=True)
errors = getattr(result, 'errors', [])
if errors:
    print(f'SYNTAX ERRORS ({len(errors)}):')
    for e in errors:
        print(f'  Line {e.lineNumber}: {e.description}')
    sys.exit(1)
else:
    print('OK - no syntax errors')
