import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Activity, Bell, ChevronDown, CircleHelp, Globe2, LayoutDashboard, Link2, MapPin, Menu, Plus, Settings, ShieldCheck, Sparkles, X } from 'lucide-react';
import { BrandMark } from './components/BrandMark';
import { ConnectCard } from './components/ConnectCard';
import { ServerList } from './components/ServerList';
import { SettingsPanel } from './components/SettingsPanel';
import { SubscriptionModal } from './components/SubscriptionModal';
import { VPNServer, VPNSubscription } from './types';

const seedServers: VPNServer[] = [
  { id: 'nl-am', name: 'Amsterdam 01', country: 'Netherlands', endpointIp: '203.0.113.8', city: 'Amsterdam', flag: '🇳🇱', protocol: 'VLESS', ping: 24, load: 31, group: 'Europe' },
  { id: 'de-fr', name: 'Frankfurt 02', country: 'Germany', endpointIp: '203.0.113.18', city: 'Frankfurt', flag: '🇩🇪', protocol: 'VMess', ping: 38, load: 44, group: 'Europe' },
  { id: 'gb-lo', name: 'London 01', country: 'United Kingdom', endpointIp: '203.0.113.29', city: 'London', flag: '🇬🇧', protocol: 'Trojan', ping: 52, load: 26, group: 'Europe' },
  { id: 'us-ny', name: 'New York 03', country: 'United States', endpointIp: '198.51.100.36', city: 'New York', flag: '🇺🇸', protocol: 'Shadowsocks', ping: 119, load: 61, group: 'Americas' },
  { id: 'jp-to', name: 'Tokyo 01', country: 'Japan', endpointIp: '198.51.100.46', city: 'Tokyo', flag: '🇯🇵', protocol: 'VLESS', ping: 146, load: 19, group: 'Asia Pacific' },
  { id: 'sg-si', name: 'Singapore 02', country: 'Singapore', endpointIp: '198.51.100.58', city: 'Singapore', flag: '🇸🇬', protocol: 'VMess', ping: 132, load: 35, group: 'Asia Pacific' },
];
const nav = [
  { id: 'home', label: 'Overview', icon: LayoutDashboard },
  { id: 'locations', label: 'Locations', icon: Globe2 },
  { id: 'subscriptions', label: 'Subscriptions', icon: Link2 },
  { id: 'settings', label: 'Settings', icon: Settings },
];
const defaultSettings = { autoConnect: false, killSwitch: true, notifications: true, startOnBoot: false };
const defaultPreferences: Record<string, string> = { protocol: 'Automatic', transport: 'Automatic', dns: 'System default' };

function App() {
  const [page, setPage] = useState('home');
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [servers] = useState(seedServers);
  const [selected, setSelected] = useState(seedServers[0]);
  const [query, setQuery] = useState('');
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [showModal, setShowModal] = useState(false);
  const [toast, setToast] = useState('');
  const [subscriptions, setSubscriptions] = useState<VPNSubscription[]>([]);
  const [settings, setSettings] = useState<Record<string, boolean>>(defaultSettings);
  const [preferences, setPreferences] = useState<Record<string, string>>(defaultPreferences);
  const filtered = useMemo(() => servers.filter(s => `${s.city} ${s.country} ${s.protocol}`.toLowerCase().includes(query.toLowerCase())), [servers, query]);

  useEffect(() => {
    let mounted = true;
    (async () => {
      try {
        await window.tasklet.sqlExec('CREATE TABLE IF NOT EXISTS v2rayag_preferences (id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
        const rows = await window.tasklet.sqlQuery("SELECT payload FROM v2rayag_preferences WHERE id = 'main'");
        if (!mounted || !rows.length) return;
        const saved = JSON.parse(String(rows[0].payload ?? '{}')) as { settings?: Record<string, boolean>; preferences?: Record<string, string>; selectedServerId?: string };
        setSettings({ ...defaultSettings, ...saved.settings });
        setPreferences({ ...defaultPreferences, ...saved.preferences });
        const savedServer = servers.find(server => server.id === saved.selectedServerId);
        if (savedServer) setSelected(savedServer);
      } catch (error) {
        console.error('Could not load saved V2rayAG preferences:', error);
      }
    })();
    return () => { mounted = false; };
  }, [servers]);

  useEffect(() => {
    if (!connected) return;
    const timer = window.setInterval(() => setSeconds(s => s + 1), 1000);
    return () => window.clearInterval(timer);
  }, [connected]);
  useEffect(() => { if (!toast) return; const timer = window.setTimeout(() => setToast(''), 3200); return () => window.clearTimeout(timer); }, [toast]);
  const duration = `${String(Math.floor(seconds / 3600)).padStart(2, '0')}:${String(Math.floor((seconds % 3600) / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
  const effectiveServer = preferences.protocol === 'Automatic' ? selected : { ...selected, protocol: preferences.protocol };
  const persistPreferences = (nextSettings: Record<string, boolean>, nextPreferences: Record<string, string>, selectedServerId: string) => {
    const payload = JSON.stringify({ settings: nextSettings, preferences: nextPreferences, selectedServerId }).replaceAll("'", "''");
    window.tasklet.sqlExec(`INSERT OR REPLACE INTO v2rayag_preferences (id, payload) VALUES ('main', '${payload}')`).catch(error => console.error('Could not save V2rayAG preferences:', error));
  };
  const notify = (message: string) => { if (settings.notifications) setToast(message); };
  const selectServer = (server: VPNServer) => {
    setSelected(server);
    persistPreferences(settings, preferences, server.id);
  };
  const toggleConnection = () => {
    if (connecting) return;
    if (connected) { setConnected(false); setSeconds(0); notify('Demo connection disconnected'); return; }
    setConnecting(true);
    window.setTimeout(() => { setConnecting(false); setConnected(true); notify('Demo connected · no VPN traffic is routed'); }, 1100);
  };
  const addSubscription = (item: VPNSubscription) => { setSubscriptions(prev => [...prev, item]); setShowModal(false); notify('Subscription flow previewed · not imported'); };
  const toggleSetting = (key: string) => setSettings(prev => {
    const next = { ...prev, [key]: !prev[key] };
    persistPreferences(next, preferences, selected.id);
    return next;
  });
  const changePreference = (key: string, value: string) => setPreferences(prev => {
    const next = { ...prev, [key]: value };
    persistPreferences(settings, next, selected.id);
    return next;
  });
  const timeLabel = new Intl.DateTimeFormat('en', { weekday: 'short', month: 'short', day: 'numeric' }).format(new Date());

  return <div className="vpn-app" data-page={page}>
    <aside className="sidebar">
      <div className="brand-lockup"><BrandMark /><div><strong>V2rayAG</strong><span>SECURE CONNECTION</span></div></div>
      <div className="sidebar-caption">WORKSPACE</div>
      <nav className="side-nav">{nav.map(({ id, label, icon: Icon }) => <button key={id} className={`nav-item ${page === id ? 'nav-active' : ''}`} onClick={() => setPage(id)}><Icon size={18} /><span>{label}</span>{page === id && <i />}</button>)}</nav>
      <div className="sidebar-bottom"><div className="sidebar-status"><span className="status-dot" /><div><strong>Prototype mode</strong><small>Tunnel not active</small></div></div><div className="sidebar-help"><CircleHelp size={16} /><span>Help & support</span></div><div className="version-note">V2rayAG VPN · UI concept</div></div>
    </aside>

    <main className="main-area">
      <header className="topbar"><button className="mobile-menu icon-button" aria-label="Open navigation" onClick={() => setMobileMenuOpen(value => !value)}><Menu size={20} /></button><div className="mobile-brand"><strong>V2rayAG</strong><span>Freedom, in one tap</span></div><div className="breadcrumb">V2rayAG <span>/</span> {nav.find(n => n.id === page)?.label}</div><div className="topbar-right"><span className="environment-chip"><span className="status-dot" /> Prototype</span><span className="date-label">{timeLabel}</span><button className="icon-button mobile-settings" aria-label="Settings" onClick={() => setPage('settings')}><Settings size={19} /></button><button className="icon-button notification-btn" aria-label="Notifications" onClick={() => notify('You’re all caught up · demo notifications')}><Bell size={18} /><i /></button><span className="avatar">LS</span></div>{mobileMenuOpen && <div className="mobile-menu-popover">{nav.map(({ id, label, icon: Icon }) => <button key={id} onClick={() => { setPage(id); setMobileMenuOpen(false); }}><Icon size={16} />{label}</button>)}</div>}</header>

      <div className="content-wrap">
        {page !== 'home' && <div className="prototype-alert"><Sparkles size={15} /><span><strong>Interactive UI prototype</strong> — connection and network readings are simulated; no VPN traffic is routed.</span><button className="alert-close" onClick={e => e.currentTarget.parentElement?.remove()} aria-label="Dismiss"><X size={14} /></button></div>}

        {page === 'home' && <>
          <div className="page-intro"><div><div className="eyebrow">PRIVACY CONTROL CENTER</div><h1>Connection overview</h1><p>Manage your route, server locations, and connection preferences.</p></div><div className="page-intro-actions"><span className="demo-pill"><span className="status-dot" /> UI preview</span><button className="btn btn-outline subscription-cta" onClick={() => setShowModal(true)}><Plus size={16} /> Add subscription</button></div></div>
          <div className="dashboard-grid">
            <div className="dashboard-main"><ConnectCard connected={connected} connecting={connecting} server={effectiveServer} transport={preferences.transport} duration={duration} onToggle={toggleConnection} /><button className="mobile-route-shortcut" onClick={() => setPage('locations')}><span className="route-flag">{selected.flag}</span><span><strong>{selected.city}</strong><small>{effectiveServer.protocol} · {selected.ping} ms sample</small></span><span className="route-shortcut-arrow">›</span></button><ServerList servers={servers.slice(0, 3)} selectedId={selected.id} onSelect={selectServer} query="" onQuery={setQuery} compact /></div>
            <aside className="dashboard-side"><div className="side-card current-location"><div className="side-card-title"><span>ACTIVE LOCATION</span><button onClick={() => setPage('locations')} aria-label="Browse locations"><ChevronDown size={16} /></button></div><div className="location-large"><span>{selected.flag}</span><div><strong>{selected.city}</strong><small>{selected.country}</small></div></div><div className="side-divider"/><div className="location-stat"><span><Activity size={15} /> Latency</span><strong>{selected.ping} ms <em>sample</em></strong></div><div className="location-stat"><span><Globe2 size={15} /> Protocol</span><strong>{selected.protocol}</strong></div><button className="text-action" onClick={() => setPage('locations')}>Change location <span>→</span></button></div>
            <div className="side-card subscription-summary"><div className="summary-top"><div className="summary-icon"><Link2 size={17} /></div><span className="eyebrow">SUBSCRIPTIONS</span></div><strong>{subscriptions.length ? subscriptions.length : 'No'} provider{subscriptions.length === 1 ? '' : 's'} added</strong><p>Bring your own subscription to see your profiles here.</p><button className="text-action" onClick={() => subscriptions.length ? setPage('subscriptions') : setShowModal(true)}>{subscriptions.length ? 'Manage subscriptions' : 'Add a subscription'} <span>→</span></button></div>
            </aside>
          </div>
          <div className="bottom-note"><ShieldCheck size={16} /><span>V2rayAG is designed around your own provider. Subscription URLs are sensitive credentials—never share them publicly.</span></div>
        </>}

        {page === 'locations' && <><div className="page-intro"><div><div className="eyebrow">SERVER SELECTOR</div><h1>Locations</h1><p>Choose an exit location. Latencies shown here are sample values.</p></div><div className="location-count"><MapPin size={16} /> {servers.length} locations</div></div><div className="locations-layout"><div className="panel location-full"><ServerList servers={filtered} selectedId={selected.id} onSelect={s => { selectServer(s); notify(`${s.city} selected`); }} query={query} onQuery={setQuery} /></div><div className="side-card location-info"><div className="info-orbit"><BrandMark small /></div><div className="eyebrow">SMART ROUTING</div><h3>Pick a route that feels right.</h3><p>In a working build, location availability, server load, and round-trip latency will come from your subscription and real network checks.</p><div className="info-pill"><Activity size={15} /> Sample ping: {selected.ping} ms</div></div></div></>}

        {page === 'subscriptions' && <><div className="page-intro"><div><div className="eyebrow">YOUR PROVIDERS</div><h1>Subscriptions</h1><p>Import VLESS, VMess, Shadowsocks, Trojan and subscription URLs.</p></div><button className="btn btn-primary" onClick={() => setShowModal(true)}><Plus size={16} /> Add subscription</button></div><div className="panel subscriptions-panel">{subscriptions.length === 0 ? <div className="empty-subscriptions"><div className="empty-art"><Link2 size={25} /></div><h3>Your profiles will show up here</h3><p>Add a provider subscription to preview the import flow. For your security, don’t paste a live URL into this prototype.</p><button className="btn btn-primary" onClick={() => setShowModal(true)}><Plus size={16} /> Add subscription</button><div className="supported-protocols"><span>VLESS</span><span>VMess</span><span>Shadowsocks</span><span>Trojan</span></div></div> : <div className="subscription-items">{subscriptions.map(item => <div className="subscription-item" key={item.id}><span className="settings-icon"><Link2 size={17} /></span><div><strong>{item.name}</strong><small>{item.protocolLabel} · URL kept only in this screen’s memory</small></div><span className="badge badge-warning">Preview only</span><button className="icon-button" onClick={() => setSubscriptions(prev => prev.filter(s => s.id !== item.id))} aria-label="Remove subscription"><X size={17} /></button></div>)}</div>}</div><div className="security-callout"><ShieldCheck size={18} /><div><strong>Keep your subscription private</strong><p>Subscription links are credentials. The production app should store them securely on-device and never send them to an unrelated server.</p></div></div></>}

        {page === 'settings' && <><div className="page-intro"><div><div className="eyebrow">PERSONALIZE YOUR APP</div><h1>Settings</h1><p>Connection preferences and app behavior.</p></div></div><div className="settings-layout"><SettingsPanel settings={settings} preferences={preferences} onToggle={toggleSetting} onPreferenceChange={changePreference} /><div className="side-card settings-tip"><div className="settings-tip-icon"><ShieldCheck size={22} /></div><div className="eyebrow">DESIGNED FOR YOUR PRIVACY</div><h3>Your traffic stays yours.</h3><p>Preferences are editable and saved here. Device-level auto-connect, kill switch, and traffic notifications require the native Android and iPhone VPN integrations.</p><div className="tip-rule"/><div className="tip-row"><span>Android</span><strong>VPNService</strong></div><div className="tip-row"><span>iPhone</span><strong>Network Extension</strong></div><div className="tip-row"><span>Web</span><strong>Management only</strong></div></div></div></>}
      </div>
      <footer className="app-footer"><span><span className="status-dot" /> All systems illustrative</span><span>Privacy first · V2rayAG</span></footer>
    </main>
    <nav className="mobile-bottom-nav">{nav.map(({ id, label, icon: Icon }) => <button key={id} className={page === id ? 'mobile-active' : ''} onClick={() => setPage(id)}><Icon size={19} /><span>{label}</span></button>)}</nav>
    {showModal && <SubscriptionModal onClose={() => setShowModal(false)} onAdd={addSubscription} />}
    {toast && <div className="toast-message"><ShieldCheck size={16} />{toast}<button onClick={() => setToast('')} aria-label="Close"><X size={14} /></button></div>}
  </div>;
}

createRoot(document.getElementById('root')!).render(<App />);
