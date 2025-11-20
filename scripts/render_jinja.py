#!/usr/bin/env python3
import sys
import os
from jinja2 import Environment, FileSystemLoader, TemplateNotFound

if len(sys.argv) < 3:
    print("Usage: render_jinja.py <template> <out_file> key=val ...", file=sys.stderr)
    sys.exit(1)

template_path, out_file = sys.argv[1:3]
pairs = sys.argv[3:]
ctx = {}
for p in pairs:
    if '=' in p:
        k, v = p.split('=', 1)
        ctx[k] = v

# Determine loader directory and template name
if os.path.isabs(template_path) or os.path.dirname(template_path):
    loader_dir = os.path.dirname(template_path) or '.'
    template_name = os.path.basename(template_path)
else:
    loader_dir = '.'
    template_name = template_path

if not os.path.exists(os.path.join(loader_dir, template_name)):
    print(f"Template not found: {os.path.join(loader_dir, template_name)}", file=sys.stderr)
    sys.exit(2)

env = Environment(loader=FileSystemLoader(loader_dir), keep_trailing_newline=True)

try:
    tmpl = env.get_template(template_name)
except TemplateNotFound:
    print(f"TemplateNotFound: {template_name} (loader_dir={loader_dir})", file=sys.stderr)
    sys.exit(3)

out = tmpl.render(**ctx)

with open(out_file, 'w') as f:
    f.write(out)
