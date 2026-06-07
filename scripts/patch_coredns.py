import re, sys

nginx_ip = sys.argv[1]
nip_domain = sys.argv[2]

content = open('/tmp/corefile.txt').read()

# Remove any existing nip.io hosts block
content = re.sub(
    r'[ \t]*hosts \{[^}]*nip\.io[^}]*\}\n',
    '',
    content,
    flags=re.DOTALL,
)

# Insert fresh hosts block before the forward directive
block = (
    '    hosts {\n'
    '        ' + nginx_ip + ' ' + nip_domain + '\n'
    '        fallthrough\n'
    '    }\n'
    '    forward '
)
content = content.replace('    forward ', block, 1)

open('/tmp/corefile_new.txt', 'w').write(content)
