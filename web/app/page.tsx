"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { cities, type City } from "@/lib/cities";
import { mondayOf } from "@/lib/date";
import { supabase } from "@/lib/supabase";
import type { MenuDay, WeekMenu } from "@/lib/types";

type Tab = "menus" | "parents" | "account";
type Message = { id: string; body: string; created_at: string; user_id: string; hidden: boolean; profiles: { nickname: string } | null };
type CityLookup = { candidates: City[]; commune: { name: string; postalCode: string } | null; suggestions?: string[]; error?: string; warnings?: string[] };
const db = supabase();
const labels: Record<string, string> = { starter: "Entrée", main: "Plat", side: "Accompagnement", dairy: "Laitage", dessert: "Dessert", other: "Au menu" };

function addDays(date: string, amount: number) { return new Date(Date.parse(`${date}T00:00:00Z`) + amount * 86_400_000).toISOString().slice(0, 10); }
function dateLabel(date: string, long = false) { return new Intl.DateTimeFormat("fr-FR", long ? { weekday: "long", day: "numeric", month: "long" } : { day: "numeric", month: "short" }).format(new Date(`${date}T12:00:00Z`)); }

function Auth({ onDone }: { onDone: () => void }) {
  const [create, setCreate] = useState(true), [nickname, setNickname] = useState(""), [email, setEmail] = useState(""), [password, setPassword] = useState(""), [notice, setNotice] = useState("");
  async function submit(event: FormEvent) {
    event.preventDefault(); setNotice("");
    if (!db) return setNotice("La connexion Supabase doit être configurée sur Vercel.");
    const result = create ? await db.auth.signUp({ email, password, options: { data: { nickname }, emailRedirectTo: location.origin } }) : await db.auth.signInWithPassword({ email, password });
    if (result.error) setNotice(result.error.message); else if (create && !result.data.session) setNotice("Compte créé. Confirmez votre adresse dans l’e-mail reçu."); else onDone();
  }
  return <form className="auth panel" onSubmit={submit}><h2>{create ? "Créer mon compte" : "Me connecter"}</h2>{create && <label>Pseudo<input value={nickname} onChange={e => setNickname(e.target.value)} minLength={2} maxLength={40} required /></label>}<label>Adresse e-mail<input value={email} onChange={e => setEmail(e.target.value)} type="email" required /></label><label>Mot de passe<input value={password} onChange={e => setPassword(e.target.value)} type="password" minLength={10} required /></label><button className="primary">{create ? "Créer mon compte" : "Me connecter"}</button>{notice && <p>{notice}</p>}<button type="button" className="link" onClick={() => setCreate(!create)}>{create ? "J’ai déjà un compte" : "Créer un compte"}</button></form>;
}

function Conversation({ city, topic, compact = false }: { city: string; topic: string; compact?: boolean }) {
  const [userId, setUserId] = useState<string | null>(null), [messages, setMessages] = useState<Message[]>([]), [draft, setDraft] = useState(""), [notice, setNotice] = useState(""), [moderator, setModerator] = useState(false);
  const load = useCallback(async () => {
    if (!db) return;
    const session = (await db.auth.getSession()).data.session; setUserId(session?.user.id ?? null);
    if (!session) return;
    const [{ data, error }, role] = await Promise.all([
      db.from("messages").select("id,body,created_at,user_id,hidden,profiles(nickname)").eq("city_slug", city).eq("topic", topic).order("created_at", { ascending: true }).limit(100),
      db.rpc("is_moderator"),
    ]);
    setModerator(Boolean(role.data)); if (error) setNotice(error.message); else setMessages((data ?? []) as unknown as Message[]);
  }, [city, topic]);
  useEffect(() => { void load(); }, [load]);
  async function send(event: FormEvent) {
    event.preventDefault(); if (!db || !userId || !draft.trim()) return;
    const { error } = await db.from("messages").insert({ user_id: userId, city_slug: city, topic, body: draft.trim() });
    if (error) setNotice(error.message); else { setDraft(""); setNotice(""); await load(); }
  }
  async function moderate(message: Message, action: "hide" | "delete") {
    if (!db) return;
    if (action === "delete" && !window.confirm("Supprimer définitivement ce message ?")) return;
    const query = action === "delete" ? db.from("messages").delete().eq("id", message.id) : db.from("messages").update({ hidden: !message.hidden }).eq("id", message.id);
    const { error } = await query; if (error) setNotice(error.message); else await load();
  }
  if (!userId) return <div className={compact ? "comments-auth" : ""}><p>Connectez-vous pour lire et écrire des messages.</p><Auth onDone={load} /></div>;
  return <section className="conversation">
    {messages.length ? messages.map(message => <article className={message.hidden ? "hidden-message" : ""} key={message.id}><b>{message.profiles?.nickname ?? "Parent"}</b><time>{new Date(message.created_at).toLocaleString("fr-FR")}</time>{message.hidden && <small>Masqué</small>}<p>{message.body}</p><div className="message-actions">{(message.user_id === userId || moderator) && <button className="link danger" onClick={() => moderate(message, "delete")}>Supprimer</button>}{moderator && <button className="link" onClick={() => moderate(message, "hide")}>{message.hidden ? "Rendre visible" : "Masquer"}</button>}</div></article>) : <div className="empty">La conversation commence ici.</div>}
    <form onSubmit={send}><textarea value={draft} onChange={e => setDraft(e.target.value)} maxLength={2000} placeholder={topic.startsWith("menu:") ? "Votre commentaire sur ce menu…" : "Votre message…"} required /><button className="primary">Publier</button></form>{notice && <p className="form-error">{notice}</p>}
  </section>;
}

function DayCard({ day, city }: { day: MenuDay; city: string }) {
  const ordered = ["starter", "main", "side", "dairy", "dessert", "other"], [open, setOpen] = useState(false);
  return <article className="day-card"><header><span>{dateLabel(day.date, true)}</span><b>{day.items.length ? `${day.items.length} éléments` : "À venir"}</b></header>
    {day.items.length ? ordered.map(group => { const items = day.items.filter(item => item.group === group); return items.length ? <section className="course" key={group}><small>{labels[group]}</small>{items.map(item => <div className={`dish ${item.diet}`} key={item.id}><i aria-hidden="true"/><span>{item.label}</span>{item.diet !== "unknown" && <em>{item.diet === "meat" ? "Viande" : item.diet === "fish" ? "Poisson" : "Végétarien"}</em>}</div>)}</section> : null; }) : <p className="empty">Le menu n’a pas encore été publié pour cette journée.</p>}
    <button className="comments-toggle" onClick={() => setOpen(!open)}>{open ? "Fermer les commentaires" : "Commentaires"}</button>{open && <Conversation city={city} topic={`menu:${day.date}`} compact />}
  </article>;
}

function CityFinder({ selected, onSelect }: { selected: City; onSelect: (city: City) => void }) {
  const [name, setName] = useState(selected.name), [postalCode, setPostalCode] = useState(selected.postalCode), [notice, setNotice] = useState(""), [kind, setKind] = useState<"success"|"info"|"error">("info"), [searching, setSearching] = useState(false), [choices, setChoices] = useState<City[]>([]);
  useEffect(() => { setName(selected.name); setPostalCode(selected.postalCode); }, [selected.name, selected.postalCode]);
  async function locate(event: FormEvent) {
    event.preventDefault(); setSearching(true); setNotice(""); setChoices([]);
    try {
      const response = await fetch(`/api/cities/lookup?${new URLSearchParams({ name: name.trim(), postalCode })}`), result = await response.json() as CityLookup;
      if (!response.ok) throw new Error(result.error ?? "La commune n’a pas pu être vérifiée.");
      if (result.candidates.length === 1) { onSelect(result.candidates[0]); setKind("success"); setNotice(`Source officielle trouvée pour ${result.candidates[0].name}.`); }
      else if (result.candidates.length > 1) { setChoices(result.candidates); setKind("info"); setNotice("Plusieurs restaurants scolaires ont été trouvés. Choisissez le vôtre."); }
      else { setKind("info"); const hint = result.suggestions?.length ? ` Essayez : ${result.suggestions.join(", ")}.` : ""; setNotice((result.error ?? `La commune est reconnue, mais aucune source publique exploitable n’a été trouvée.`) + hint); }
    } catch (reason) { setKind("error"); setNotice(reason instanceof Error ? reason.message : "La recherche est indisponible."); } finally { setSearching(false); }
  }
  return <section className="location-panel panel"><form className="city-search" onSubmit={locate}><label>Ma ville<input value={name} onChange={e => setName(e.target.value)} list="supported-cities" autoComplete="address-level2" required /></label><datalist id="supported-cities">{cities.map(city => <option value={city.name} key={city.slug}/>)}</datalist><label>Code postal<input value={postalCode} onChange={e => setPostalCode(e.target.value.replace(/\D/g, "").slice(0,5))} inputMode="numeric" pattern="[0-9]{5}" required /></label><button className="primary" disabled={searching}>{searching ? "Recherche des sources…" : "Trouver mes menus"}</button></form>
    <div className="city-shortcuts">{cities.map(city => <button className={city.slug === selected.slug ? "selected" : ""} onClick={() => onSelect(city)} type="button" key={city.slug}>{city.name} · {city.postalCode}</button>)}</div>{choices.length > 0 && <div className="source-choices">{choices.map(city => <button key={city.slug} onClick={() => onSelect(city)}><b>{city.restaurantName ?? city.name}</b><span>Choisir cette cantine</span></button>)}</div>}{notice && <p className={`location-notice ${kind}`} aria-live="polite">{notice}</p>}</section>;
}

function Menus({ city, setCity }: { city: City; setCity: (city: City) => void }) {
  const [week, setWeek] = useState(mondayOf()), [level, setLevel] = useState<"elementary"|"nursery">("elementary"), [menu, setMenu] = useState<WeekMenu|null>(null), [error, setError] = useState(""), [loading, setLoading] = useState(true);
  useEffect(() => { let alive = true; setLoading(true); setError(""); fetch(`/api/menus?city=${encodeURIComponent(city.slug)}&week=${week}&level=${level}`).then(async r => { const value = await r.json(); if (!r.ok) throw new Error(value.error); if (alive) setMenu(value); }).catch(e => alive && setError(e.message)).finally(() => alive && setLoading(false)); return () => { alive = false; }; }, [city.slug, week, level]);
  return <main><section className="hero"><p className="eyebrow">La semaine dans l’assiette</p><h1>Qu’est-ce qu’on mange<br/><span>à la cantine&nbsp;?</span></h1><p>Un affichage simple, pensé pour être parcouru avec les enfants.</p></section><CityFinder selected={city} onSelect={setCity}/>
    {city.source.kind === "argenteuil-pdf" && <section className="school-level panel"><label>École<select value={level} onChange={e => setLevel(e.target.value as typeof level)}><option value="elementary">Élémentaire</option><option value="nursery">Maternelle</option></select></label></section>}
    <nav className="week-nav panel"><button onClick={() => setWeek(addDays(week,-7))}>←</button><div><small>Semaine</small><strong>{dateLabel(week)} — {dateLabel(addDays(week,4))}</strong></div><button onClick={() => setWeek(addDays(week,7))}>→</button></nav><div className="legend"><span><i className="red"/> Viande</span><span><i className="green"/> Végétarien ou poisson</span></div>
    {loading ? <div className="status">Les menus arrivent…</div> : error ? <div className="status error">{error}</div> : <>{menu?.requiresAccount && <section className="provider-notice panel"><h2>Menus disponibles chez le prestataire</h2><p>La mairie utilise Clic et Miam, qui demande un compte pour afficher les menus.</p>{menu.accessCode && <p>Code établissement : <strong>{menu.accessCode}</strong></p>}{menu.documents?.map(link => <a className="primary" href={link.url} target="_blank" rel="noreferrer" key={link.url}>Ouvrir Clic et Miam</a>)}</section>}{menu?.documents?.length && !menu.requiresAccount ? <section className="provider-notice panel"><h2>Documents officiels</h2>{menu.documents.map(link => <a href={link.url} target="_blank" rel="noreferrer" key={link.url}>{link.title}</a>)}</section> : null}<section className="week-grid">{menu?.days.map(day => <DayCard day={day} city={city.slug} key={day.date}/>)}</section><p className="source">Source : <a href={menu?.sourceUrl} target="_blank" rel="noreferrer">{menu?.sourceName}</a> · mise à jour {menu && new Date(menu.fetchedAt).toLocaleString("fr-FR")}</p></>}
  </main>;
}

function Parents({ city }: { city: City }) { return <main><section className="hero compact"><p className="eyebrow">Le coin des parents</p><h1>On en parle<br/><span>ensemble.</span></h1><p>La conversation de {city.name}.</p></section><section className="panel"><Conversation city={city.slug} topic="general"/></section></main>; }

function Account({ city }: { city: City }) {
  const [email, setEmail] = useState<string|null>(null), [notifications, setNotifications] = useState(false), [inbox, setInbox] = useState<{id:string;title:string;body:string}[]>([]), [moderator, setModerator] = useState(false);
  const refresh = useCallback(async () => { if (!db) return; const session = (await db.auth.getSession()).data.session; setEmail(session?.user.email ?? null); if (session) setModerator(Boolean((await db.rpc("is_moderator")).data)); }, []);
  const loadInbox = useCallback(async () => { if (!db) return; const { data } = await db.from("notifications").select("id,title,body").is("read_at",null).order("created_at",{ascending:false}).limit(20); setInbox(data ?? []); }, []);
  useEffect(() => { void refresh(); void loadInbox(); setNotifications(typeof Notification !== "undefined" && Notification.permission === "granted"); }, [refresh, loadInbox]);
  async function enableNotifications() { if (!db || !email) return; const permission = await Notification.requestPermission(); if (permission !== "granted") return; const id = (await db.auth.getUser()).data.user?.id; if (id) await db.from("city_subscriptions").upsert({ user_id:id, city_slug:city.slug, notify_messages:true, notify_comments:true }); setNotifications(true); }
  if (!email) return <main><section className="hero compact"><p className="eyebrow">Mon espace</p><h1>Votre compte,<br/><span>tout simplement.</span></h1></section><Auth onDone={refresh}/></main>;
  return <main><section className="hero compact"><p className="eyebrow">Mon espace</p><h1>Bonjour&nbsp;!</h1><p>{email}{moderator && " · Modérateur"}</p></section><section className="settings panel"><h2>Mes préférences</h2><div><span><b>Ma ville</b><small>{city.name}</small></span></div><div><span><b>Notifications</b><small>Commentaires et nouveaux messages</small></span><button onClick={enableNotifications}>{notifications ? "Activées" : "Activer"}</button></div>{inbox.length > 0 && <section className="inbox"><h3>Nouveautés</h3>{inbox.map(item => <article key={item.id}><b>{item.title}</b><p>{item.body}</p></article>)}<button className="link" onClick={async () => { await db?.from("notifications").update({read_at:new Date().toISOString()}).is("read_at",null); await loadInbox(); }}>Tout marquer comme lu</button></section>}<button className="link" onClick={async () => { await db?.auth.signOut(); await refresh(); }}>Me déconnecter</button></section>{moderator && <section className="moderation panel"><h2>Modération de {city.name}</h2><p>Vous pouvez masquer ou supprimer les messages depuis les conversations et les commentaires de chaque menu.</p></section>}</main>;
}

export default function Home() {
  const [tab,setTab] = useState<Tab>("menus"), [city,setCityState] = useState<City>(cities[0]), [unread,setUnread] = useState(0);
  useEffect(() => { const raw = localStorage.getItem("atable-city"); if (!raw) return; try { const saved = JSON.parse(raw) as City; if (saved?.slug && saved?.name && saved?.source) setCityState(saved); } catch { const known = cities.find(c => c.slug === raw); if (known) setCityState(known); } }, []);
  useEffect(() => { if (!db) return; let channel: ReturnType<typeof db.channel>|undefined; db.auth.getUser().then(async ({data}) => { if (!data.user) return; setUnread((await db.from("notifications").select("id",{count:"exact",head:true}).is("read_at",null)).count ?? 0); channel = db.channel(`notifications-${data.user.id}`).on("postgres_changes",{event:"INSERT",schema:"public",table:"notifications",filter:`user_id=eq.${data.user.id}`},payload => { const item=payload.new as {title:string;body:string}; setUnread(v=>v+1); if (typeof Notification !== "undefined" && Notification.permission === "granted") new Notification(item.title,{body:item.body}); }).subscribe(); }); return () => { if (channel) void db.removeChannel(channel); }; }, []);
  function chooseCity(value: City) { setCityState(value); localStorage.setItem("atable-city",JSON.stringify(value)); }
  return <div className="app"><header className="top"><a className="brand" href="#" onClick={() => setTab("menus")}><span>à</span> table</a><span>{city.name}{unread>0 && <b className="badge">{unread}</b>}</span></header>{tab === "menus" ? <Menus city={city} setCity={chooseCity}/> : tab === "parents" ? <Parents city={city}/> : <Account city={city}/>}<nav className="bottom"><button className={tab==="menus"?"active":""} onClick={()=>setTab("menus")}><span>▦</span>Menus</button><button className={tab==="parents"?"active":""} onClick={()=>setTab("parents")}><span>◎</span>Parents</button><button className={tab==="account"?"active":""} onClick={()=>{setTab("account");setUnread(0);}}><span>♙</span>Mon espace</button></nav></div>;
}
