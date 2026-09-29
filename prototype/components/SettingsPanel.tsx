import React from 'react';
import { Bell, Link2, LockKeyhole, Smartphone, Zap } from 'lucide-react';

type Props = {
  settings: Record<string, boolean>;
  preferences: Record<string, string>;
  onToggle: (key: string) => void;
  onPreferenceChange: (key: string, value: string) => void;
};
const rows = [
  { key: 'autoConnect', icon: Zap, title: 'Auto-connect', detail: 'Remember this connection preference' },
  { key: 'killSwitch', icon: LockKeyhole, title: 'Kill switch', detail: 'Block traffic if a real tunnel drops' },
  { key: 'notifications', icon: Bell, title: 'Connection notifications', detail: 'Show connect and disconnect alerts' },
  { key: 'startOnBoot', icon: Smartphone, title: 'Start on device boot', detail: 'Remember startup preference' },
];
const selects = [
  { key: 'protocol', title: 'Preferred protocol', options: ['Automatic', 'VLESS', 'VMess', 'Shadowsocks', 'Trojan'] },
  { key: 'transport', title: 'Transport', options: ['Automatic', 'TCP', 'WebSocket', 'gRPC', 'HTTP/2'] },
  { key: 'dns', title: 'DNS preference', options: ['System default', 'Cloudflare DNS', 'Quad9 DNS'] },
];
export const SettingsPanel: React.FC<Props> = ({ settings, preferences, onToggle, onPreferenceChange }) => <div className="panel settings-panel">
  <div className="panel-heading"><div><div className="eyebrow">PREFERENCES</div><h3>Connection settings</h3></div><span className="settings-mark"><LockKeyhole size={17} /></span></div>
  <div className="settings-list">{rows.map(({ key, icon: Icon, title, detail }) => <div className="settings-row" key={key}>
    <span className="settings-icon"><Icon size={16} /></span><span className="settings-copy"><strong>{title}</strong><small>{detail}</small></span>
    <input type="checkbox" className="toggle toggle-primary" checked={Boolean(settings[key])} onChange={() => onToggle(key)} aria-label={title} />
  </div>)}</div>
  <div className="preference-controls">{selects.map(({ key, title, options }) => <label className="preference-control" key={key}><span>{title}</span><select className="select select-bordered" value={preferences[key] ?? options[0]} onChange={e => onPreferenceChange(key, e.target.value)}>{options.map(option => <option key={option} value={option}>{option}</option>)}</select></label>)}</div>
  <p className="settings-save-note">Preferences save automatically in this prototype. Native VPN actions take effect after the Android/iPhone client is integrated.</p>
  <div className="about-card"><div className="about-title"><Link2 size={15} /> About V2rayAG VPN</div><div className="about-row"><span>Source</span><a href="https://t.me/V2rayAG" target="_blank" rel="noreferrer">Telegram · @V2rayAG</a></div><div className="about-row"><span>Developer</span><strong>V2rayAG telegram channel and HashtagAlireza</strong></div></div>
</div>;
