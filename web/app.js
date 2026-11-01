// 감사일기 웹앱 (iPhone '홈 화면에 추가'용 PWA)
// - Mac 앱과 같은 Supabase 데이터베이스(entries 테이블)를 씁니다.
// - 오프라인에서도 써지고, 연결되면 자동으로 올라갑니다. (이 기기 저장소 + 보낼 목록)
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

const LOCAL_ONLY = !SUPABASE_URL || !SUPABASE_ANON_KEY;
let supabase = null;
if (!LOCAL_ONLY) {
  const { createClient } = await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm');
  supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  });
}

/* =========================================================
   감정 7단계 (Mac 앱과 같은 색)
   ========================================================= */
const EMOTIONS = {
  1: { label: '아주 불쾌함', color: 'rgb(107,92,214)' },
  2: { label: '불쾌함', color: 'rgb(92,122,224)' },
  3: { label: '약간 불쾌함', color: 'rgb(79,163,217)' },
  4: { label: '보통', color: 'rgb(92,194,181)' },
  5: { label: '약간 기분 좋음', color: 'rgb(168,212,112)' },
  6: { label: '기분 좋음', color: 'rgb(247,199,69)' },
  7: { label: '아주 기분 좋음', color: 'rgb(255,168,33)' },
};
const UNSET_LABEL = '기분 미기록';

/** 감정 얼굴 SVG. level 0 = 미기록(점선 얼굴) */
let faceSeq = 0;
function faceSVG(level, size = 40) {
  const ink = 'rgba(0,0,0,.72)';
  if (!level) {
    return `<svg class="face" width="${size}" height="${size}" viewBox="0 0 100 100" aria-hidden="true">
      <circle cx="50" cy="50" r="46" fill="none" stroke="var(--unset)" stroke-width="5" stroke-dasharray="9 7"/>
      <g fill="var(--unset)"><rect x="30.5" y="32.5" width="8.5" height="15" rx="4.25"/><rect x="61" y="32.5" width="8.5" height="15" rx="4.25"/></g>
      <path d="M30 68 L70 68" stroke="var(--unset)" stroke-width="6.5" stroke-linecap="round"/>
    </svg>`;
  }
  const c = (level - 4) / 3;               // -1(울상) ~ 0(무표정) ~ 1(웃음)
  const gid = `shine-${++faceSeq}`;        // 얼굴마다 고유 id (같은 id가 여러 개면 일부 화면에서 효과가 사라짐)
  // 입: 입꼬리는 살짝만 올리고/내리고, 곡선 깊이도 적당히 → 과장되지 않은 자연스러운 표정
  const half = 18 + 3 * Math.abs(c);       // 입 너비의 절반
  const yEnd = 67 - 6 * c;                 // 입꼬리 높이 (웃으면 올라가고 슬프면 내려감)
  const ctrl = 67 + 14 * c;                // 곡선 조절점 (웃으면 아래로 휘고 슬프면 위로 휨)
  const x1 = 50 - half, x2 = 50 + half;
  const f = (n) => n.toFixed(1);

  let mouth;
  if (level === 7) {
    // 활짝 웃음: 살짝 벌린 입
    mouth = `<path d="M${f(x1)} ${f(yEnd)} Q50 ${f(yEnd + 3)} ${f(x2)} ${f(yEnd)} Q50 ${f(ctrl + 7)} ${f(x1)} ${f(yEnd)}Z"
      fill="${ink}" stroke="${ink}" stroke-width="4" stroke-linejoin="round"/>`;
  } else {
    mouth = `<path d="M${f(x1)} ${f(yEnd)} Q50 ${f(ctrl)} ${f(x2)} ${f(yEnd)}" fill="none" stroke="${ink}" stroke-width="6" stroke-linecap="round"/>`;
  }

  // 눈: 기본은 동그란 눈, 아주 기분 좋으면 웃는 눈(︶ ︶)
  const eyes = level === 7
    ? `<path d="M28.5 43 Q34.75 34 41 43 M59 43 Q65.25 34 71.5 43" fill="none" stroke="${ink}" stroke-width="6" stroke-linecap="round"/>`
    : `<g fill="${ink}"><rect x="30.5" y="33" width="8.5" height="14" rx="4.25"/><rect x="61" y="33" width="8.5" height="14" rx="4.25"/></g>`;

  // 눈썹: 불쾌할수록 안쪽 끝이 올라간 '시무룩한' 눈썹
  const brow = level <= 2
    ? (() => { const t = level === 1 ? 6 : 3.5;
        return `<path d="M26 ${f(26 + t / 2)} L40 ${f(26 - t / 2)} M60 ${f(26 - t / 2)} L74 ${f(26 + t / 2)}" stroke="${ink}" stroke-width="4.5" stroke-linecap="round" opacity=".85"/>`; })()
    : '';

  // 볼터치: 기분 좋을 때만 은은하게
  const blush = level >= 6
    ? `<g fill="#FF7A6B" opacity="${level === 7 ? 0.35 : 0.25}"><ellipse cx="25" cy="58" rx="7" ry="4.5"/><ellipse cx="75" cy="58" rx="7" ry="4.5"/></g>`
    : '';

  return `<svg class="face" width="${size}" height="${size}" viewBox="0 0 100 100" aria-hidden="true">
    <defs><radialGradient id="${gid}" cx="35%" cy="25%" r="70%"><stop offset="0" stop-color="#fff" stop-opacity=".55"/><stop offset=".6" stop-color="#fff" stop-opacity="0"/></radialGradient></defs>
    <circle cx="50" cy="50" r="48" fill="${EMOTIONS[level].color}"/>
    <circle cx="50" cy="50" r="48" fill="url(#${gid})" opacity=".5"/>
    ${blush}${brow}${eyes}${mouth}
  </svg>`;
}

/* =========================================================
   날짜 도우미 ('2026-10-28' 형식의 날짜 키 사용)
   ========================================================= */
const pad = (n) => String(n).padStart(2, '0');
const keyOf = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const dateOf = (key) => { const [y, m, d] = key.split('-').map(Number); return new Date(y, m - 1, d); };
const todayKey = () => keyOf(new Date());
const addDays = (key, n) => { const d = dateOf(key); d.setDate(d.getDate() + n); return keyOf(d); };
const monthOf = (key) => key.slice(0, 7);                     // '2026-10'
const WEEK = ['일', '월', '화', '수', '목', '금', '토'];
const fmtDay = (key) => { const d = dateOf(key); return `${d.getMonth() + 1}월 ${d.getDate()}일 (${WEEK[d.getDay()]})`; };
const fmtDayLong = (key) => `${dateOf(key).getFullYear()}년 ${fmtDay(key)}`;
const relLabel = (key) => {
  const diff = Math.round((dateOf(todayKey()) - dateOf(key)) / 86400000);
  return diff === 0 ? '오늘' : diff === 1 ? '어제' : diff === 2 ? '그저께' : `${diff}일 전`;
};
const fmtTime = (d) => `${d.getHours() < 12 ? '오전' : '오후'} ${((d.getHours() + 11) % 12) + 1}:${pad(d.getMinutes())}`;

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const uid = () => Math.random().toString(36).slice(2, 10);
const $ = (sel, root = document) => root.querySelector(sel);

/* =========================================================
   저장소: 이 기기(localStorage) + 아직 못 보낸 날짜 목록(outbox)
   ========================================================= */
const store = {
  scope: 'local',
  entries: {},          // day -> { day, items[], emotion_level, summary, updated_at, deleted }
  outbox: new Set(),    // 서버에 아직 올리지 못한 날짜

  load(scope) {
    this.scope = scope;
    try {
      this.entries = JSON.parse(localStorage.getItem(`gj:${scope}:entries`) || '{}');
      this.outbox = new Set(JSON.parse(localStorage.getItem(`gj:${scope}:outbox`) || '[]'));
    } catch {
      this.entries = {};
      this.outbox = new Set();
    }
  },
  persist() {
    try {
      localStorage.setItem(`gj:${this.scope}:entries`, JSON.stringify(this.entries));
      localStorage.setItem(`gj:${this.scope}:outbox`, JSON.stringify([...this.outbox]));
    } catch { /* 저장 공간 부족 등 — 화면 상태는 유지 */ }
  },
  get(day) {
    const e = this.entries[day];
    return e && !e.deleted ? e : null;
  },
  put(day, { items, emotion_level, summary }) {
    this.entries[day] = {
      day, items, emotion_level, summary: summary || null,
      updated_at: new Date().toISOString(), deleted: false,
    };
    this.outbox.add(day);
    this.persist();
  },
  remove(day) {
    // 지운 기록도 '삭제됨' 표시로 남겨야 다른 기기에서도 지워집니다
    this.entries[day] = { day, items: [], emotion_level: 0, summary: null, updated_at: new Date().toISOString(), deleted: true };
    this.outbox.add(day);
    this.persist();
  },
};

/* =========================================================
   동기화 (Supabase)
   ========================================================= */
const sync = {
  session: null,
  state: LOCAL_ONLY ? 'local' : 'idle',   // local | idle | busy | offline | error
  lastSync: null,
  error: null,
  running: null,
  channel: null,
};

function setSync(state, error = null) {
  sync.state = state;
  sync.error = error;
  if (state === 'idle') sync.lastSync = new Date();
  renderStatus();
}

/** 동시에 두 번 돌지 않도록 묶어서 실행 */
function runSync(task) {
  if (LOCAL_ONLY || !sync.session) return Promise.resolve();
  const run = async () => {
    if (!navigator.onLine) { setSync('offline'); return; }
    setSync('busy');
    try {
      await task();
      setSync(store.outbox.size ? 'offline' : 'idle');
    } catch (err) {
      console.error(err);
      setSync(navigator.onLine ? 'error' : 'offline', err?.message || String(err));
    }
  };
  sync.running = (sync.running || Promise.resolve()).then(run, run);
  return sync.running;
}

function normalize(row) {
  return {
    day: row.day,
    items: Array.isArray(row.items) ? row.items : [],
    emotion_level: row.emotion_level ?? 0,
    summary: row.summary ?? null,
    updated_at: row.updated_at,
    deleted: !!row.deleted,
  };
}

/** 서버 기록 하나를 이 기기 기록과 비교해 최신 쪽으로 맞춤 (나중에 저장한 쪽이 이김) */
function mergeRemote(row) {
  const local = store.entries[row.day];
  const remoteTime = Date.parse(row.updated_at);
  const localTime = local ? Date.parse(local.updated_at) : -Infinity;
  if (remoteTime > localTime + 500) {
    store.entries[row.day] = normalize(row);
    store.outbox.delete(row.day);
    return true;
  }
  if (localTime > remoteTime + 500) store.outbox.add(row.day);
  return false;
}

async function pull() {
  const { data, error } = await supabase
    .from('entries')
    .select('day,items,emotion_level,summary,updated_at,deleted');
  if (error) throw error;

  const remoteDays = new Set();
  let changed = false;
  for (const row of data) {
    remoteDays.add(row.day);
    if (mergeRemote(row)) changed = true;
  }
  // 서버에 없는 이 기기 기록은 올림
  for (const day of Object.keys(store.entries)) {
    if (!remoteDays.has(day)) store.outbox.add(day);
  }
  store.persist();
  if (changed) render();
  await flush();
}

async function flush() {
  if (!store.outbox.size) return;
  const rows = [...store.outbox]
    .map((day) => store.entries[day])
    .filter(Boolean)
    .map((e) => ({
      user_id: sync.session.user.id,
      day: e.day, items: e.items, emotion_level: e.emotion_level,
      summary: e.summary, updated_at: e.updated_at, deleted: e.deleted,
    }));
  if (!rows.length) { store.outbox.clear(); store.persist(); return; }

  const { error } = await supabase.from('entries').upsert(rows, { onConflict: 'user_id,day' });
  if (error) throw error;

  // 보내는 사이에 또 고친 날짜는 다음 회차에 다시 보냄
  for (const row of rows) {
    if (store.entries[row.day]?.updated_at === row.updated_at) store.outbox.delete(row.day);
  }
  store.persist();
}

function startRealtime() {
  if (sync.channel) supabase.removeChannel(sync.channel);
  sync.channel = supabase
    .channel('entries-changes')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'entries' }, (payload) => {
      if (payload.new?.day && mergeRemote(payload.new)) {
        store.persist();
        render();
      }
    })
    .subscribe();
}

/** 저장 후 바로 서버로 */
function saved() {
  render();
  runSync(flush);
}

/* =========================================================
   화면 상태
   ========================================================= */
const ui = {
  view: 'loading',            // login | home
  month: monthOf(todayKey()), // '2026-10'
  selected: todayKey(),
  loginMode: 'signin',        // signin | signup
  tab: 'calendar',            // calendar | menu   (＋는 바로 작성 화면을 엶)
  distOpen: localStorage.getItem('gj:distOpen') === '1',
  installHintClosed: localStorage.getItem('gj:installHintClosed') === '1',
};
const app = $('#app');

function render() {
  if (ui.view === 'home') renderHome();
}

/* ---------- 로그인 ---------- */
function renderLogin(message = '', isError = false) {
  ui.view = 'login';
  const signup = ui.loginMode === 'signup';
  app.innerHTML = `
    <form class="login" id="login-form" novalidate>
      <img class="logo" src="icons/icon-192.png" alt="" width="84" height="84">
      <h1>감사일기</h1>
      <p class="sub">${signup ? 'iPhone과 Mac에서 같은 계정으로 쓰게 돼요' : 'Mac 앱과 같은 계정으로 로그인하세요'}</p>
      <label class="visually-hidden" for="email">이메일</label>
      <input class="field" id="email" type="email" autocomplete="email" placeholder="이메일" required>
      <label class="visually-hidden" for="password">비밀번호</label>
      <input class="field" id="password" type="password" autocomplete="${signup ? 'new-password' : 'current-password'}"
             placeholder="비밀번호${signup ? ' (6자 이상)' : ''}" minlength="6" required>
      <button class="btn primary block" type="submit">${signup ? '계정 만들기' : '로그인'}</button>
      <button class="btn ghost block" type="button" data-action="toggle-mode">
        ${signup ? '이미 계정이 있어요 · 로그인' : '처음이에요 · 계정 만들기'}
      </button>
      <p class="msg ${isError ? 'error' : ''}" role="status">${esc(message)}</p>
    </form>`;

  $('#login-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = $('#email').value.trim();
    const password = $('#password').value;
    if (!email || password.length < 6) return renderLoginMessage('이메일과 6자 이상의 비밀번호를 입력해 주세요.', true);
    const button = e.submitter || $('#login-form button[type=submit]');
    button.disabled = true;
    try {
      if (ui.loginMode === 'signup') {
        const { data, error } = await supabase.auth.signUp({ email, password });
        if (error) throw error;
        if (data.session) return enterSession(data.session);
        ui.loginMode = 'signin';
        renderLogin('확인 메일을 보냈어요. 메일의 링크를 누른 뒤 로그인해 주세요.');
      } else {
        const { data, error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
        enterSession(data.session);
      }
    } catch (err) {
      renderLoginMessage(friendlyAuthError(err), true);
      button.disabled = false;
    }
  });
}

function renderLoginMessage(text, isError) {
  const el = $('.login .msg');
  if (el) { el.textContent = text; el.classList.toggle('error', isError); }
}

function friendlyAuthError(err) {
  const m = (err?.message || '').toLowerCase();
  if (m.includes('invalid login')) return '이메일 또는 비밀번호가 맞지 않아요.';
  if (m.includes('email not confirmed')) return '메일함의 확인 링크를 먼저 눌러 주세요.';
  if (m.includes('already registered')) return '이미 가입된 이메일이에요. 로그인해 주세요.';
  if (m.includes('fetch') || m.includes('network')) return '인터넷 연결을 확인해 주세요.';
  return err?.message || '문제가 생겼어요. 다시 시도해 주세요.';
}

function enterSession(session) {
  sync.session = session;
  store.load(session.user.id);
  renderHomeShell();
  startRealtime();
  runSync(pull);
}

/* ---------- 홈 ---------- */
// 알림을 눌러 열었으면(?write=today) 바로 오늘 쓰기 화면
let pendingWrite = new URLSearchParams(location.search).has('write');
function renderHomeShell() {
  ui.view = 'home';
  renderHome();
  if (pendingWrite) {
    pendingWrite = false;
    history.replaceState(null, '', location.pathname);
    if (!flow) openFlow(todayKey());
  }
}
// 앱이 이미 열려 있을 때 알림을 누른 경우
navigator.serviceWorker?.addEventListener('message', (e) => {
  if (e.data?.type !== 'write-today') return;
  if (ui.view === 'home') { if (!flow) openFlow(todayKey()); }
  else pendingWrite = true;
});

const isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent);
const isStandalone = () => window.navigator.standalone || matchMedia('(display-mode: standalone)').matches;

/** 홈 = 위쪽 내용 + 아래 탭 바 (캘린더 · ＋ · 메뉴) */
function renderHome() {
  const showInstall = isIOS && !isStandalone() && !ui.installHintClosed;
  const onMenu = ui.tab === 'menu';

  app.innerHTML = `
    <div class="home">
      <header class="topbar">
        <h1>${onMenu ? '메뉴' : '감사일기'}</h1>
        <span class="status js-status"></span>
      </header>
      ${onMenu ? menuHTML() : `
        ${showInstall ? `
          <div class="install-hint">
            <span>📲</span>
            <span>앱처럼 쓰려면 아래 <b>공유</b> 버튼 → <b>홈 화면에 추가</b>를 눌러 주세요.</span>
            <button class="icon-btn" data-action="close-install" aria-label="닫기">×</button>
          </div>` : ''}
        <div class="columns">
          <section class="card" aria-label="달력">${calendarHTML()}</section>
          <section class="card detail" aria-label="선택한 날의 기록">${detailHTML()}</section>
        </div>`}
    </div>
    ${tabbarHTML()}`;
  renderStatus();
  if (!onMenu) {
    bindSwipe();
    $('.dist')?.addEventListener('toggle', (e) => {
      ui.distOpen = e.target.open;
      localStorage.setItem('gj:distOpen', ui.distOpen ? '1' : '0');
    });
  }
}

const ICONS = {
  calendar: `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" aria-hidden="true">
    <rect x="3.5" y="5" width="17" height="15.5" rx="3.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/></svg>`,
  plus: `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true">
    <path d="M12 5v14M5 12h14"/></svg>`,
  menu: `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" aria-hidden="true">
    <path d="M4 7h16M4 12h16M4 17h16"/></svg>`,
};

function tabbarHTML() {
  const tab = (id, label) => `
    <button class="tab ${ui.tab === id ? 'active' : ''}" data-action="tab" data-tab="${id}"
            aria-current="${ui.tab === id ? 'page' : 'false'}">
      ${ICONS[id]}<span>${label}</span>
    </button>`;
  return `
    <nav class="tabbar" aria-label="화면 전환">
      ${tab('calendar', '캘린더')}
      <button class="tab-plus" data-action="write" data-day="${todayKey()}" aria-label="오늘의 감사일기 쓰기">${ICONS.plus}</button>
      ${tab('menu', '메뉴')}
    </nav>`;
}

function statusText() {
  return {
    local: '로컬 모드',
    idle: sync.lastSync ? `동기화됨 · ${fmtTime(sync.lastSync)}` : '동기화 대기',
    busy: '동기화 중…',
    offline: '오프라인 · 연결되면 올라가요',
    error: '동기화 오류',
  }[sync.state];
}

function renderStatus() {
  document.querySelectorAll('.js-status').forEach((el) => {
    el.className = `status js-status ${sync.state === 'busy' ? 'busy' : ''} ${['offline', 'error'].includes(sync.state) ? 'warn' : ''}`;
    el.innerHTML = `<i class="dot"></i>${statusText()}`;
    el.title = sync.error || '';
  });
  document.querySelectorAll('.js-status-text').forEach((el) => { el.textContent = statusText(); });
}

/* ---------- 매일 알림 (웹 푸시) ---------- */
const FN_URL = `${(SUPABASE_URL || '').replace(/\/+$/, '')}/functions/v1/reminders`;
const remind = (() => {
  const saved = (() => { try { return JSON.parse(localStorage.getItem('gj:remind') || '{}'); } catch { return {}; } })();
  return { on: !!saved.on, time: saved.time || '21:00', busy: false };
})();
const saveRemind = () => localStorage.setItem('gj:remind', JSON.stringify({ on: remind.on, time: remind.time }));

/** 'ok' | 'login' | 'install' (iPhone에서 홈 화면 앱이 아님) | 'unsupported' */
function pushSupport() {
  if (LOCAL_ONLY || !sync.session) return 'login';
  if (isIOS && !isStandalone()) return 'install';
  if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) return 'unsupported';
  return 'ok';
}

function base64ToBytes(b64) {
  const s = atob(b64.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (b64.length % 4)) % 4));
  return Uint8Array.from(s, (c) => c.charCodeAt(0));
}

async function saveSubscription(sub) {
  const j = sub.toJSON();
  const { error } = await supabase.from('push_subscriptions').upsert({
    endpoint: j.endpoint, p256dh: j.keys.p256dh, auth: j.keys.auth,
    user_id: sync.session.user.id,
    remind_time: remind.time,
    tz: Intl.DateTimeFormat().resolvedOptions().timeZone || 'Asia/Seoul',
    enabled: true, updated_at: new Date().toISOString(),
  }, { onConflict: 'endpoint' });
  if (error) throw error;
}

async function enableReminder() {
  // 권한 요청은 버튼을 누른 바로 그 순간에 해야 iPhone이 물어봄
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') {
    throw new Error('알림이 허용되지 않았어요. iPhone 설정 ▸ 알림 ▸ 감사일기에서 켜 주세요.');
  }
  const reg = await navigator.serviceWorker.ready;
  let sub = await reg.pushManager.getSubscription();
  if (!sub) {
    const res = await fetch(`${FN_URL}?action=vapid`);
    const { publicKey } = await res.json();
    if (!publicKey) throw new Error('알림 서버에 연결하지 못했어요.');
    sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: base64ToBytes(publicKey) });
  }
  await saveSubscription(sub);
}

async function disableReminder() {
  const reg = await navigator.serviceWorker.ready;
  const sub = await reg.pushManager.getSubscription();
  if (!sub) return;
  await supabase.from('push_subscriptions').delete().eq('endpoint', sub.endpoint);
  await sub.unsubscribe().catch(() => {});
}

async function updateReminderTime() {
  const reg = await navigator.serviceWorker.ready;
  const sub = await reg.pushManager.getSubscription();
  if (sub) await saveSubscription(sub);
}

async function sendTestPush() {
  const { data } = await supabase.auth.getSession();
  const res = await fetch(FN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${data.session?.access_token}` },
    body: JSON.stringify({ action: 'test' }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || '테스트 알림을 보내지 못했어요.');
}

async function onReminderChange(work, okMessage) {
  if (remind.busy) return;
  remind.busy = true;
  renderHome();
  try {
    await work();
    if (okMessage) toast(okMessage);
  } catch (err) {
    console.error(err);
    alert(err.message || '알림 설정 중 문제가 생겼어요.');
  } finally {
    remind.busy = false;
    saveRemind();
    if (ui.tab === 'menu') renderHome();
  }
}

function reminderHTML() {
  const support = pushSupport();
  const notes = {
    login: '로그인하면 알림을 켤 수 있어요.',
    install: 'iPhone에서는 <b>홈 화면에 추가</b>한 감사일기 앱에서만 알림을 받을 수 있어요. 홈 화면 아이콘으로 열어서 켜 주세요.',
    unsupported: '이 브라우저는 알림을 지원하지 않아요. (iPhone은 iOS 16.4 이상, 홈 화면 앱에서 가능)',
  };
  if (support !== 'ok') {
    return `
      <section class="card list">
        <h3 class="menu-title">매일 알림</h3>
        <p class="row-note" style="padding-top:12px;border-top:1px solid var(--line)">${notes[support]}</p>
      </section>`;
  }
  const off = remind.busy ? 'disabled' : '';
  return `
    <section class="card list">
      <h3 class="menu-title">매일 알림</h3>
      <label class="row">
        <span>알림 받기</span>
        <span class="switch"><input type="checkbox" id="remind-on" ${remind.on ? 'checked' : ''} ${off}><i></i></span>
      </label>
      <label class="row ${remind.on ? '' : 'muted'}">
        <span>알림 시간</span>
        <input type="time" id="remind-time" class="time-input" value="${remind.time}" ${off}>
      </label>
      ${remind.on ? `<button class="row link" data-action="test-push" ${off}><span>테스트 알림 보내기</span><span>🔔</span></button>` : ''}
      <p class="row-note" style="padding-top:10px">정한 시간에 <b>“오늘 감사한 것은 뭐가 있었나요?”</b> 알림이 와요. 그날 이미 감사일기를 썼다면 알림은 오지 않아요.</p>
    </section>`;
}

/* ---------- 메뉴 화면 ---------- */
function stats() {
  const list = Object.values(store.entries).filter((e) => !e.deleted);
  const days = new Set(list.map((e) => e.day));
  // 연속 기록: 오늘(아직 안 썼으면 어제)부터 거꾸로 이어진 날 수
  let streak = 0;
  let day = days.has(todayKey()) ? todayKey() : addDays(todayKey(), -1);
  while (days.has(day)) { streak++; day = addDays(day, -1); }
  return {
    days: list.length,
    items: list.reduce((n, e) => n + e.items.length, 0),
    streak,
    month: list.filter((e) => monthOf(e.day) === monthOf(todayKey())).length,
  };
}

function menuHTML() {
  const s = stats();
  const email = sync.session?.user?.email;
  const stat = (value, label) => `<div class="stat"><b>${value}</b><span>${label}</span></div>`;

  return `
    <div class="menu">
      <section class="card">
        <h3 class="menu-title">나의 감사 기록</h3>
        <div class="stats">
          ${stat(`${s.streak}일`, '연속 기록')}
          ${stat(`${s.month}일`, '이번 달')}
          ${stat(`${s.days}일`, '전체 기록')}
          ${stat(`${s.items}개`, '감사한 일')}
        </div>
      </section>

      ${reminderHTML()}

      <section class="card list">
        <h3 class="menu-title">계정 · 동기화</h3>
        ${LOCAL_ONLY ? `
          <div class="row"><span>모드</span><span>로컬 모드 (이 기기에만 저장)</span></div>
          <p class="row-note">config.js에 Supabase 주소와 키를 넣으면 로그인과 iPhone·Mac 동기화가 켜집니다.</p>` : `
          <div class="row"><span>계정</span><span>${esc(email)}</span></div>
          <div class="row"><span>상태</span><span class="js-status-text">${statusText()}</span></div>
          <div class="row"><span>아직 못 보낸 기록</span><span>${store.outbox.size}개</span></div>
          <button class="row link" data-action="sync"><span>지금 동기화</span><span>↻</span></button>`}
      </section>

      <section class="card list">
        <h3 class="menu-title">도움말</h3>
        <details class="row-details">
          <summary><span>홈 화면에 앱으로 추가하기</span><span class="chev">›</span></summary>
          <ol>
            <li>iPhone <b>Safari</b>에서 이 주소를 엽니다.</li>
            <li>아래 <b>공유 버튼(□↑)</b> → <b>홈 화면에 추가</b>.</li>
            <li>홈 화면의 노란 스마일 아이콘으로 열면 앱처럼 전체 화면으로 실행돼요.</li>
          </ol>
        </details>
        <details class="row-details">
          <summary><span>감사일기 쓰는 법</span><span class="chev">›</span></summary>
          <ol>
            <li>가운데 <b>＋</b>를 누르고 감사한 일을 하나 적은 뒤 <b>더 적기</b>.</li>
            <li>다 적었으면 <b>그만 적기</b> → 오늘의 기분과 한 줄 총평 → <b>저장</b>.</li>
            <li>위쪽 날짜를 누르면 지난 날짜의 일기도 쓸 수 있어요.</li>
            <li>중간에 닫아도 적은 내용은 자동 저장돼요.</li>
          </ol>
        </details>
        <details class="row-details">
          <summary><span>Mac 앱과 함께 쓰기</span><span class="chev">›</span></summary>
          <ol>
            <li>Mac 앱 설정(⌘,) ▸ 동기화에서 같은 이메일로 로그인하면 기록이 함께 보여요.</li>
            <li>Mac에서는 어떤 앱을 쓰다가도 <b>⌘⇧G</b>로 바로 적을 수 있어요.</li>
          </ol>
        </details>
      </section>

      <section class="card list">
        <h3 class="menu-title">데이터</h3>
        <button class="row link" data-action="export"><span>기록 내보내기 (JSON 파일)</span><span>↓</span></button>
        <div class="row"><span>버전</span><span>1.4</span></div>
      </section>

      ${LOCAL_ONLY ? '' : '<button class="btn danger block logout" data-action="logout">로그아웃</button>'}
    </div>`;
}

function exportEntries() {
  const list = Object.values(store.entries)
    .filter((e) => !e.deleted)
    .sort((a, b) => a.day.localeCompare(b.day))
    .map(({ day, items, emotion_level, summary }) => ({
      day, items, emotion: emotion_level ? EMOTIONS[emotion_level].label : UNSET_LABEL, emotion_level, summary,
    }));
  const blob = new Blob([JSON.stringify(list, null, 2)], { type: 'application/json' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = `감사일기-${todayKey()}.json`;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(link.href), 1000);
}

function calendarHTML() {
  const [y, m] = ui.month.split('-').map(Number);
  const first = new Date(y, m - 1, 1);
  const daysInMonth = new Date(y, m, 0).getDate();
  const today = todayKey();
  const isCurrentMonth = ui.month === monthOf(today);

  let cells = '';
  for (let i = 0; i < first.getDay(); i++) cells += '<span></span>';
  for (let d = 1; d <= daysInMonth; d++) {
    const key = `${ui.month}-${pad(d)}`;
    const entry = store.get(key);
    const level = entry?.emotion_level || 0;
    const bg = entry ? (level ? EMOTIONS[level].color : 'var(--unset)') : 'transparent';
    const cls = ['day', entry && 'has', key === today && 'today', key === ui.selected && 'selected'].filter(Boolean).join(' ');
    const label = `${m}월 ${d}일, ${entry ? (level ? EMOTIONS[level].label : UNSET_LABEL) : '기록 없음'}`;
    cells += `<button class="${cls}" data-action="select" data-day="${key}" ${key > today ? 'disabled' : ''} aria-label="${label}">
      <span class="circle" style="background:${bg}">${d}</span></button>`;
  }

  return `
    <div class="cal-head">
      <h2>${y}년 ${m}월</h2>
      ${isCurrentMonth ? '' : '<button class="btn ghost" data-action="go-today">오늘</button>'}
      <button class="icon-btn" data-action="month" data-delta="-1" aria-label="이전 달">‹</button>
      <button class="icon-btn" data-action="month" data-delta="1" aria-label="다음 달" ${isCurrentMonth ? 'disabled' : ''}>›</button>
    </div>
    <div class="cal-week">${WEEK.map((w, i) => `<span class="${i === 0 ? 'sun' : i === 6 ? 'sat' : ''}">${w}</span>`).join('')}</div>
    <div class="cal-grid" id="cal-grid">${cells}</div>
    ${distributionHTML()}`;
}

/** 이 달의 감정 분포 */
function distributionHTML() {
  const days = Object.values(store.entries).filter((e) => !e.deleted && monthOf(e.day) === ui.month);
  const total = days.length;
  const counts = {};
  for (const e of days) counts[e.emotion_level || 0] = (counts[e.emotion_level || 0] || 0) + 1;

  const row = (icon, label, color, count) => `
    <div class="dist-row ${count ? '' : 'zero'}" aria-label="${label} ${count}일">
      ${icon}<span>${label}</span>
      <span class="bar">${count ? `<i style="width:${(count / total) * 100}%;background:${color}"></i>` : ''}</span>
      <span class="count">${count}일</span>
    </div>`;

  let body = '<p class="empty-note">이 달에는 아직 기록이 없어요</p>';
  let mini = '';
  if (total) {
    body = [7, 6, 5, 4, 3, 2, 1].map((lv) => row(faceSVG(lv, 18), EMOTIONS[lv].label, EMOTIONS[lv].color, counts[lv] || 0)).join('');
    if (counts[0]) body += row(faceSVG(0, 18), UNSET_LABEL, 'var(--unset)', counts[0]);
    // 접혀 있을 때 보이는 한 줄 요약 막대 (기분 좋은 순)
    mini = [7, 6, 5, 4, 3, 2, 1, 0]
      .filter((lv) => counts[lv])
      .map((lv) => `<i style="flex:${counts[lv]};background:${lv ? EMOTIONS[lv].color : 'var(--unset)'}"></i>`)
      .join('');
  }
  // <details>: 눌러서 접고 펼치기 (상태는 기억됨)
  return `
    <details class="dist" ${ui.distOpen ? 'open' : ''}>
      <summary>
        <span class="dist-title">이 달의 감정</span>
        ${mini ? `<span class="dist-mini" aria-hidden="true">${mini}</span>` : '<span class="dist-mini empty"></span>'}
        <span class="dist-count">${total}일</span>
        <span class="chev" aria-hidden="true">›</span>
      </summary>
      <div class="dist-body">${body}</div>
    </details>`;
}

function detailHTML() {
  const day = ui.selected;
  const entry = store.get(day);
  const future = day > todayKey();

  if (!entry) {
    return `
      <h2>${fmtDayLong(day)}</h2>
      <p class="empty-note" style="margin-bottom:14px">${future ? '아직 오지 않은 날이에요.' : '이 날의 감사일기가 없어요.'}</p>
      ${future ? '' : `<button class="btn primary" data-action="write" data-day="${day}">＋ ${day === todayKey() ? '오늘의' : '이 날'} 감사일기 쓰기</button>`}`;
  }

  const level = entry.emotion_level;
  return `
    <h2>${fmtDayLong(day)}</h2>
    <div class="mood-line">
      ${faceSVG(level, 48)}
      <div>
        <div class="label">${level ? EMOTIONS[level].label : UNSET_LABEL}</div>
        ${entry.summary ? `<div class="summary">${esc(entry.summary)}</div>` : ''}
        ${level ? '' : '<div class="summary" style="font-size:13px">[수정 · 더 적기]에서 그날의 기분을 남길 수 있어요</div>'}
      </div>
    </div>
    <p class="items-title">감사한 일 ${entry.items.length}가지</p>
    <ol class="item-list">
      ${entry.items.map((t, i) => `<li><span class="badge">${i + 1}</span><span class="text">${esc(t)}</span></li>`).join('')}
    </ol>
    <div class="detail-actions">
      <button class="btn secondary" data-action="write" data-day="${day}">✏️ 수정 · 더 적기</button>
      <button class="btn danger" data-action="delete" data-day="${day}">삭제</button>
    </div>`;
}

function bindSwipe() {
  const grid = $('#cal-grid');
  if (!grid) return;
  let startX = 0, startY = 0;
  grid.addEventListener('touchstart', (e) => { startX = e.touches[0].clientX; startY = e.touches[0].clientY; }, { passive: true });
  grid.addEventListener('touchend', (e) => {
    const dx = e.changedTouches[0].clientX - startX;
    const dy = e.changedTouches[0].clientY - startY;
    if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.5) moveMonth(dx < 0 ? 1 : -1);
  }, { passive: true });
}

function moveMonth(delta) {
  const [y, m] = ui.month.split('-').map(Number);
  const next = monthOf(keyOf(new Date(y, m - 1 + delta, 1)));
  if (next > monthOf(todayKey())) return;
  ui.month = next;
  renderHome();
}

function selectDay(day) {
  ui.selected = day;
  ui.month = monthOf(day);
  renderHome();
}

function toast(text) {
  document.querySelector('.toast')?.remove();
  const el = document.createElement('div');
  el.className = 'toast';
  el.textContent = text;
  document.body.append(el);
  setTimeout(() => el.remove(), 1800);
}

/* 홈 화면 버튼들 (이벤트 위임) */
app.addEventListener('click', (e) => {
  const target = e.target.closest('[data-action]');
  if (!target) return;
  const { action, day, delta } = target.dataset;
  switch (action) {
    case 'toggle-mode':
      ui.loginMode = ui.loginMode === 'signin' ? 'signup' : 'signin';
      renderLogin();
      break;
    case 'select': selectDay(day); break;
    case 'month': moveMonth(Number(delta)); break;
    case 'go-today': selectDay(todayKey()); break;
    case 'write': openFlow(day); break;
    case 'delete':
      if (confirm(`${fmtDay(day)}의 감사일기를 삭제할까요?\n삭제하면 되돌릴 수 없어요.`)) {
        store.remove(day);
        saved();
        toast('삭제했어요');
      }
      break;
    case 'tab':
      if (ui.tab !== target.dataset.tab) {
        ui.tab = target.dataset.tab;
        renderHome();
        window.scrollTo(0, 0);
      }
      break;
    case 'sync':
      runSync(pull).then(() => { if (ui.tab === 'menu') renderHome(); toast('동기화했어요'); });
      break;
    case 'export': exportEntries(); break;
    case 'test-push': onReminderChange(sendTestPush, '테스트 알림을 보냈어요. 잠시 후 도착해요'); break;
    case 'logout':
      if (confirm('로그아웃할까요?\n이 기기에 남은 기록은 다음에 로그인하면 다시 보여요.')) {
        runSync(flush).finally(() => supabase.auth.signOut());
      }
      break;
    case 'close-install':
      ui.installHintClosed = true;
      localStorage.setItem('gj:installHintClosed', '1');
      renderHome();
      break;
  }
});

app.addEventListener('change', (e) => {
  if (e.target.id === 'remind-on') {
    const turnOn = e.target.checked;
    onReminderChange(async () => {
      if (turnOn) { await enableReminder(); remind.on = true; }
      else { await disableReminder(); remind.on = false; }
    }, turnOn ? `매일 ${fmtClock(remind.time)}에 알려드릴게요` : '알림을 껐어요');
  } else if (e.target.id === 'remind-time' && e.target.value) {
    remind.time = e.target.value;
    saveRemind();
    if (remind.on) onReminderChange(updateReminderTime, `매일 ${fmtClock(remind.time)}에 알려드릴게요`);
  }
});

function fmtClock(hhmm) {
  const [h, m] = hhmm.split(':').map(Number);
  return `${h < 12 ? '오전' : '오후'} ${((h + 11) % 12) + 1}:${pad(m)}`;
}

/* =========================================================
   작성 흐름: ① 하나씩 적기 → ② 기분 + 한 줄 총평 → 저장
   닫거나 앱을 벗어나면 그때까지 적은 내용 자동 저장
   ========================================================= */
let flow = null;
const SUMMARY_LIMIT = 80;
const EMPTY_SNAPSHOT = JSON.stringify({ items: [], emotion: 0, summary: null });

function cleanItems() {
  return flow.items.map((i) => i.text.replace(/\s*\n\s*/g, ' ').trim()).filter(Boolean);
}
function snapshot() {
  return JSON.stringify({
    items: cleanItems(),
    emotion: flow.emotionChosen ? flow.emotion : 0,
    summary: flow.summary.trim() || null,
  });
}

function openFlow(day) {
  flow = {
    day, items: [], current: '', step: 'items',
    emotion: 4, emotionChosen: false, summary: '', existing: false, saved: EMPTY_SNAPSHOT,
  };
  loadFlowDay(day);

  const sheet = document.createElement('div');
  sheet.className = 'sheet';
  sheet.id = 'flow';
  sheet.setAttribute('role', 'dialog');
  sheet.setAttribute('aria-label', '감사일기 쓰기');
  sheet.innerHTML = '<div class="panel"></div>';
  document.body.append(sheet);
  document.body.classList.add('noscroll');
  bindFlowEvents(sheet);
  renderFlow();
  focusCurrent();
}

/** 날짜를 바꾸면 그 날의 기존 기록을 불러오고, 아직 저장 안 한 새 항목은 따라감 */
function loadFlowDay(day) {
  const carried = flow.items.filter((i) => i.isNew);
  const entry = store.get(day);
  flow.day = day;
  flow.items = (entry?.items || []).map((text) => ({ id: uid(), text, isNew: false }));
  flow.emotion = entry?.emotion_level || 4;
  flow.emotionChosen = !!entry?.emotion_level;
  flow.summary = entry?.summary || '';
  flow.saved = entry ? snapshot() : EMPTY_SNAPSHOT;
  flow.items.push(...carried);
  flow.existing = !!entry;
}

function commitCurrent() {
  const text = flow.current.trim();
  if (!text) return false;
  flow.items.push({ id: uid(), text, isNew: true });
  flow.current = '';
  return true;
}

function saveFlow() {
  const items = cleanItems();
  if (!items.length) return false;
  store.put(flow.day, {
    items,
    emotion_level: flow.emotionChosen ? flow.emotion : 0,
    summary: flow.summary.trim().slice(0, SUMMARY_LIMIT),
  });
  flow.saved = snapshot();
  flow.items.forEach((i) => { i.isNew = false; });
  flow.existing = true;
  saved();
  return true;
}

function autosaveFlow() {
  if (!flow || flow.step === 'done') return;
  commitCurrent();
  if (snapshot() === flow.saved) return;
  if (saveFlow()) {
    toast('적은 내용을 저장했어요');
  } else if (flow.existing && !cleanItems().length) {
    // 이미 있던 기록의 감사한 일을 모두 지웠다면 → 그 날 기록 삭제
    store.remove(flow.day);
    flow.existing = false;
    flow.saved = EMPTY_SNAPSHOT;
    saved();
    toast('이 날의 기록을 지웠어요');
  }
}

function closeFlow({ autosave = true } = {}) {
  if (!flow) return;
  if (autosave) autosaveFlow();
  const day = flow.day;
  flow = null;
  $('#flow')?.remove();
  document.body.classList.remove('noscroll');
  if (store.get(day)) { ui.selected = day; ui.month = monthOf(day); }
  render();
}

function renderFlow() {
  const panel = $('#flow .panel');
  if (!panel || !flow) return;
  const isToday = flow.day === todayKey();

  if (flow.step === 'done') {
    const level = flow.emotionChosen ? flow.emotion : 0;
    panel.innerHTML = `
      <div class="done"><div>
        ${faceSVG(level, 112)}
        <h2>기록했어요</h2>
        <p>감사한 일 ${cleanItems().length}가지 · ${level ? EMOTIONS[level].label : UNSET_LABEL}</p>
      </div></div>`;
    return;
  }

  const top = `
    <div class="sheet-top">
      <button class="btn ghost" data-flow="close">닫기</button>
      <span class="title">감사일기 쓰기</span>
      <span style="width:56px"></span>
    </div>
    <div class="daybar">
      <button class="icon-btn" data-flow="prev-day" aria-label="전날">‹</button>
      <label class="pick">
        <span>📅</span><span>${fmtDay(flow.day)}</span>
        <span class="chip ${isToday ? 'today' : ''}">${relLabel(flow.day)}</span>
        <input type="date" id="day-input" value="${flow.day}" max="${todayKey()}" aria-label="날짜 선택">
      </label>
      <button class="icon-btn" data-flow="next-day" aria-label="다음 날" ${isToday ? 'disabled' : ''}>›</button>
    </div>`;

  if (flow.step === 'items') {
    const hint = flow.existing ? '이 날의 기록에 이어서 적어요 · 닫아도 자동 저장돼요' : '닫아도 지금까지 적은 내용은 자동 저장돼요';
    panel.innerHTML = `${top}
      <div class="step" id="step-scroll">
        <h2>${isToday ? '오늘' : '이 날'} 어떤 일이 감사했나요?</h2>
        <p class="hint">${hint}</p>
        <ol class="write-list">
          ${flow.items.map((item, i) => `
            <li class="write-row" data-id="${item.id}">
              <span class="badge">${i + 1}</span>
              <textarea class="item-text" rows="1" aria-label="감사한 일 ${i + 1}">${esc(item.text)}</textarea>
              <button class="del" data-flow="del" data-id="${item.id}" aria-label="${i + 1}번 지우기">✕</button>
            </li>`).join('')}
          <li class="write-row input">
            <span class="badge pending">${flow.items.length + 1}</span>
            <textarea id="current" rows="1" enterkeyhint="next" aria-label="새 감사한 일"
              placeholder="${flow.items.length ? '또 감사한 일이 있나요?' : '감사한 일 하나를 적어주세요'}">${esc(flow.current)}</textarea>
          </li>
        </ol>
      </div>
      <div class="bar-bottom">
        <button class="btn secondary" data-flow="stop" id="btn-stop">그만 적기</button>
        <button class="btn primary" data-flow="more" id="btn-more">＋ 더 적기</button>
      </div>`;
    panel.querySelectorAll('textarea').forEach(autoGrow);
    updateFlowButtons();
    const scroller = $('#step-scroll');
    scroller.scrollTop = scroller.scrollHeight;
    return;
  }

  // wrap: 기분 + 한 줄 총평
  const items = cleanItems();
  panel.innerHTML = `${top}
    <div class="step">
      <h2>${isToday ? '오늘' : '그날'} 하루는 어땠나요?</h2>
      <div class="mood-pick">
        <span id="mood-face">${faceSVG(flow.emotion, 120)}</span>
        <span class="mood-label" id="mood-label">${EMOTIONS[flow.emotion].label}</span>
      </div>
      <div class="range-wrap">
        <input type="range" class="emotion-range" id="emotion" min="1" max="7" step="1" value="${flow.emotion}"
               aria-label="오늘의 기분" aria-valuetext="${EMOTIONS[flow.emotion].label}"
               style="--thumb:${EMOTIONS[flow.emotion].color}">
        <div class="ticks">${'<i></i>'.repeat(7)}</div>
        <div class="range-ends"><span>아주 불쾌함</span><span>아주 기분 좋음</span></div>
      </div>

      <div class="section-label">한 줄 총평 <span class="chip">선택</span></div>
      <textarea class="summary-box" id="summary" rows="2" maxlength="${SUMMARY_LIMIT}"
        placeholder="예) 동료의 응원 덕분에 버틸 수 있었던 하루">${esc(flow.summary)}</textarea>
      <div class="counter" id="counter">${flow.summary.length}/${SUMMARY_LIMIT}</div>

      <div class="recap">
        <p class="items-title">감사한 일 ${items.length}가지</p>
        <ol class="item-list">${items.map((t, i) => `<li><span class="badge">${i + 1}</span><span class="text">${esc(t)}</span></li>`).join('')}</ol>
      </div>
    </div>
    <div class="bar-bottom">
      <button class="btn secondary" data-flow="back">‹ 감사한 일</button>
      <button class="btn primary" data-flow="save">✓ 저장</button>
    </div>`;
  autoGrow($('#summary'));
}

function autoGrow(el) {
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${el.scrollHeight}px`;
}

function updateFlowButtons() {
  const more = $('#btn-more');
  const stop = $('#btn-stop');
  if (!more || !stop) return;
  const hasText = !!flow.current.trim();
  more.disabled = !hasText;
  stop.disabled = !hasText && cleanItems().length === 0;
}

function focusCurrent() {
  const el = $('#current');
  if (el) { el.focus(); el.setSelectionRange(el.value.length, el.value.length); }
}

function addMore() {
  if (!commitCurrent()) { focusCurrent(); return; }
  renderFlow();
  focusCurrent();
}

function stopWriting() {
  commitCurrent();
  if (!cleanItems().length) return;
  flow.emotionChosen = true;     // 기분 화면을 봤으면 슬라이더 값(기본 '보통')도 선택으로 간주
  flow.step = 'wrap';
  renderFlow();
}

function changeFlowDay(day) {
  if (!day || day > todayKey()) return;
  loadFlowDay(day);
  renderFlow();
}

function bindFlowEvents(sheet) {
  // [더 적기]·[그만 적기]·✕ 를 누를 때 입력칸 포커스가 빠지면 iPhone 키보드가 내려갔다 올라옴 → 막기
  sheet.addEventListener('pointerdown', (e) => {
    if (e.target.closest('[data-flow="more"], [data-flow="del"]')) e.preventDefault();
  });

  sheet.addEventListener('click', (e) => {
    const target = e.target.closest('[data-flow]');
    if (!target || !flow) return;
    switch (target.dataset.flow) {
      case 'close': closeFlow(); break;
      case 'prev-day': changeFlowDay(addDays(flow.day, -1)); break;
      case 'next-day': changeFlowDay(addDays(flow.day, 1)); break;
      case 'more': addMore(); break;
      case 'stop': stopWriting(); break;
      case 'back': flow.step = 'items'; renderFlow(); focusCurrent(); break;
      case 'del':
        flow.items = flow.items.filter((i) => i.id !== target.dataset.id);
        renderFlow();
        break;
      case 'save':
        if (saveFlow()) {
          flow.step = 'done';
          renderFlow();
          setTimeout(() => closeFlow({ autosave: false }), 1100);
        }
        break;
    }
  });

  sheet.addEventListener('input', (e) => {
    if (!flow) return;
    const el = e.target;
    if (el.id === 'current') {
      flow.current = el.value;
      autoGrow(el);
      updateFlowButtons();
    } else if (el.classList.contains('item-text')) {
      const item = flow.items.find((i) => i.id === el.closest('[data-id]').dataset.id);
      if (item) item.text = el.value;
      autoGrow(el);
      updateFlowButtons();
    } else if (el.id === 'summary') {
      flow.summary = el.value.slice(0, SUMMARY_LIMIT);
      $('#counter').textContent = `${flow.summary.length}/${SUMMARY_LIMIT}`;
      autoGrow(el);
    } else if (el.id === 'emotion') {
      flow.emotion = Number(el.value);
      flow.emotionChosen = true;
      const info = EMOTIONS[flow.emotion];
      $('#mood-face').innerHTML = faceSVG(flow.emotion, 120);
      $('#mood-label').textContent = info.label;
      el.style.setProperty('--thumb', info.color);
      el.setAttribute('aria-valuetext', info.label);
    }
  });

  sheet.addEventListener('change', (e) => {
    if (e.target.id === 'day-input') changeFlowDay(e.target.value);
  });

  sheet.addEventListener('keydown', (e) => {
    if (!flow) return;
    // 한글 조합 중 Enter는 무시 (마지막 글자 확정용)
    if (e.isComposing || e.keyCode === 229) return;
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      if (flow.step === 'items') stopWriting();
      else if (flow.step === 'wrap') $('[data-flow="save"]')?.click();
    } else if (e.key === 'Enter' && !e.shiftKey && e.target.id === 'current') {
      e.preventDefault();
      addMore();
    } else if (e.key === 'Escape') {
      closeFlow();
    }
  });
}

/* =========================================================
   iPhone 화면 다듬기
   ========================================================= */
// 핀치 확대 막기 (Safari의 gesture 이벤트) + 두 번 탭 확대 막기
['gesturestart', 'gesturechange', 'gestureend'].forEach((type) =>
  document.addEventListener(type, (e) => e.preventDefault(), { passive: false }));
let lastTouchEnd = 0;
document.addEventListener('touchend', (e) => {
  const now = Date.now();
  if (now - lastTouchEnd < 300 && !e.target.closest('input, textarea')) e.preventDefault();
  lastTouchEnd = now;
}, { passive: false });

// 키보드가 올라오면 보이는 영역(visualViewport)에 맞춰 작성 시트 높이를 줄임
// → 아래 [더 적기]/[그만 적기] 버튼이 키보드에 가려지지 않음
function fitToViewport() {
  const vv = window.visualViewport;
  if (!vv) return;
  const root = document.documentElement.style;
  root.setProperty('--vv-height', `${vv.height}px`);
  root.setProperty('--vv-top', `${vv.offsetTop}px`);
  // 키보드가 올라와 있는 동안은 화면 아래 '홈 막대' 여백이 필요 없음 → 빈 공간 없애기
  document.documentElement.classList.toggle('kb-open', vv.height < window.innerHeight - 120);
  // 키보드가 닫힌 뒤 iPhone이 화면을 밀어 올린 채로 두는 문제 되돌리기
  if (flow && vv.height >= window.innerHeight - 1 && window.scrollY !== 0) window.scrollTo(0, 0);
}
window.visualViewport?.addEventListener('resize', fitToViewport);
window.visualViewport?.addEventListener('scroll', fitToViewport);
fitToViewport();

/* =========================================================
   시작
   ========================================================= */
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') {
    // 앱을 벗어날 때: 쓰던 내용 저장 (시트는 그대로 둠)
    if (flow && flow.step !== 'done') {
      commitCurrent();
      if (snapshot() !== flow.saved) saveFlow();
      renderFlow();
    }
  } else {
    runSync(pull);
    if (ui.view === 'home' && !flow) renderHome();   // 날짜가 바뀌었을 수 있음
  }
});
window.addEventListener('online', () => runSync(pull));
window.addEventListener('offline', () => setSync('offline'));
setInterval(() => { if (document.visibilityState === 'visible') runSync(pull); }, 60_000);

async function boot() {
  if (LOCAL_ONLY) {
    store.load('local');
    renderHomeShell();
    return;
  }
  supabase.auth.onAuthStateChange((event, session) => {
    if (session) sync.session = session;
    if (event === 'SIGNED_OUT') {
      sync.session = null;
      if (sync.channel) supabase.removeChannel(sync.channel);
      sync.channel = null;
      ui.loginMode = 'signin';
      ui.tab = 'calendar';
      renderLogin('로그아웃했어요.');
    }
  });
  const { data } = await supabase.auth.getSession();
  if (data.session) enterSession(data.session);
  else renderLogin();
}

boot();
