import re, sys, os, shutil, subprocess, tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(SCRIPT_DIR, 'index.html'), encoding='utf-8') as f:
    html = f.read()

scripts = re.findall(r'<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>', html, re.DOTALL)
js = '\n;\n'.join(scripts)

# ── Cách 1: Node.js (chuẩn nhất, hỗ trợ đầy đủ syntax mới) ──
node = shutil.which('node')
if node:
    tmp = tempfile.NamedTemporaryFile('w', suffix='.js', delete=False, encoding='utf-8')
    tmp.write(js)
    tmp.close()
    try:
        r = subprocess.run([node, '--check', tmp.name], capture_output=True, text=True)
    finally:
        os.unlink(tmp.name)
    if r.returncode == 0:
        print('OK - no syntax errors (node --check)')
        sys.exit(0)
    print('SYNTAX ERRORS (node --check):')
    print(r.stderr)
    sys.exit(1)

# ── Cách 2: fallback esprima (máy không có Node) ──
try:
    import esprima
except ImportError:
    try:
        subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'esprima', '-q',
                               '--break-system-packages'])
    except subprocess.CalledProcessError:
        subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'esprima', '-q'])
    import esprima

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
