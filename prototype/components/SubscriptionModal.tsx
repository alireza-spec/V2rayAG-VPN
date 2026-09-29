import React, { useState } from 'react';
import { Link2, X } from 'lucide-react';
import { VPNSubscription } from '../types';

type Props = { onClose: () => void; onAdd: (item: VPNSubscription) => void };

export const SubscriptionModal: React.FC<Props> = ({ onClose, onAdd }) => {
  const [name, setName] = useState('My subscription');
  const [url, setUrl] = useState('');
  const [error, setError] = useState('');
  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!url.trim()) { setError('Enter a subscription URL to preview this flow.'); return; }
    if (!/^https?:\/\//i.test(url.trim()) && !/^(vless|vmess|ss|trojan):\/\//i.test(url.trim())) { setError('Use an https:// URL or a vless://, vmess://, ss://, or trojan:// link.'); return; }
    onAdd({ id: String(Date.now()), name: name.trim() || 'My subscription', url: url.trim(), protocolLabel: 'Imported · demo' });
  };
  return <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) onClose(); }}>
    <form className="subscription-modal" onSubmit={submit}>
      <div className="modal-heading"><div className="modal-icon"><Link2 size={20} /></div><button type="button" className="icon-button" onClick={onClose} aria-label="Close"><X size={18} /></button></div>
      <h3>Add a subscription</h3><p>Paste your provider’s subscription link. Keep it private—it can grant access to your VPN.</p>
      <label className="field-label">Subscription name<input className="form-field" value={name} onChange={e => setName(e.target.value)} placeholder="e.g. Personal VPN" /></label>
      <label className="field-label">Subscription URL<input className="form-field" type="password" autoComplete="off" value={url} onChange={e => { setUrl(e.target.value); setError(''); }} placeholder="https://… or protocol link" /></label>
      <div className="protocol-chips"><span>VLESS</span><span>VMess</span><span>Shadowsocks</span><span>Trojan</span></div>
      {error && <div className="inline-error">{error}</div>}
      <div className="privacy-note">Prototype only: this form does not fetch, save, or connect to your subscription.</div>
      <div className="modal-actions"><button type="button" className="btn btn-ghost" onClick={onClose}>Cancel</button><button className="btn btn-primary" type="submit">Preview import</button></div>
    </form>
  </div>;
};
