'use client';

import { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '../lib/supabase';
import { api } from '../lib/api';

/**
 * Wraps the whole app: shows a login form until there is a session, then checks
 * that the account is actually an admin (the DB enforces this anyway — this is
 * just so the UI can say something useful instead of erroring on every call).
 */
export default function AuthGate({ children }) {
  const [session, setSession] = useState(undefined); // undefined = still loading
  const [me, setMe] = useState(null);
  const [checking, setChecking] = useState(false);
  const [fatal, setFatal] = useState(null);

  useEffect(() => {
    let done = false;
    const settle = (s) => { done = true; setSession(s ?? null); };

    // Without the catch a rejected getSession() would leave the UI stuck on
    // "Ładowanie…" forever, with no clue why.
    supabase.auth
      .getSession()
      .then(({ data, error }) => {
        if (error) setFatal(error.message);
        settle(data?.session);
      })
      .catch((e) => { setFatal(e?.message || String(e)); settle(null); });

    // Belt and braces: never hang. If auth is unreachable, fall through to the
    // login form rather than an infinite spinner.
    const t = setTimeout(() => {
      if (!done) {
        setFatal('Brak odpowiedzi z Supabase (timeout). Sprawdź połączenie i adres w admin/.env.local.');
        settle(null);
      }
    }, 8000);

    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => settle(s));
    return () => { clearTimeout(t); sub.subscription.unsubscribe(); };
  }, []);

  useEffect(() => {
    if (!session) { setMe(null); return; }
    let cancelled = false;
    (async () => {
      setChecking(true);
      try {
        // Pre-authorised by email? Claim it on first sign-in.
        await api.claimInvite().catch(() => {});
        const info = await api.me();
        if (!cancelled) setMe(info);
      } catch {
        if (!cancelled) setMe({ is_admin: false, role: null });
      } finally {
        if (!cancelled) setChecking(false);
      }
    })();
    return () => { cancelled = true; };
  }, [session]);

  if (session === undefined) return <div className="spin">Ładowanie…</div>;
  if (!session) return <Login fatal={fatal} />;
  if (checking || !me) return <div className="spin">Sprawdzanie uprawnień…</div>;
  if (!me.is_admin) return <NoAccess email={session.user.email} />;

  return (
    <>
      <Nav email={session.user.email} role={me.role} />
      <div className="wrap">{children}</div>
    </>
  );
}

function Nav({ email, role }) {
  const path = usePathname();
  const is = (p) => (path === p ? 'active' : '');
  return (
    <nav className="nav">
      <div className="brand">Debatly<span>.</span>admin</div>
      <Link href="/" className={is('/')}>Pytania</Link>
      <Link href="/drafts" className={is('/drafts')}>Do zatwierdzenia</Link>
      <Link href="/q/new" className={is('/q/new')}>+ Nowe pytanie</Link>
      <div className="spacer" />
      <span className="who">{email} · {role}</span>
      <button className="btn sm ghost" onClick={() => supabase.auth.signOut()}>Wyloguj</button>
    </nav>
  );
}

function NoAccess({ email }) {
  return (
    <div className="center">
      <div className="card login">
        <h3>Brak dostępu</h3>
        <p className="muted">
          Konto <b>{email}</b> nie ma uprawnień administratora.
        </p>
        <p className="faint">
          Jeśli dostałeś zaproszenie — potwierdź najpierw adres e-mail, potem zaloguj się ponownie.
        </p>
        <button className="btn" onClick={() => supabase.auth.signOut()}>Wyloguj</button>
      </div>
    </div>
  );
}

function Login({ fatal }) {
  const [mode, setMode] = useState('link');   // 'link' = passwordless, 'password'
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [err, setErr] = useState(null);
  const [info, setInfo] = useState(null);
  const [busy, setBusy] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setBusy(true); setErr(null); setInfo(null);

    if (mode === 'password') {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) setErr(error.message);
    } else {
      // Passwordless: Supabase mails a one-time link that lands back here.
      const { error } = await supabase.auth.signInWithOtp({
        email,
        options: { emailRedirectTo: window.location.origin },
      });
      if (error) setErr(error.message);
      else setInfo(`Wysłaliśmy link na ${email}. Otwórz go na tym komputerze — zalogujesz się bez hasła.`);
    }
    setBusy(false);
  }

  async function resetPassword() {
    if (!email) { setErr('Podaj najpierw adres e-mail.'); return; }
    setBusy(true); setErr(null); setInfo(null);
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: window.location.origin,
    });
    if (error) setErr(error.message);
    else setInfo(`Wysłaliśmy link do ustawienia hasła na ${email}.`);
    setBusy(false);
  }

  return (
    <div className="center">
      <form className="card login" onSubmit={submit}>
        <h3>Debatly — panel treści</h3>

        <div className="toolbar" style={{ marginBottom: 16 }}>
          <button type="button" className={`btn sm ${mode === 'link' ? 'primary' : ''}`}
                  onClick={() => { setMode('link'); setErr(null); setInfo(null); }}>
            Link e-mail
          </button>
          <button type="button" className={`btn sm ${mode === 'password' ? 'primary' : ''}`}
                  onClick={() => { setMode('password'); setErr(null); setInfo(null); }}>
            Hasło
          </button>
        </div>

        {fatal && (
          <div className="alert err">
            <b>Problem z połączeniem:</b> {fatal}
          </div>
        )}
        {err && <div className="alert err">{err}</div>}
        {info && <div className="alert ok">{info}</div>}

        <label className="field">
          <span>E-mail</span>
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)}
                 autoComplete="username" required />
        </label>

        {mode === 'password' && (
          <label className="field">
            <span>Hasło</span>
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)}
                   autoComplete="current-password" required />
          </label>
        )}

        <button className="btn primary" style={{ width: '100%' }} disabled={busy}>
          {busy ? 'Chwileczkę…' : mode === 'link' ? 'Wyślij link logujący' : 'Zaloguj'}
        </button>

        {mode === 'password' && (
          <button type="button" className="btn ghost sm" style={{ width: '100%', marginTop: 10 }}
                  onClick={resetPassword} disabled={busy}>
            Nie mam hasła / nie pamiętam — wyślij link do ustawienia
          </button>
        )}

        <p className="faint" style={{ marginTop: 14, marginBottom: 0 }}>
          Konta zakładane przez „Invite user” nie mają hasła, które znasz —
          użyj logowania linkiem albo ustaw hasło powyżej.
        </p>
      </form>
    </div>
  );
}
