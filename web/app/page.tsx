"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { cities } from "@/lib/cities";
import { mondayOf } from "@/lib/date";
import { supabase } from "@/lib/supabase";
import type { MenuDay, WeekMenu } from "@/lib/types";

type Tab = "menus" | "parents" | "account";
type Message = { id: string; body: string; created_at: string; user_id: string; profiles: { nickname: string } | null };

const db = supabase();
const labels: Record<string, string> = { starter: "Entrée", main: "Plat", side: "Accompagnement", dairy: "Laitage", dessert: "Dessert", other: "Au menu" };

function addDays(date: string, amount: number) {
  return new Date(Date.parse(`${date}T00:00:00Z`) + amount * 86_400_000).toISOString().slice(0, 10);
}

function dateLabel(date: string, long = false) {
  return new Intl.DateTimeFormat("fr-FR", long ? { weekday: "long", day: "numeric", month: "long" } : { day: "numeric", month: "short" }).format(new Date(`${date}T12:00:00Z`));
}

function DayCard({ day }: { day: MenuDay }) {
  const ordered = ["starter", "main", "side", "dairy", "dessert", "other"];
  return <article className="day-card">
    <header><span>{dateLabel(day.date, true)}</span><b>{day.items.length ? `${day.items.length} éléments` : "À venir"}</b></header>
    {day.items.length ? ordered.map((group) => {
      const items = day.items.filter((item) => item.group === group);
      return items.length ? <section className="course" key={group}><small>{labels[group]}</small>{items.map((item) =>
        <div className={`dish ${item.diet}`} key={item.id}><i aria-hidden="true" /> <span>{item.label}</span>{item.diet !== "unknown" && <em>{item.diet === "meat" ? "Viande" : item.diet === "fish" ? "Poisson" : "Végétarien"}</em>}</div>
      )}</section> : null;
    }) : <p className="empty">Le menu n’a pas encore été publié pour cette journée.</p>}
  </article>;
}

function Menus({ city, setCity }: { city: string; setCity: (city: string) => void }) {
  const [week, setWeek] = useState(mondayOf());
  const [level, setLevel] = useState<"elementary" | "nursery">("elementary");
  const [menu, setMenu] = useState<WeekMenu | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    let alive = true;
    setLoading(true); setError("");
    fetch(`/api/menus?city=${city}&week=${week}&level=${level}`).then(async (response) => {
      const value = await response.json();
      if (!response.ok) throw new Error(value.error);
      if (alive) setMenu(value);
    }).catch((reason) => alive && setError(reason.message)).finally(() => alive && setLoading(false));
    return () => { alive = false; };
  }, [city, week, level]);
  const selected = cities.find((item) => item.slug === city)!;
  return <main>
    <section className="hero">
      <p className="eyebrow">La semaine dans l’assiette</p>
      <h1>Qu’est-ce qu’on mange<br /><span>à la cantine&nbsp;?</span></h1>
      <p>Un affichage simple, pensé pour être parcouru avec les enfants.</p>
    </section>
    <section className="controls panel">
      <label>Ma ville<select value={city} onChange={(event) => setCity(event.target.value)}>{cities.map((item) => <option value={item.slug} key={item.slug}>{item.name} · {item.postalCode}</option>)}</select></label>
      {selected.source.kind === "argenteuil-pdf" && <label>École<select value={level} onChange={(event) => setLevel(event.target.value as typeof level)}><option value="elementary">Élémentaire</option><option value="nursery">Maternelle</option></select></label>}
    </section>
    <nav className="week-nav panel" aria-label="Changer de semaine"><button onClick={() => setWeek(addDays(week, -7))}>←</button><div><small>Semaine</small><strong>{dateLabel(week)} — {dateLabel(addDays(week, 4))}</strong></div><button onClick={() => setWeek(addDays(week, 7))}>→</button></nav>
    <div className="legend"><span><i className="red" /> Viande</span><span><i className="green" /> Végétarien ou poisson</span></div>
    {loading ? <div className="status">Les menus arrivent…</div> : error ? <div className="status error">{error}</div> : <>
      <section className="week-grid">{menu?.days.map((day) => <DayCard day={day} key={day.date} />)}</section>
      <p className="source">Source&nbsp;: <a href={menu?.sourceUrl} target="_blank">{menu?.sourceName}</a> · mise à jour {menu && new Date(menu.fetchedAt).toLocaleString("fr-FR")}</p>
    </>}
  </main>;
}

function Auth({ onDone }: { onDone: () => void }) {
  const [create, setCreate] = useState(true);
  const [nickname, setNickname] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [notice, setNotice] = useState("");
  async function submit(event: FormEvent) {
    event.preventDefault(); setNotice("");
    if (!db) return setNotice("La connexion Supabase doit être configurée sur Vercel.");
    const result = create
      ? await db.auth.signUp({ email, password, options: { data: { nickname } } })
      : await db.auth.signInWithPassword({ email, password });
    if (result.error) setNotice(result.error.message);
    else if (create && !result.data.session) setNotice("Compte créé. Confirmez votre adresse dans l’e-mail reçu.");
    else onDone();
  }
  return <form className="auth panel" onSubmit={submit}><h2>{create ? "Créer mon compte" : "Me connecter"}</h2>{create && <label>Pseudo<input value={nickname} onChange={(e) => setNickname(e.target.value)} minLength={2} maxLength={40} required /></label>}<label>Adresse e-mail<input value={email} onChange={(e) => setEmail(e.target.value)} type="email" required /></label><label>Mot de passe<input value={password} onChange={(e) => setPassword(e.target.value)} type="password" minLength={10} required /></label><button className="primary">{create ? "Créer mon compte" : "Me connecter"}</button>{notice && <p>{notice}</p>}<button type="button" className="link" onClick={() => setCreate(!create)}>{create ? "J’ai déjà un compte" : "Créer un compte"}</button></form>;
}

function Parents({ city }: { city: string }) {
  const [userId, setUserId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [draft, setDraft] = useState("");
  const [notice, setNotice] = useState("");
  const load = useCallback(async () => {
    if (!db) return;
    const { data: session } = await db.auth.getSession();
    setUserId(session.session?.user.id ?? null);
    if (!session.session) return;
    const { data, error } = await db.from("messages").select("id,body,created_at,user_id,profiles(nickname)").eq("city_slug", city).eq("topic", "general").order("created_at", { ascending: true }).limit(100);
    if (error) setNotice(error.message); else setMessages((data ?? []) as unknown as Message[]);
  }, [city]);
  useEffect(() => { load(); }, [load]);
  async function send(event: FormEvent) {
    event.preventDefault(); if (!db || !userId || !draft.trim()) return;
    const { error } = await db.from("messages").insert({ user_id: userId, city_slug: city, topic: "general", body: draft.trim() });
    if (error) setNotice(error.message); else { setDraft(""); await load(); }
  }
  if (!userId) return <main><section className="hero compact"><p className="eyebrow">Le coin des parents</p><h1>On en parle<br /><span>ensemble.</span></h1></section><Auth onDone={load} /></main>;
  return <main><section className="hero compact"><p className="eyebrow">Le coin des parents</p><h1>On en parle<br /><span>ensemble.</span></h1><p>La conversation de {cities.find((item) => item.slug === city)?.name}.</p></section><section className="conversation panel">{messages.length ? messages.map((message) => <article key={message.id}><b>{message.profiles?.nickname ?? "Parent"}</b><time>{new Date(message.created_at).toLocaleString("fr-FR")}</time><p>{message.body}</p></article>) : <div className="empty">La conversation commence ici.</div>}<form onSubmit={send}><textarea value={draft} onChange={(e) => setDraft(e.target.value)} maxLength={2000} placeholder="Votre message…" required /><button className="primary">Envoyer</button></form>{notice && <p>{notice}</p>}</section></main>;
}

function Account({ city }: { city: string }) {
  const [email, setEmail] = useState<string | null>(null);
  const [notifications, setNotifications] = useState(false);
  const [inbox, setInbox] = useState<{ id: string; title: string; body: string; created_at: string }[]>([]);
  const refresh = useCallback(async () => { if (db) setEmail((await db.auth.getSession()).data.session?.user.email ?? null); }, []);
  const loadInbox = useCallback(async () => {
    if (!db) return;
    const { data } = await db.from("notifications").select("id,title,body,created_at").is("read_at", null).order("created_at", { ascending: false }).limit(20);
    setInbox(data ?? []);
  }, []);
  useEffect(() => { refresh(); loadInbox(); setNotifications(typeof Notification !== "undefined" && Notification.permission === "granted"); }, [refresh, loadInbox]);
  async function enableNotifications() {
    if (!db || !email) return;
    const permission = await Notification.requestPermission();
    if (permission !== "granted") return;
    const userId = (await db.auth.getUser()).data.user?.id;
    if (userId) await db.from("city_subscriptions").upsert({ user_id: userId, city_slug: city, notify_messages: true, notify_comments: true });
    setNotifications(true);
  }
  if (!email) return <main><section className="hero compact"><p className="eyebrow">Mon espace</p><h1>Votre compte,<br /><span>tout simplement.</span></h1></section><Auth onDone={refresh} /></main>;
  return <main><section className="hero compact"><p className="eyebrow">Mon espace</p><h1>Bonjour&nbsp;!</h1><p>{email}</p></section><section className="settings panel"><h2>Mes préférences</h2><div><span><b>Ma ville</b><small>{cities.find((item) => item.slug === city)?.name}</small></span></div><div><span><b>Notifications</b><small>Commentaires et nouveaux messages</small></span><button onClick={enableNotifications}>{notifications ? "Activées" : "Activer"}</button></div>{inbox.length > 0 && <section className="inbox"><h3>Nouveautés</h3>{inbox.map((item) => <article key={item.id}><b>{item.title}</b><p>{item.body}</p></article>)}<button className="link" onClick={async () => { await db?.from("notifications").update({ read_at: new Date().toISOString() }).is("read_at", null); await loadInbox(); }}>Tout marquer comme lu</button></section>}<button className="link" onClick={async () => { await db?.auth.signOut(); await refresh(); }}>Me déconnecter</button></section></main>;
}

export default function Home() {
  const [tab, setTab] = useState<Tab>("menus");
  const [city, setCity] = useState("montmagny");
  const [unread, setUnread] = useState(0);
  useEffect(() => { const saved = localStorage.getItem("atable-city"); if (saved && cities.some((item) => item.slug === saved)) setCity(saved); }, []);
  useEffect(() => {
    if (!db) return;
    let channel: ReturnType<typeof db.channel> | undefined;
    db.auth.getUser().then(async ({ data }) => {
      if (!data.user) return;
      const { count } = await db.from("notifications").select("id", { count: "exact", head: true }).is("read_at", null);
      setUnread(count ?? 0);
      channel = db.channel(`notifications-${data.user.id}`).on("postgres_changes", { event: "INSERT", schema: "public", table: "notifications", filter: `user_id=eq.${data.user.id}` }, (payload) => {
        const item = payload.new as { title: string; body: string };
        setUnread((value) => value + 1);
        if (typeof Notification !== "undefined" && Notification.permission === "granted") new Notification(item.title, { body: item.body });
      }).subscribe();
    });
    return () => { if (channel) db.removeChannel(channel); };
  }, [tab]);
  const chooseCity = (value: string) => { setCity(value); localStorage.setItem("atable-city", value); };
  const content = useMemo(() => tab === "menus" ? <Menus city={city} setCity={chooseCity} /> : tab === "parents" ? <Parents city={city} /> : <Account city={city} />, [tab, city]);
  return <div className="app"><header className="top"><a className="brand" href="#" onClick={() => setTab("menus")}><span>à</span> table</a><span>{cities.find((item) => item.slug === city)?.name}{unread > 0 && <b className="badge">{unread}</b>}</span></header>{content}<nav className="bottom"><button className={tab === "menus" ? "active" : ""} onClick={() => setTab("menus")}><span>▦</span>Menus</button><button className={tab === "parents" ? "active" : ""} onClick={() => setTab("parents")}><span>◎</span>Parents</button><button className={tab === "account" ? "active" : ""} onClick={() => { setTab("account"); setUnread(0); }}><span>♙</span>Mon espace</button></nav></div>;
}
