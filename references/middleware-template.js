// Password is read from Cloudflare Secret (env.PAGE_PASSWORD), not hardcoded
const COOKIE_NAME = 'auth_token';
const AUTH_MAX_AGE = 86400; // 24h

async function sha256(str) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(str));
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
}

const LOGIN_HTML = `<!DOCTYPE html>
<html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Login</title>
<style>
body{font-family:-apple-system,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;background:#f5f5f5;margin:0}
.box{background:#fff;padding:40px;border-radius:12px;box-shadow:0 1px 3px rgba(0,0,0,.08);text-align:center;max-width:360px;width:90%}
h2{margin:0 0 24px;color:#1a1a1a}
input{width:100%;padding:12px;border:1px solid #ddd;border-radius:8px;font-size:16px;box-sizing:border-box}
input:focus{outline:none;border-color:#f0c040}
button{margin-top:16px;width:100%;padding:12px;background:#333;color:#fff;border:none;border-radius:8px;font-size:16px;cursor:pointer}
button:hover{background:#555}
.err{color:#e74c3c;margin-top:12px;font-size:14px;display:none}
</style></head><body>
<div class="box"><h2><svg style="display:inline-block;vertical-align:middle;width:24px;height:24px;margin-right:8px" viewBox="0 0 24 24" fill="none" stroke="#1a1a1a" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>Password Required</h2>
<form method="POST" action="/login"><input name="password" type="password" placeholder="Enter password" autofocus>
<button type="submit">Enter</button></form>
<p class="err" id="err">Wrong password</p>
</div>
<script>if(location.search.includes('error'))document.getElementById('err').style.display='block'</script>
</body></html>`;

export async function onRequest(context) {
  const { request, next, env } = context;
  const url = new URL(request.url);

  const PASSWORD = env.PAGE_PASSWORD;
  const SECRET = env.PAGE_SECRET;
  if (!PASSWORD || !SECRET) {
    return new Response('Server misconfigured: missing PAGE_PASSWORD or PAGE_SECRET secret', { status: 500 });
  }

  // API routes go straight through (after auth check)
  if (url.pathname.startsWith('/api/')) {
    const cookie = request.headers.get('Cookie') || '';
    const token = cookie.split(';').map(c => c.trim()).find(c => c.startsWith(COOKIE_NAME + '='));
    const expectedToken = await sha256(SECRET + PASSWORD);
    if (!token || token.split('=')[1] !== expectedToken) {
      return new Response('Unauthorized', { status: 401 });
    }
    return next();
  }

  // Login POST
  if (url.pathname === '/login' && request.method === 'POST') {
    const form = await request.formData();
    const pwd = form.get('password');
    if (pwd === PASSWORD) {
      const authToken = await sha256(SECRET + PASSWORD);
      return new Response(null, {
        status: 302,
        headers: {
          'Location': '/',
          'Set-Cookie': `${COOKIE_NAME}=${authToken}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${AUTH_MAX_AGE}`
        }
      });
    }
    return new Response(null, { status: 302, headers: { 'Location': '/login?error=1' } });
  }

  // Login page
  if (url.pathname === '/login') {
    return new Response(LOGIN_HTML, { headers: { 'Content-Type': 'text/html' } });
  }

  // Auth check
  const cookie = request.headers.get('Cookie') || '';
  const token = cookie.split(';').map(c => c.trim()).find(c => c.startsWith(COOKIE_NAME + '='));
  const expectedToken = await sha256(SECRET + PASSWORD);
  if (!token || token.split('=')[1] !== expectedToken) {
    return new Response(null, { status: 302, headers: { 'Location': '/login' } });
  }

  return next();
}
