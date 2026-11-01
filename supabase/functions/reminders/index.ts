// 감사일기 매일 알림 (Supabase Edge Function)
//
//  GET  /reminders?action=vapid   → 알림 구독에 필요한 공개키 (처음 호출 때 자동 생성)
//  POST /reminders  {action:'test'} + 로그인 토큰 → 내 기기로 테스트 알림
//  POST /reminders  {action:'send'} + x-cron-secret → (매분 예약 작업) 시간이 된 기기에 알림
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import webpush from "npm:web-push@3.6.7";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

const MESSAGE = { title: "감사일기", body: "오늘 감사한 것은 뭐가 있었나요?", url: "./?write=today", tag: "daily-gratitude" };
const WINDOW_MINUTES = 30;   // 정한 시각부터 30분 안에만 보냄 (늦게 켠 날 한밤중에 울리지 않게)

type Config = { vapid_public: string; vapid_private: string; cron_secret: string };

async function config(): Promise<Config> {
  const { data, error } = await admin.from("push_config").select("*").eq("id", 1).single();
  if (error) throw error;
  if (data.vapid_public && data.vapid_private) return data as Config;
  const keys = webpush.generateVAPIDKeys();
  const { data: saved, error: e2 } = await admin.from("push_config")
    .update({ vapid_public: keys.publicKey, vapid_private: keys.privateKey })
    .eq("id", 1).is("vapid_public", null).select().maybeSingle();
  if (e2) throw e2;
  if (saved) return saved as Config;
  // 동시에 다른 호출이 먼저 만든 경우
  const { data: again } = await admin.from("push_config").select("*").eq("id", 1).single();
  return again as Config;
}

async function sendTo(cfg: Config, sub: { endpoint: string; p256dh: string; auth: string }, payload = MESSAGE) {
  webpush.setVapidDetails("mailto:noreply@gratitude.app", cfg.vapid_public, cfg.vapid_private);
  try {
    await webpush.sendNotification(
      { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
      JSON.stringify(payload),
      { TTL: 60 * 60, urgency: "high" },
    );
    return "sent";
  } catch (err) {
    const status = (err as { statusCode?: number }).statusCode;
    if (status === 404 || status === 410) {
      // 앱을 지웠거나 알림을 끈 기기 → 구독 정리
      await admin.from("push_subscriptions").delete().eq("endpoint", sub.endpoint);
      return "gone";
    }
    console.error("push failed", status, (err as Error).message);
    return `failed: ${status ?? ""} ${(err as Error).message}`.slice(0, 200);
  }
}

/** 해당 시간대의 오늘 날짜(YYYY-MM-DD)와 지금 시각(분 단위) */
function localNow(tz: string) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23",
    }).formatToParts(new Date()).map((p) => [p.type, p.value]),
  );
  return { date: `${parts.year}-${parts.month}-${parts.day}`, minutes: Number(parts.hour) * 60 + Number(parts.minute) };
}

async function sendDue(cfg: Config) {
  const { data: subs, error } = await admin.from("push_subscriptions").select("*").eq("enabled", true);
  if (error) throw error;
  const result = { checked: subs.length, sent: 0, skipped_written: 0, failures: [] as string[] };

  for (const sub of subs) {
    let now;
    try { now = localNow(sub.tz); } catch { now = localNow("Asia/Seoul"); }
    const [h, m] = String(sub.remind_time).split(":").map(Number);
    const due = h * 60 + m;
    if (sub.last_sent_on === now.date || now.minutes < due || now.minutes - due > WINDOW_MINUTES) continue;

    // 오늘 이미 감사일기를 썼으면 알림 생략
    const { data: written } = await admin.from("entries").select("day")
      .eq("user_id", sub.user_id).eq("day", now.date).eq("deleted", false).limit(1);
    if (!written?.length) {
      const r = await sendTo(cfg, sub);
      if (r === "sent") result.sent++;
      else result.failures.push(r);
    } else {
      result.skipped_written++;
    }
    await admin.from("push_subscriptions").update({ last_sent_on: now.date }).eq("endpoint", sub.endpoint);
  }
  return result;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const url = new URL(req.url);
    const cfg = await config();

    if (req.method === "GET" && url.searchParams.get("action") === "vapid") {
      return json({ publicKey: cfg.vapid_public });
    }

    const body = await req.json().catch(() => ({}));

    if (body.action === "send") {
      if (req.headers.get("x-cron-secret") !== cfg.cron_secret) return json({ error: "forbidden" }, 403);
      return json(await sendDue(cfg));
    }

    if (body.action === "test") {
      const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
      const { data: { user } } = await admin.auth.getUser(token);
      if (!user) return json({ error: "로그인이 필요해요" }, 401);
      const { data: subs } = await admin.from("push_subscriptions").select("*").eq("user_id", user.id);
      if (!subs?.length) return json({ error: "알림이 켜진 기기가 없어요" }, 404);
      const results = [];
      for (const sub of subs) {
        results.push(await sendTo(cfg, sub, { ...MESSAGE, body: "알림이 잘 와요 👍 정한 시간에 이렇게 알려드릴게요.", tag: "test" }));
      }
      return json({ results });
    }

    return json({ error: "unknown action" }, 400);
  } catch (err) {
    console.error(err);
    return json({ error: (err as Error).message }, 500);
  }
});
